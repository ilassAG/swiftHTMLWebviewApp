//
//  NATSSettings.swift
//  swiftHTMLWebviewApp
//

import Foundation

enum NATSAuthMethod: String, CaseIterable {
    case none
    case token
    case userPassword
    case nkey
    case creds
    case tlsCertificate

    static func parse(_ value: Any?) -> NATSAuthMethod? {
        let raw = stringValue(value).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return allCases.first { $0.rawValue.lowercased() == raw.lowercased() }
    }

    var requiresSecret: Bool {
        self != .none
    }

    var isTransportSupported: Bool {
        switch self {
        case .none, .token, .nkey, .creds:
            return true
        case .userPassword, .tlsCertificate:
            return false
        }
    }

    static var supportedTransportMethods: [String] {
        allCases.filter(\.isTransportSupported).map(\.rawValue)
    }

    static var unsupportedTransportMethods: [String] {
        allCases.filter { !$0.isTransportSupported }.map(\.rawValue)
    }
}

enum NATSSettingsError: Error, Equatable, CustomStringConvertible {
    case invalidAuthMethod
    case invalidURL(String)

    var description: String {
        switch self {
        case .invalidAuthMethod:
            return "Invalid NATS auth method."
        case .invalidURL(let value):
            return "Invalid NATS URL: \(value)"
        }
    }
}

struct NATSSettings: Equatable {
    static let defaultURLs: [String] = []

    var enabled = false
    var urls: [String] = []
    var tlsFirst = true
    var clientNameTemplate = "swift-wrapper-${appUUID}"
    var identitySource = "appUUID"
    var authMethod: NATSAuthMethod = .creds
    var maxReconnects = -1
    var reconnectWaitMs = 500
    var pingIntervalSeconds = 10
    var namespace = "swift.wrapper"
    var devicePrefixTemplate = "swift.wrapper.${appUUID}"
    var commandSubjectTemplate = "swift.wrapper.${appUUID}.commands.*"
    var responseSubjectTemplate = "swift.wrapper.${appUUID}.events.responses"
    var statusSubjectTemplate = "swift.wrapper.${appUUID}.status"
    var telemetrySubjectTemplate = "swift.wrapper.${appUUID}.telemetry.status"
    var telemetryEnabled = true
    var telemetryIntervalSeconds = 30

    static func fromStoredJSONString(_ rawValue: String?) -> NATSSettings {
        guard let rawValue,
              let data = rawValue.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let settings = try? fromPayload(object, fallback: NATSSettings()) else {
            return NATSSettings()
        }
        return settings
    }

    static func fromPayload(_ payload: [String: Any], fallback: NATSSettings = NATSSettings()) throws -> NATSSettings {
        let source = (payload["nats"] as? [String: Any]) ?? payload
        var settings = fallback

        if let enabled = boolValue(source["enabled"]) {
            settings.enabled = enabled
        }
        if let urls = stringArray(source["urls"]) {
            settings.urls = try normalizeURLs(urls, useDefaultWhenEmpty: settings.enabled)
        } else if settings.enabled && settings.urls.isEmpty {
            settings.urls = defaultURLs
        }
        if let tlsFirst = boolValue(source["tlsFirst"] ?? source["tls_first"]) {
            settings.tlsFirst = tlsFirst
        }
        if let value = normalizedString(source["clientNameTemplate"] ?? source["client_name_template"]) {
            settings.clientNameTemplate = value
        }
        if let value = normalizedString(source["identitySource"] ?? source["identity_source"]) {
            settings.identitySource = value
        }
        if let auth = source["auth"] as? [String: Any] {
            if auth.keys.contains(where: { $0 == "method" }) {
                guard let method = NATSAuthMethod.parse(auth["method"]) else {
                    throw NATSSettingsError.invalidAuthMethod
                }
                settings.authMethod = method
            }
        } else if let methodValue = source["authMethod"] ?? source["auth_method"] {
            guard let method = NATSAuthMethod.parse(methodValue) else {
                throw NATSSettingsError.invalidAuthMethod
            }
            settings.authMethod = method
        }
        if let reconnect = source["reconnect"] as? [String: Any] {
            if let value = intValue(reconnect["maxReconnects"] ?? reconnect["max_reconnects"]) {
                settings.maxReconnects = max(-1, value)
            }
            if let value = intValue(reconnect["reconnectWaitMs"] ?? reconnect["reconnect_wait_ms"]) {
                settings.reconnectWaitMs = min(60_000, max(100, value))
            }
            if let value = intValue(reconnect["pingIntervalSeconds"] ?? reconnect["ping_interval_seconds"]) {
                settings.pingIntervalSeconds = min(300, max(1, value))
            }
        }
        if let telemetry = source["telemetry"] as? [String: Any] {
            if let enabled = boolValue(telemetry["enabled"]) {
                settings.telemetryEnabled = enabled
            }
            if let value = intValue(telemetry["intervalSeconds"] ?? telemetry["interval_seconds"]) {
                settings.telemetryIntervalSeconds = min(300, max(5, value))
            }
        }
        if let subjects = source["subjects"] as? [String: Any] {
            if let value = normalizedString(subjects["namespace"]) {
                settings.namespace = value
            }
            if let value = normalizedString(subjects["devicePrefixTemplate"] ?? subjects["device_prefix_template"]) {
                settings.devicePrefixTemplate = value
            }
            if let value = normalizedString(subjects["commandSubjectTemplate"] ?? subjects["command_subject_template"]) {
                settings.commandSubjectTemplate = value
            }
            if let value = normalizedString(subjects["responseSubjectTemplate"] ?? subjects["response_subject_template"]) {
                settings.responseSubjectTemplate = value
            }
            if let value = normalizedString(subjects["statusSubjectTemplate"] ?? subjects["status_subject_template"]) {
                settings.statusSubjectTemplate = value
            }
            if let value = normalizedString(subjects["telemetrySubjectTemplate"] ?? subjects["telemetry_subject_template"]) {
                settings.telemetrySubjectTemplate = value
            }
        }

        return settings
    }

