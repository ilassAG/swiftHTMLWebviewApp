//
//  NATSBridge.swift
//  swiftHTMLWebviewApp
//

import Foundation
import Security

protocol NATSCredentialStore {
    func store(_ credential: String, method: NATSAuthMethod) throws
    func hasCredential() -> Bool
    func loadCredential() -> String?
    func clear()
}

final class NATSKeychainStore: NATSCredentialStore {
    private let service = "swiftHTMLWebviewApp.nats"
    private let account = "default"

    func store(_ credential: String, method: NATSAuthMethod) throws {
        let data = credential.data(using: .utf8) ?? Data()
        clear()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrDescription as String: method.rawValue,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func hasCredential() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    func loadCredential() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

protocol NATSConnectionDriver {
    var connected: Bool { get }
    func connect(
        settings: NATSSettings,
        appUUID: String,
        credential: String?,
        commandHandler: @escaping NATSCommandHandler
    ) -> String?
    func disconnect()
    func publish(subject: String, payload: Data) -> String?
}

typealias NATSCommandHandler = @Sendable (_ subject: String, _ payload: Data, _ replyTo: String?) -> Void
typealias NATSCommandExecutor = @MainActor (_ command: [String: Any], _ completion: @escaping ([String: Any]) -> Void) -> Void

final class NATSUnavailableConnectionDriver: NATSConnectionDriver {
    private(set) var connected = false

    func connect(
        settings: NATSSettings,
        appUUID: String,
        credential: String?,
        commandHandler: @escaping NATSCommandHandler
    ) -> String? {
        connected = false
        return "NATS transport is not linked in this build."
    }

    func disconnect() {
        connected = false
    }

    func publish(subject: String, payload: Data) -> String? {
        "NATS transport is not linked in this build."
    }
}

@MainActor
final class NATSBridge: ObservableObject {
    private let settings: AppSettings
    private let credentialStore: NATSCredentialStore
    private let connection: NATSConnectionDriver
    private var commandExecutor: NATSCommandExecutor?
    private var lastError = ""
    private var autoConnectInFlight = false

    init(
        settings: AppSettings = .shared,
        credentialStore: NATSCredentialStore = NATSKeychainStore(),
        connection: NATSConnectionDriver = NATSBridge.makeDefaultConnectionDriver()
    ) {
        self.settings = settings
        self.credentialStore = credentialStore
        self.connection = connection
    }

    nonisolated private static func makeDefaultConnectionDriver() -> NATSConnectionDriver {
        #if canImport(Nats)
        return NATSSwiftConnectionDriver()
        #else
        return NATSUnavailableConnectionDriver()
        #endif
    }

    func configureCommandExecutor(_ executor: @escaping NATSCommandExecutor) {
        commandExecutor = executor
    }

    var isConnected: Bool {
        connection.connected
    }

    func statusSnapshot() -> [String: Any] {
        settings.natsConfiguration.redactedSnapshot(
            appUUID: settings.appUUIDString,
            credentialSet: credentialStore.hasCredential(),
            connected: connection.connected,
            lastError: lastError
        )
    }

    func provision(request: [String: Any]) -> [String: Any] {
        guard hasValidToken(request) else {
            return BridgeResponse.error(
                request: request,
                action: "natsProvision",
                message: "securityToken is required for natsProvision."
            )
        }
        guard let natsPayload = request["nats"] as? [String: Any] else {
            return BridgeResponse.error(request: request, action: "natsProvision", message: "nats payload is required.")
        }

        do {
            let parsed = try NATSSettings.fromPayload(natsPayload, fallback: settings.natsConfiguration)
            guard parsed.authMethod.isTransportSupported else {
                lastError = "NATS auth method is not supported by the native transport yet: \(parsed.authMethod.rawValue)."
                return BridgeResponse.error(request: request, action: "natsProvision", message: lastError)
            }
            if parsed.authMethod.requiresSecret {
                guard let secret = secretFromPayload(natsPayload, method: parsed.authMethod), !secret.isEmpty else {
                    return BridgeResponse.error(
                        request: request,
                        action: "natsProvision",
                        message: "NATS credential is required for auth method \(parsed.authMethod.rawValue)."
                    )
                }
                try credentialStore.store(secret, method: parsed.authMethod)
            } else {
                credentialStore.clear()
            }
            settings.natsConfiguration = parsed
            lastError = ""
            return response(request: request, action: "natsProvision", success: true)
        } catch {
            lastError = "\(error)"
            return BridgeResponse.error(request: request, action: "natsProvision", message: lastError)
        }
    }

    func status(request: [String: Any]) -> [String: Any] {
        response(request: request, action: "natsStatus", success: true)
    }

    func connect(request: [String: Any]) -> [String: Any] {
        let current = settings.natsConfiguration
        guard current.enabled else {
            lastError = "NATS is not enabled."
            return response(request: request, action: "natsConnect", success: false)
        }
        guard current.authMethod.isTransportSupported else {
            lastError = "NATS auth method is not supported by the native transport yet: \(current.authMethod.rawValue)."
            return response(request: request, action: "natsConnect", success: false)
        }
        guard !current.urls.isEmpty else {
            lastError = "At least one NATS URL is required."
            return response(request: request, action: "natsConnect", success: false)
        }
        let credential = credentialStore.loadCredential()
        if current.authMethod.requiresSecret && (credential ?? "").isEmpty {
            lastError = "NATS credential is not provisioned."
            return response(request: request, action: "natsConnect", success: false)
        }
        if let error = connection.connect(
            settings: current,
            appUUID: settings.appUUIDString,
            credential: credential,
            commandHandler: { [weak self] subject, payload, replyTo in
                Task { @MainActor in
                    self?.handleCommand(subject: subject, payload: payload, replyTo: replyTo)
                }
            }
        ) {
            lastError = error
            return response(request: request, action: "natsConnect", success: false)
        }
        lastError = ""
        publishStatusEvent()
        return response(request: request, action: "natsConnect", success: true)
    }

    func connectIfConfigured(reason: String) {
        guard !connection.connected, !autoConnectInFlight else { return }
        let current = settings.natsConfiguration
        guard current.enabled,
              current.authMethod.isTransportSupported,
              !current.urls.isEmpty else {
            return
        }
        if current.authMethod.requiresSecret && !credentialStore.hasCredential() {
            lastError = "NATS credential is not provisioned."
            return
        }
        let credential = credentialStore.loadCredential()
        let appUUID = settings.appUUIDString
        let connection = connection
        let bridge = self
        autoConnectInFlight = true
        Task.detached { [current, credential, appUUID, connection, bridge] in
            let error = connection.connect(
                settings: current,
                appUUID: appUUID,
                credential: credential,
                commandHandler: { [weak bridge] subject, payload, replyTo in
                    Task { @MainActor in
                        bridge?.handleCommand(subject: subject, payload: payload, replyTo: replyTo)
                    }
                }
            )
            await MainActor.run {
                bridge.autoConnectInFlight = false
                if let error {
                    bridge.lastError = error
                } else {
                    bridge.lastError = ""
                    bridge.publishStatusEvent()
                }
            }
        }
    }

    func disconnect(request: [String: Any]) -> [String: Any] {
        connection.disconnect()
        lastError = ""
        return response(request: request, action: "natsDisconnect", success: true)
    }

    func publish(request: [String: Any]) -> [String: Any] {
        guard connection.connected else {
            lastError = "NATS is not connected."
            return response(request: request, action: "natsPublish", success: false)
        }
        let current = settings.natsConfiguration
        let subject = stringValue(request["subject"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard subject.hasPrefix(current.devicePrefix(appUUID: settings.appUUIDString) + ".") else {
            lastError = "NATS publish subject is outside the device namespace."
            return response(request: request, action: "natsPublish", success: false)
        }
        let payload: Data
        if let json = request["json"], JSONSerialization.isValidJSONObject(json),
           let data = try? JSONSerialization.data(withJSONObject: json) {
            payload = data
        } else {
            payload = stringValue(request["payload"] ?? request["data"]).data(using: .utf8) ?? Data()
        }
        if let error = connection.publish(subject: subject, payload: payload) {
            lastError = error
            return response(request: request, action: "natsPublish", success: false)
        }
        lastError = ""
        var result = response(request: request, action: "natsPublish", success: true)
        result["subject"] = subject
        result["bytes"] = payload.count
        return result
    }

    func publishData(subject: String, payload: Data) -> String? {
        guard connection.connected else {
            lastError = "NATS is not connected."
            return lastError
        }
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(settings.natsConfiguration.devicePrefix(appUUID: settings.appUUIDString) + ".") else {
            lastError = "NATS publish subject is outside the device namespace."
            return lastError
        }
        if let error = connection.publish(subject: trimmed, payload: payload) {
            lastError = error
            return error
        }
        lastError = ""
        return nil
    }

    func publishJSON(subject: String, payload: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload) else {
            lastError = "NATS JSON payload is not serializable."
            return lastError
        }
        return publishData(subject: subject, payload: data)
    }

    func publishTelemetry(payload: [String: Any]) -> String? {
        let current = settings.natsConfiguration
        guard current.telemetryEnabled else {
            return nil
        }
        return publishJSON(subject: current.telemetrySubject(appUUID: settings.appUUIDString), payload: payload)
    }

    private func response(request: [String: Any], action: String, success: Bool) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: action)
        response["success"] = success
        response["nats"] = statusSnapshot()
        if !success && !lastError.isEmpty {
            response["error"] = lastError
        }
        return response
    }

    private func handleCommand(subject: String, payload: Data, replyTo: String?) {
        do {
            var command = try commandFromPayload(payload)
            normalizeCommandAction(&command, subject: subject)
            let action = stringValue(command["action"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard isAllowedCommand(action) else {
                publishCommandResponse(
                    command: command,
                    commandSubject: subject,
                    transportReplyTo: replyTo,
                    response: BridgeResponse.error(
                        request: command,
                        action: action.isEmpty ? "natsCommand" : action,
                        message: "NATS command is not allowed: \(action)."
                    )
                )
                return
            }
            guard let commandExecutor else {
                publishCommandResponse(
                    command: command,
                    commandSubject: subject,
                    transportReplyTo: replyTo,
                    response: BridgeResponse.error(
                        request: command,
                        action: action,
                        message: "NATS command executor is not configured."
                    )
                )
                return
            }
            commandExecutor(command) { [weak self] result in
                Task { @MainActor in
                    self?.publishCommandResponse(
                        command: command,
                        commandSubject: subject,
                        transportReplyTo: replyTo,
                        response: result
                    )
                }
            }
        } catch {
            publishCommandResponse(
                command: [:],
                commandSubject: subject,
                transportReplyTo: replyTo,
                response: BridgeResponse.error(request: [:], action: "natsCommand", message: error.localizedDescription)
            )
        }
    }

    private func commandFromPayload(_ payload: Data) throws -> [String: Any] {
        guard !payload.isEmpty else {
            return [:]
        }
        let object = try JSONSerialization.jsonObject(with: payload)
        guard let command = object as? [String: Any] else {
            throw AppError.invalidRequest("NATS command payload must be a JSON object.")
        }
        return command
    }

    private func normalizeCommandAction(_ command: inout [String: Any], subject: String) {
        var action = stringValue(command["action"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if action.isEmpty {
            action = actionFromCommandSubject(subject)
        }
        switch action {
        case "status":
            action = "deviceInfoGet"
        case "settings":
            action = "settingsGet"
        case "screenshot":
            action = "screenshotGet"
        case "qrScan", "qrCodeScan", "qrScanImage":
            action = "qrScanImage"
        case "qrScanJob", "qrCodeScanJob", "qrScanImageJob":
            action = "qrScanImage"
        case "screenStream", "videoStreamStart":
            action = "screenStreamStart"
        case "videoStreamStop":
            action = "screenStreamStop"
        default:
            break
        }
        if !action.isEmpty {
            command["action"] = action
        }
    }

    private func actionFromCommandSubject(_ subject: String) -> String {
        let prefix = "\(settings.natsConfiguration.devicePrefix(appUUID: settings.appUUIDString)).commands."
        guard subject.hasPrefix(prefix) else {
            return ""
        }
        return String(subject.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isAllowedCommand(_ action: String) -> Bool {
        [
            "natsStatus",
            "deviceInfoGet",
            "settingsGet",
            "settingsSet",
            "screenshotGet",
            "qrScanImage",
            "screenStreamStart",
            "screenStreamStop",
            "reload"
        ].contains(action)
    }

    private func publishCommandResponse(
        command: [String: Any],
        commandSubject: String,
        transportReplyTo: String?,
        response: [String: Any]
    ) {
        var payload = response
        var natsCommand: [String: Any] = ["subject": commandSubject]
        for key in ["jobId", "scanJobId", "taskId", "distributionId"] {
            let value = stringValue(command[key]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                natsCommand[key] = value
            }
        }
        if let transportReplyTo,
           !transportReplyTo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            natsCommand["transportReplyTo"] = transportReplyTo.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        payload["natsCommand"] = natsCommand
        let transportReplySubject = (transportReplyTo ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitReplySubject = stringValue(command["replyTo"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let responseSubject = !transportReplySubject.isEmpty
            ? transportReplySubject
            : !explicitReplySubject.isEmpty
                ? explicitReplySubject
                : settings.natsConfiguration.responseSubject(appUUID: settings.appUUIDString)
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload) else {
            lastError = "NATS command response is not JSON serializable."
            return
        }
        if let error = connection.publish(subject: responseSubject, payload: data) {
            lastError = error
        }
    }

    private func publishStatusEvent() {
        let payload = response(request: [:], action: "natsStatus", success: true)
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload) else {
            return
        }
        _ = connection.publish(subject: settings.natsConfiguration.statusSubject(appUUID: settings.appUUIDString), payload: data)
    }

    private func hasValidToken(_ request: [String: Any]) -> Bool {
        let token = stringValue(request["token"] ?? request["securityToken"]).trimmingCharacters(in: .whitespacesAndNewlines)
        return !token.isEmpty && token == settings.securityToken
    }

    private func secretFromPayload(_ payload: [String: Any], method: NATSAuthMethod) -> String? {
        guard let auth = payload["auth"] as? [String: Any] else {
            return nil
        }
        switch method {
        case .creds:
            return stringValue(auth["creds"] ?? auth["credentials"])
        case .token:
            return stringValue(auth["token"])
        case .userPassword:
            return stringValue(auth["password"])
        case .nkey:
            return stringValue(auth["seed"] ?? auth["nkey"])
        case .tlsCertificate:
            return stringValue(auth["privateKey"] ?? auth["p12"] ?? auth["pkcs12"])
        case .none:
            return nil
        }
    }
}
