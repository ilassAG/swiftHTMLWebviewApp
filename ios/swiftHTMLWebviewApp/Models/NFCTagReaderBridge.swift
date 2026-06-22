//
//  NFCTagReaderBridge.swift
//  swiftHTMLWebviewApp
//
//  One-shot CoreNFC tag reader for the JavaScript bridge.
//

import CoreNFC
import Foundation

final class NFCTagReaderBridge: NSObject, ObservableObject {
    private var session: NFCTagReaderSession?
    private var request: [String: Any] = [:]
    private var completion: (([String: Any]) -> Void)?
    private var timeoutWorkItem: DispatchWorkItem?
    private var completed = false

    @MainActor
    func read(request: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        guard NFCTagReaderSession.readingAvailable else {
            completion(NFCPayload.errorResponse(request: request, error: "NFC tag reading is not available on this device."))
            return
        }
        guard session == nil else {
            completion(NFCPayload.errorResponse(request: request, error: "An NFC tag read session is already active."))
            return
        }

        self.request = request
        self.completion = completion
        self.completed = false

        // FeliCa / ISO 18092 polling needs additional system-code entitlements.
        // Keep the default reader focused on common NFC/NDEF tags that are covered
        // by the NDEF + TAG reader-session formats entitlement.
        let polling: NFCTagReaderSession.PollingOption = [.iso14443, .iso15693]
        guard let session = NFCTagReaderSession(pollingOption: polling, delegate: self, queue: .main) else {
            completion(NFCPayload.errorResponse(request: request, error: "Could not create an NFC tag reader session."))
            return
        }
        session.alertMessage = stringValue(request["message"]).isEmpty
            ? "NFC-Tag an die obere Kante des iPhones halten."
            : stringValue(request["message"])
        self.session = session
        scheduleTimeout(seconds: doubleValue(request["timeoutSeconds"]) ?? (doubleValue(request["timeoutMs"]).map { $0 / 1000.0 } ?? 0))
        session.begin()
    }

