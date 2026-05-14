//
//  TapToPayBridge.swift
//  swiftHTMLWebviewApp
//
//  Optional Stripe Terminal / Tap to Pay bridge.
//  Without StripeTerminal linked, the app still builds and reports Tap to Pay as unavailable.
//

import Foundation

#if canImport(StripeTerminal)
import StripeTerminal

final class TapToPayBridge: NSObject, ObservableObject {
    enum Phase {
        case preparing
        case connecting
        case ready
        case presenting
        case processing
    }

    private final class StaticConnectionTokenProvider: NSObject, ConnectionTokenProvider {
        var tokenSecret: String?

        func fetchConnectionToken(_ completion: @escaping ConnectionTokenCompletionBlock) {
            guard let tokenSecret, !tokenSecret.isEmpty else {
                completion(nil, TapToPayBridge.makeError("Kein Stripe Terminal Connection Token vorhanden."))
                return
            }
            completion(tokenSecret, nil)
        }
    }

    private let tokenProvider = StaticConnectionTokenProvider()
    private var discoverCancelable: Cancelable?
    private var collectCancelable: Cancelable?
    private var pendingReaders: [Reader] = []
    private var readerConnectionCompletion: ((Error?) -> Void)?
    private var readerConnectionTimeout: DispatchWorkItem?
    private var pendingLocationId: String?
    private var pendingMerchantDisplayName: String?
    private var isConnectingReader = false
    private var didConfigureTerminal = false

    func availabilityPayload(request: [String: Any]) -> [String: Any] {
        configureTerminalIfNeeded()
        let requestId = request["requestId"] as? String
        let supportError = tapToPaySupportError()
        let available = supportError == nil
        var payload: [String: Any] = [
            "action": "tapToPayAvailability",
            "available": available,
            "readerType": "apple_built_in"
        ]
        if let requestId { payload["requestId"] = requestId }
        if let supportError { payload["reason"] = supportError.localizedDescription }
        return payload
    }

    func collect(
        request: [String: Any],
        onPhase: @escaping (Phase) -> Void,
        completion: @escaping ([String: Any]) -> Void
    ) {
        configureTerminalIfNeeded()
        onPhase(.preparing)
        print("TapToPay: collect requested paymentId=\(request["paymentId"] as? String ?? "-")")

        guard let clientSecret = request["clientSecret"] as? String, !clientSecret.isEmpty else {
            completion(errorPayload(action: "tapToPayCollect", request: request, message: "clientSecret fehlt."))
            return
        }
        guard let tokenSecret = request["connectionTokenSecret"] as? String, !tokenSecret.isEmpty else {
            completion(errorPayload(action: "tapToPayCollect", request: request, message: "connectionTokenSecret fehlt."))
            return
        }
        guard let locationId = request["locationId"] as? String, !locationId.isEmpty else {
            completion(errorPayload(action: "tapToPayCollect", request: request, message: "Terminal Location fehlt."))
            return
        }

        if let supportError = tapToPaySupportError() {
            completion(errorPayload(
                action: "tapToPayCollect",
                request: request,
                error: supportError
            ))
            return
        }

        tokenProvider.tokenSecret = tokenSecret
        onPhase(.connecting)
        ensureReaderConnected(locationId: locationId, merchantDisplayName: request["merchantDisplayName"] as? String) { [weak self] error in
            guard let self else { return }
            if let error {
                completion(self.errorPayload(action: "tapToPayCollect", request: request, error: error))
                return
            }
            self.collectPayment(
                clientSecret: clientSecret,
                request: request,
                onPhase: onPhase,
                completion: completion
            )
        }
    }

    private func tapToPaySupportError() -> Error? {
        switch Terminal.shared.supportsReaders(
            of: .appleBuiltIn,
            discoveryMethod: .localMobile,
            simulated: false
        ) {
        case .success:
            return nil
        case .failure(let error):
            return error
        }
    }

    private func configureTerminalIfNeeded() {
        guard !didConfigureTerminal else { return }
        Terminal.setTokenProvider(tokenProvider)
        Terminal.shared.delegate = self
        Terminal.shared.logLevel = .verbose
        Terminal.setLogListener { logline in
            print("StripeTerminal: \(logline)")
        }
        didConfigureTerminal = true
        print("TapToPay: Stripe Terminal configured")
    }