    func persistedJSONString() -> String {
        let object = nonSecretJSONObject()
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let rawValue = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return rawValue
    }

    func nonSecretJSONObject() -> [String: Any] {
        [
            "enabled": enabled,
            "urls": urls,
            "tlsFirst": tlsFirst,
            "clientNameTemplate": clientNameTemplate,
            "identitySource": identitySource,
            "auth": ["method": authMethod.rawValue],
            "reconnect": [
                "maxReconnects": maxReconnects,
                "reconnectWaitMs": reconnectWaitMs,
                "pingIntervalSeconds": pingIntervalSeconds
            ],
            "telemetry": [
                "enabled": telemetryEnabled,
                "intervalSeconds": telemetryIntervalSeconds
            ],
            "subjects": [
                "namespace": namespace,
                "devicePrefixTemplate": devicePrefixTemplate,
                "commandSubjectTemplate": commandSubjectTemplate,
                "responseSubjectTemplate": responseSubjectTemplate,
                "statusSubjectTemplate": statusSubjectTemplate,
                "telemetrySubjectTemplate": telemetrySubjectTemplate
            ]
        ]
    }

    func redactedSnapshot(appUUID: String, credentialSet: Bool, connected: Bool, lastError: String) -> [String: Any] {
        [
            "enabled": enabled,
            "urls": urls,
            "tlsFirst": tlsFirst,
            "clientName": clientName(appUUID: appUUID),
            "identitySource": identitySource,
            "auth": [
                "method": authMethod.rawValue,
                "credentialSet": credentialSet,
                "supportedMethods": NATSAuthMethod.supportedTransportMethods,
                "unsupportedMethods": NATSAuthMethod.unsupportedTransportMethods
            ],
            "telemetry": [
                "enabled": telemetryEnabled,
                "intervalSeconds": telemetryIntervalSeconds
            ],
            "connected": connected,
            "lastError": lastError,
            "subjects": [
                "namespace": namespace,
                "devicePrefix": devicePrefix(appUUID: appUUID),
                "commandSubject": commandSubject(appUUID: appUUID),
                "responseSubject": responseSubject(appUUID: appUUID),
                "statusSubject": statusSubject(appUUID: appUUID),
                "telemetrySubject": telemetrySubject(appUUID: appUUID)
            ]
        ]
    }

    func clientName(appUUID: String) -> String {
        replacingIdentityPlaceholders(in: clientNameTemplate, appUUID: appUUID)
    }

    func devicePrefix(appUUID: String) -> String {
        replacingIdentityPlaceholders(in: devicePrefixTemplate, appUUID: appUUID)
    }

    func commandSubject(appUUID: String) -> String {
        replacingIdentityPlaceholders(in: commandSubjectTemplate, appUUID: appUUID)
    }

    func responseSubject(appUUID: String) -> String {
        replacingIdentityPlaceholders(in: responseSubjectTemplate, appUUID: appUUID)
    }

    func statusSubject(appUUID: String) -> String {
        replacingIdentityPlaceholders(in: statusSubjectTemplate, appUUID: appUUID)
    }

    func telemetrySubject(appUUID: String) -> String {
        replacingIdentityPlaceholders(in: telemetrySubjectTemplate, appUUID: appUUID)
    }

    private func replacingIdentityPlaceholders(in template: String, appUUID: String) -> String {
        template
            .replacingOccurrences(of: "${appUUID}", with: appUUID)
            .replacingOccurrences(of: "{appUUID}", with: appUUID)
    }

    private static func normalizeURLs(_ values: [String], useDefaultWhenEmpty: Bool) throws -> [String] {
        let normalized = values.compactMap { normalizedString($0) }
        if normalized.isEmpty {
            return useDefaultWhenEmpty ? defaultURLs : []
        }
        for value in normalized {
            guard let url = URL(string: value),
                  let scheme = url.scheme?.lowercased(),
                  ["nats", "tls", "ws", "wss"].contains(scheme),
                  url.host != nil else {
                throw NATSSettingsError.invalidURL(value)
            }
        }
        return normalized
    }

    private static func stringArray(_ value: Any?) -> [String]? {
        if let array = value as? [String] {
            return array
        }
        if let array = value as? [Any] {
            return array.compactMap { normalizedString($0) }
        }
        if let string = normalizedString(value) {
            return string.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return nil
    }

    private static func normalizedString(_ value: Any?) -> String? {
        let trimmed = stringValue(value).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