    @MainActor
    func shutdown() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        session?.invalidate()
        session = nil
        request = [:]
        completion = nil
        completed = false
    }

    private func scheduleTimeout(seconds: Double) {
        timeoutWorkItem?.cancel()
        guard seconds > 0 else { return }
        let timeout = min(max(seconds, 1), 60)
        let workItem = DispatchWorkItem { [weak self] in
            self?.session?.invalidate(errorMessage: "NFC scan timed out.")
        }
        timeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: workItem)
    }

    private func handle(tag: NFCTag, session: NFCTagReaderSession) {
        let tagInfo = tagPayload(tag)
        guard let ndefTag = ndefTag(for: tag) else {
            var response = successResponse()
            response["tag"] = tagInfo
            response["ndef"] = NFCPayload.ndefUnavailablePayload()
            complete(response: response, alertMessage: "NFC-Tag gelesen.")
            return
        }

        ndefTag.queryNDEFStatus { [weak self] status, capacity, error in
            guard let self else { return }
            if let error {
                self.complete(response: self.errorResponse(error: error.localizedDescription), alertMessage: "NFC-Tag konnte nicht gelesen werden.")
                return
            }

            if status == .notSupported {
                var response = self.successResponse()
                var enrichedTag = tagInfo
                enrichedTag["ndefAvailable"] = false
                response["tag"] = enrichedTag
                response["ndef"] = NFCPayload.ndefUnavailablePayload(
                    status: self.ndefStatusName(status),
                    capacityBytes: capacity
                )
                self.complete(response: response, alertMessage: "NFC-Tag gelesen.")
                return
            }

            ndefTag.readNDEF { message, error in
                if let error {
                    self.complete(response: self.errorResponse(error: error.localizedDescription), alertMessage: "NDEF-Daten konnten nicht gelesen werden.")
                    return
                }

                var response = self.successResponse()
                var enrichedTag = tagInfo
                enrichedTag["ndefAvailable"] = true
                enrichedTag["ndefWritable"] = status == .readWrite
                enrichedTag["ndefStatus"] = self.ndefStatusName(status)
                enrichedTag["ndefCapacityBytes"] = capacity
                response["tag"] = enrichedTag
                response["ndef"] = self.ndefPayload(message: message, status: status, capacity: capacity)
                self.complete(response: response, alertMessage: "NFC-Tag gelesen.")
            }
        }
    }

    private func complete(response: [String: Any], alertMessage: String) {
        DispatchQueue.main.async {
            guard !self.completed else { return }
            self.completed = true
            self.timeoutWorkItem?.cancel()
            self.timeoutWorkItem = nil
            self.session?.alertMessage = alertMessage
            self.session?.invalidate()
            self.session = nil
            let completion = self.completion
            self.completion = nil
            self.request = [:]
            completion?(response)
        }
    }

    private func ndefTag(for tag: NFCTag) -> NFCNDEFTag? {
        switch tag {
        case .miFare(let tag): return tag
        case .iso7816(let tag): return tag
        case .iso15693(let tag): return tag
        case .feliCa(let tag): return tag
        @unknown default: return nil
        }
    }

    private func tagPayload(_ tag: NFCTag) -> [String: Any] {
        var payload: [String: Any] = [:]
        switch tag {
        case .miFare(let tag):
            var extra: [String: Any] = [
                "mifareFamily": mifareFamilyName(tag.mifareFamily)
            ]
            if let historicalBytes = tag.historicalBytes {
                extra["historicalBytesHex"] = NFCPayload.hex(historicalBytes)
                extra["historicalBytesBase64"] = historicalBytes.base64EncodedString()
            }
            payload = NFCPayload.tagPayload(type: "miFare", identifier: tag.identifier, extra: extra)
        case .iso7816(let tag):
            var extra: [String: Any] = [
                "initialSelectedAID": tag.initialSelectedAID
            ]
            if let applicationData = tag.applicationData {
                extra["applicationDataHex"] = NFCPayload.hex(applicationData)
                extra["applicationDataBase64"] = applicationData.base64EncodedString()
            }
            if let historicalBytes = tag.historicalBytes {
                extra["historicalBytesHex"] = NFCPayload.hex(historicalBytes)
                extra["historicalBytesBase64"] = historicalBytes.base64EncodedString()
            }
            payload = NFCPayload.tagPayload(type: "iso7816", identifier: tag.identifier, extra: extra)
        case .iso15693(let tag):
            payload = NFCPayload.tagPayload(type: "iso15693", identifier: tag.identifier, extra: [
                "icManufacturerCode": tag.icManufacturerCode,
                "icSerialNumberHex": NFCPayload.hex(tag.icSerialNumber),
                "icSerialNumberBase64": tag.icSerialNumber.base64EncodedString()
            ])
        case .feliCa(let tag):
            payload = NFCPayload.tagPayload(type: "feliCa", identifier: tag.currentIDm, extra: [
                "systemCodeHex": NFCPayload.hex(tag.currentSystemCode),
                "systemCodeBase64": tag.currentSystemCode.base64EncodedString()
            ])
        @unknown default:
            payload["type"] = "unknown"
        }
        return payload
    }

    private func ndefPayload(message: NFCNDEFMessage?, status: NFCNDEFStatus, capacity: Int) -> [String: Any] {
        let messages = message.map { ndefMessage in
            [
                ndefMessage.records.enumerated().map { index, record in
                    recordInput(record, index: index)
                }
            ]
        } ?? []
        return NFCPayload.ndefPayload(
            status: ndefStatusName(status),
            capacityBytes: capacity,
            messages: messages
        )
    }

    private func recordInput(_ record: NFCNDEFPayload, index: Int) -> NFCPayload.RecordInput {
        NFCPayload.RecordInput(
            index: index,
            typeNameFormatRawValue: Int(record.typeNameFormat.rawValue),
            type: record.type,
            identifier: record.identifier,
            payload: record.payload
        )
    }

    private func successResponse() -> [String: Any] {
        NFCPayload.successResponse(request: request)
    }

    private func errorResponse(error: String) -> [String: Any] {
        NFCPayload.errorResponse(request: request, error: error)
    }

    private func ndefStatusName(_ status: NFCNDEFStatus) -> String {
        switch status {
        case .notSupported: return "notSupported"
        case .readOnly: return "readOnly"
        case .readWrite: return "readWrite"
        @unknown default: return "unknown"
        }
    }

    private func mifareFamilyName(_ family: NFCMiFareFamily) -> String {
        switch family {
        case .unknown: return "unknown"
        case .ultralight: return "ultralight"
        case .plus: return "plus"
        case .desfire: return "desfire"
        @unknown default: return "unknown"
        }
    }
}

extension NFCTagReaderBridge: NFCTagReaderSessionDelegate {
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        session.alertMessage = stringValue(request["message"]).isEmpty
            ? "NFC-Tag an die obere Kante des iPhones halten."
            : stringValue(request["message"])
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        DispatchQueue.main.async {
            guard !self.completed else { return }
            self.timeoutWorkItem?.cancel()
            self.timeoutWorkItem = nil
            self.session = nil
            let completion = self.completion
            self.completion = nil
            let nsError = error as NSError
            var response = self.errorResponse(error: error.localizedDescription)
            if nsError.domain == NFCReaderError.errorDomain
                && nsError.code == NFCReaderError.readerSessionInvalidationErrorUserCanceled.rawValue {
                response["cancelled"] = true
                response["error"] = "NFC tag reading was cancelled."
            }
            self.request = [:]
            completion?(response)
        }
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard tags.count == 1, let tag = tags.first else {
            session.alertMessage = "Bitte nur einen NFC-Tag gleichzeitig halten."
            session.restartPolling()
            return
        }

        session.connect(to: tag) { [weak self] error in
            guard let self else { return }
            if let error {
                self.complete(response: self.errorResponse(error: error.localizedDescription), alertMessage: "NFC-Tag konnte nicht verbunden werden.")
                return
            }
            self.handle(tag: tag, session: session)
        }
    }
}