    private func ensureReaderConnected(
        locationId: String,
        merchantDisplayName: String?,
        completion: @escaping (Error?) -> Void
    ) {
        if Terminal.shared.connectionStatus == .connected,
           Terminal.shared.connectedReader != nil {
            print("TapToPay: Apple Built-In reader already connected")
            completion(nil)
            return
        }
        if readerConnectionCompletion != nil || isConnectingReader || Terminal.shared.connectionStatus == .connecting {
            print("TapToPay: reader connection already in progress")
            completion(Self.makeError("Tap to Pay verbindet gerade mit dem iPhone-Reader. Bitte einen Moment warten."))
            return
        }

        resetPendingReaderConnection()
        pendingLocationId = locationId
        pendingMerchantDisplayName = merchantDisplayName
        readerConnectionCompletion = completion

        let discoveryConfig = DiscoveryConfiguration(discoveryMethod: .localMobile, simulated: false)
        discoveryConfig.timeout = 20
        pendingReaders.removeAll()
        print("TapToPay: start local mobile reader discovery locationId=\(locationId)")

        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            print("TapToPay: reader discovery/connect timed out")
            self.discoverCancelable?.cancel { _ in }
            self.finishReaderConnection(Self.makeError("Tap to Pay konnte den iPhone-Reader nicht rechtzeitig aktivieren. Bitte erneut versuchen."))
        }
        readerConnectionTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 90, execute: timeout)

        discoverCancelable = Terminal.shared.discoverReaders(discoveryConfig, delegate: self) { [weak self] error in
            guard let self else { return }
            print("TapToPay: discovery completion error=\(error?.localizedDescription ?? "nil")")
            if let error, self.readerConnectionCompletion != nil {
                self.finishReaderConnection(error)
                return
            }
        }

        if discoverCancelable == nil {
            finishReaderConnection(Self.makeError("Tap to Pay Reader-Discovery konnte nicht gestartet werden."))
        }
    }

    private func connectFirstDiscoveredReaderIfNeeded() {
        guard readerConnectionCompletion != nil, !isConnectingReader else { return }
        guard let locationId = pendingLocationId else { return }
        guard let reader = pendingReaders.first(where: { $0.deviceType == .appleBuiltIn }) ?? pendingReaders.first else {
            return
        }

        isConnectingReader = true
        print("TapToPay: connecting reader type=\(reader.deviceType) serial=\(reader.serialNumber)")

        let connectionConfig = LocalMobileConnectionConfiguration(
            locationId: locationId,
            merchantDisplayName: pendingMerchantDisplayName,
            onBehalfOf: nil
        )
        Terminal.shared.connectLocalMobileReader(
            reader,
            delegate: self,
            connectionConfig: connectionConfig
        ) { [weak self] _, connectError in
            guard let self else { return }
            print("TapToPay: connect completed error=\(connectError?.localizedDescription ?? "nil")")
            self.finishReaderConnection(connectError)
        }
    }

    private func collectPayment(
        clientSecret: String,
        request: [String: Any],
        onPhase: @escaping (Phase) -> Void,
        completion: @escaping ([String: Any]) -> Void
    ) {
        onPhase(.ready)
        print("TapToPay: retrieve PaymentIntent")
        Terminal.shared.retrievePaymentIntent(clientSecret: clientSecret) { [weak self] paymentIntent, retrieveError in
            guard let self else { return }
            if let retrieveError {
                print("TapToPay: retrieve failed \(retrieveError.localizedDescription)")
                completion(self.errorPayload(action: "tapToPayCollect", request: request, error: retrieveError))
                return
            }
            guard let paymentIntent else {
                completion(self.errorPayload(action: "tapToPayCollect", request: request, message: "PaymentIntent konnte nicht geladen werden."))
                return
            }
            let collectConfig = CollectConfiguration(skipTipping: true)
            onPhase(.presenting)
            print("TapToPay: collectPaymentMethod start")
            self.collectCancelable = Terminal.shared.collectPaymentMethod(paymentIntent, collectConfig: collectConfig) { [weak self] collectedIntent, collectError in
                guard let self else { return }
                self.collectCancelable = nil
                if let collectError {
                    print("TapToPay: collect failed \(collectError.localizedDescription)")
                    let nsError = collectError as NSError
                    if nsError.code == ErrorCode.canceled.rawValue {
                        completion(self.cancelPayload(request: request, reason: collectError.localizedDescription))
                    } else {
                        completion(self.errorPayload(action: "tapToPayCollect", request: request, error: collectError))
                    }
                    return
                }
                guard let collectedIntent else {
                    completion(self.errorPayload(action: "tapToPayCollect", request: request, message: "Keine Karte eingelesen."))
                    return
                }
                onPhase(.processing)
                print("TapToPay: processPayment start")
                Terminal.shared.processPayment(collectedIntent) { [weak self] processedIntent, processError in
                    guard let self else { return }
                    if let processError {
                        print("TapToPay: process failed \(processError.localizedDescription)")
                        completion(self.errorPayload(action: "tapToPayCollect", request: request, error: processError))
                        return
                    }
                    guard let processedIntent else {
                        completion(self.errorPayload(action: "tapToPayCollect", request: request, message: "PaymentIntent wurde nicht verarbeitet."))
                        return
                    }
                    print("TapToPay: process completed status=\(processedIntent.status)")
                    completion(self.successPayload(request: request, paymentIntent: processedIntent))
                }
            }
        }
    }

    private func finishReaderConnection(_ error: Error?) {
        readerConnectionTimeout?.cancel()
        readerConnectionTimeout = nil
        let completion = readerConnectionCompletion
        resetPendingReaderConnection()
        completion?(error)
    }

    private func resetPendingReaderConnection() {
        readerConnectionCompletion = nil
        pendingLocationId = nil
        pendingMerchantDisplayName = nil
        isConnectingReader = false
        discoverCancelable = nil
        readerConnectionTimeout?.cancel()
        readerConnectionTimeout = nil
    }

    private func successPayload(request: [String: Any], paymentIntent: PaymentIntent) -> [String: Any] {
        var payload: [String: Any] = [
            "action": "tapToPayCollect",
            "paymentIntentId": paymentIntent.stripeId,
            "status": "\(paymentIntent.status)",
            "nativeStatus": "processed"
        ]
        if let requestId = request["requestId"] as? String { payload["requestId"] = requestId }
        if let paymentId = request["paymentId"] as? String { payload["paymentId"] = paymentId }
        return payload
    }

    private func cancelPayload(request: [String: Any], reason: String) -> [String: Any] {
        var payload: [String: Any] = [
            "action": "tapToPayCollect",
            "cancelled": true,
            "reason": reason
        ]
        if let requestId = request["requestId"] as? String { payload["requestId"] = requestId }
        if let paymentId = request["paymentId"] as? String { payload["paymentId"] = paymentId }
        return payload
    }

    private func errorPayload(action: String, request: [String: Any], message: String) -> [String: Any] {
        var payload: [String: Any] = ["action": action, "error": message]
        if let requestId = request["requestId"] as? String { payload["requestId"] = requestId }
        if let paymentId = request["paymentId"] as? String { payload["paymentId"] = paymentId }
        return payload
    }

    private func errorPayload(action: String, request: [String: Any], error: Error) -> [String: Any] {
        errorPayload(action: action, request: request, message: error.localizedDescription)
    }

    private static func makeError(_ message: String) -> NSError {
        NSError(domain: "com.ilass.swiftHTMLWebviewApp.tap-to-pay", code: 1, userInfo: [
            NSLocalizedDescriptionKey: message
        ])
    }
}

extension TapToPayBridge: DiscoveryDelegate {
    func terminal(_ terminal: Terminal, didUpdateDiscoveredReaders readers: [Reader]) {
        pendingReaders = readers
        let summary = readers
            .map { "\($0.deviceType)/\($0.serialNumber)" }
            .joined(separator: ", ")
        print("TapToPay: discovered readers count=\(readers.count) [\(summary)]")
        connectFirstDiscoveredReaderIfNeeded()
    }
}

extension TapToPayBridge: TerminalDelegate {
    func terminal(_ terminal: Terminal, didReportUnexpectedReaderDisconnect reader: Reader) {
        print("Tap to Pay reader disconnected unexpectedly: \(reader.serialNumber)")
    }
}

extension TapToPayBridge: LocalMobileReaderDelegate {
    func localMobileReader(_ reader: Reader, didStartInstallingUpdate update: ReaderSoftwareUpdate, cancelable: Cancelable?) {}
    func localMobileReader(_ reader: Reader, didReportReaderSoftwareUpdateProgress progress: Float) {}
    func localMobileReader(_ reader: Reader, didFinishInstallingUpdate update: ReaderSoftwareUpdate?, error: Error?) {}
    func localMobileReaderDidAcceptTermsOfService(_ reader: Reader) {}
    func localMobileReader(_ reader: Reader, didRequestReaderInput inputOptions: ReaderInputOptions = []) {}
    func localMobileReader(_ reader: Reader, didRequestReaderDisplayMessage displayMessage: ReaderDisplayMessage) {}
}


#else

final class TapToPayBridge: NSObject, ObservableObject {
    enum Phase {
        case preparing
        case connecting
        case ready
        case presenting
        case processing
    }

    func availabilityPayload(request: [String: Any]) -> [String: Any] {
        var payload: [String: Any] = [
            "action": "tapToPayAvailability",
            "available": false,
            "readerType": "apple_built_in",
            "reason": "StripeTerminal SDK is not linked in this build."
        ]
        if let requestId = request["requestId"] as? String { payload["requestId"] = requestId }
        return payload
    }

    func collect(
        request: [String: Any],
        onPhase: @escaping (Phase) -> Void,
        completion: @escaping ([String: Any]) -> Void
    ) {
        var payload: [String: Any] = [
            "action": "tapToPayCollect",
            "error": "StripeTerminal SDK is not linked in this build."
        ]
        if let requestId = request["requestId"] as? String { payload["requestId"] = requestId }
        if let paymentId = request["paymentId"] as? String { payload["paymentId"] = paymentId }
        completion(payload)
    }
}

#endif
