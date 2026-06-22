//
//  RecoveryConfigParser.swift
//  swiftHTMLWebviewApp
//
//  Parses recovery QR payloads into startup URLs without depending on UI state.
//

import Foundation

struct RecoveryConfigParser {
    func serverURL(from rawCode: String) -> String? {
        let trimmed = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let jsonData = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] {
            if let directURL = firstNonEmptyString(json, keys: [
                "serverURL",
                "serverUrl",
                "defaultServerURL",
                "defaultServerUrl",
                "mobileURL",
                "mobileUrl",
                "url"
            ]) {
                return normalizedMobileURL(directURL, linkId: stringValue(json["linkId"]))
            }

            if let backendURL = firstNonEmptyString(json, keys: ["backendURL", "backendUrl"]) {
                return normalizedMobileURL(backendURL, linkId: stringValue(json["linkId"]))
            }
        }

        return normalizedMobileURL(trimmed, linkId: "")
    }

    private func normalizedMobileURL(_ rawValue: String, linkId: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let existingLinkId = components.queryItems?.first(where: { $0.name == "link" })?.value ?? ""
        let targetLinkId = existingLinkId.isEmpty ? linkId.trimmingCharacters(in: .whitespacesAndNewlines) : existingLinkId
        if components.path.isEmpty || components.path == "/" {
            components.path = "/mobile/"
        }
        if !targetLinkId.isEmpty && existingLinkId.isEmpty {
            var queryItems = components.queryItems ?? []
            queryItems.append(URLQueryItem(name: "link", value: targetLinkId))
            components.queryItems = queryItems
        }
        components.fragment = nil
        return components.url?.absoluteString
    }

    private func firstNonEmptyString(_ values: [String: Any], keys: [String]) -> String? {
        for key in keys {
            let value = stringValue(values[key]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

struct ConfigQRCode {
    let token: String
    let settings: [String: Any]
    let wifiRequest: [String: Any]?
}

struct ConfigQRCodeParser {
    private static let knownSettingKeys: Set<String> = [
        "serverURL", "serverUrl", "defaultServerURL", "defaultServerUrl", "mobileURL", "mobileUrl", "url",
        "highAvailabilityEnabled", "haEnabled", "ha_enabled",
        "highAvailabilityTimeoutSeconds", "haTimeout", "ha_timeout",
        "highAvailabilityURL2", "haURL2", "ha_url2",
        "highAvailabilityURL3", "haURL3", "ha_url3",
        "highAvailabilityURL4", "haURL4", "ha_url4",
        "beaconUUID", "beaconUuid", "beacon_uuid",
        "deviceName", "device_name", "name",
        "deviceUUID", "deviceUuid", "device_uuid", "uuid",
        "deviceLocation", "device_location", "location",
        "newSecurityToken"
    ]

    private static let reservedQueryKeys: Set<String> = [
        "action", "command", "toolmode", "token", "securityToken", "link", "linkId"
    ]

    func parse(code: String) -> ConfigQRCode? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let json = jsonObject(from: trimmed) {
            return parse(json: json)
        }

        return parseQueryPayload(trimmed)
    }

    private func parse(json: [String: Any]) -> ConfigQRCode? {
        guard isConfigJSON(json) else {
            return nil
        }

        var settings = (json["settings"] as? [String: Any]) ?? [:]
        for key in Self.knownSettingKeys where settings[key] == nil && json[key] != nil {
            settings[key] = json[key]
        }
        mergeJSONObject(json["appConfig"] ?? json["app_config"], into: &settings, key: "appConfig")
        mergeJSONObject(json["store"], into: &settings, key: "appConfig")

        let wifi = wifiRequest(from: json["wifi"] as? [String: Any])
        let token = firstNonEmptyString(json, keys: ["token", "securityToken"])
        guard !settings.isEmpty || wifi != nil else {
            return nil
        }
        return ConfigQRCode(token: token, settings: settings, wifiRequest: wifi)
    }

    private func parseQueryPayload(_ rawValue: String) -> ConfigQRCode? {
        guard let queryItems = queryItems(from: rawValue), !queryItems.isEmpty else {
            return nil
        }

        var settings: [String: Any] = [:]
        var appConfig: [String: Any] = [:]
        var looseAppConfig: [String: Any] = [:]
        var wifi: [String: Any] = [:]
        var token = ""
        var sawConfigMarker = false

        for item in queryItems {
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = (item.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            if name == "token" || name == "securityToken" {
                token = value
                sawConfigMarker = true
            } else if name == "toolmode" && value == "changeConfig" {
                sawConfigMarker = true
            } else if let nestedKey = bracketKey(name, prefix: "wifi") {
                wifi[normalizedWifiKey(nestedKey)] = value
                sawConfigMarker = true
            } else if let nestedKey = bracketKey(name, prefix: "store") ?? bracketKey(name, prefix: "appConfig") {
                appConfig[nestedKey] = value
                sawConfigMarker = true
            } else if Self.knownSettingKeys.contains(name) {
                settings[name] = value
                sawConfigMarker = true
            } else if !Self.reservedQueryKeys.contains(name) {
                looseAppConfig[name] = value
            }
        }

        if sawConfigMarker || !token.isEmpty {
            for (key, value) in looseAppConfig {
                appConfig[key] = value
            }
        }

        if !appConfig.isEmpty {
            settings["appConfig"] = appConfig
        }

        var wifiRequest: [String: Any]? = nil
        if !wifi.isEmpty {
            var request = wifi
            request["action"] = "wifiConfigure"
            request["source"] = "qr"
            wifiRequest = request
        }

        guard !settings.isEmpty || wifiRequest != nil else {
            return nil
        }
        return ConfigQRCode(token: token, settings: settings, wifiRequest: wifiRequest)
    }

    private func queryItems(from rawValue: String) -> [URLQueryItem]? {
        if rawValue.hasPrefix("?") {
            var components = URLComponents()
            components.percentEncodedQuery = String(rawValue.drop(while: { $0 == "?" || $0 == "&" }))
            return components.queryItems
        }
        if let components = URLComponents(string: rawValue), components.query != nil {
            return components.queryItems
        }
        if rawValue.contains("=") {
            var components = URLComponents()
            components.percentEncodedQuery = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "?&"))
            return components.queryItems
        }
        return nil
    }

    private func bracketKey(_ value: String, prefix: String) -> String? {
        let marker = "\(prefix)["
        guard value.hasPrefix(marker), value.hasSuffix("]") else {
            return nil
        }
        let start = value.index(value.startIndex, offsetBy: marker.count)
        let end = value.index(before: value.endIndex)
        let key = String(value[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    private func normalizedWifiKey(_ key: String) -> String {
        switch key {
        case "pw", "pass", "password":
            return "password"
        default:
            return key
        }
    }

    private func wifiRequest(from value: [String: Any]?) -> [String: Any]? {
        guard let value else { return nil }
        var request: [String: Any] = ["action": "wifiConfigure", "source": "qr"]
        let ssid = firstNonEmptyString(value, keys: ["ssid", "SSID"])
        if !ssid.isEmpty {
            request["ssid"] = ssid
        }
        let password = firstNonEmptyString(value, keys: ["passphrase", "password", "pw", "pass"])
        if !password.isEmpty {
            request["password"] = password
        }
        if let joinOnce = boolValue(value["joinOnce"]) {
            request["joinOnce"] = joinOnce
        }
        return request["ssid"] == nil ? nil : request
    }

    private func isConfigJSON(_ json: [String: Any]) -> Bool {
        if stringValue(json["toolmode"]).trimmingCharacters(in: .whitespacesAndNewlines) == "changeConfig" {
            return true
        }
        if json["settings"] is [String: Any] || json["appConfig"] is [String: Any] || json["app_config"] is [String: Any] || json["store"] is [String: Any] || json["wifi"] is [String: Any] {
            return true
        }
        if !firstNonEmptyString(json, keys: ["token", "securityToken"]).isEmpty {
            return Self.knownSettingKeys.contains(where: { json[$0] != nil })
        }
        return false
    }

    private func mergeJSONObject(_ value: Any?, into settings: inout [String: Any], key: String) {
        guard let incoming = value as? [String: Any], !incoming.isEmpty else {
            return
        }
        var merged = (settings[key] as? [String: Any]) ?? [:]
        incoming.forEach { merged[$0.key] = $0.value }
        settings[key] = merged
    }

    private func jsonObject(from value: String) -> [String: Any]? {
        guard let data = value.data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
    }

    private func firstNonEmptyString(_ values: [String: Any], keys: [String]) -> String {
        for key in keys {
            let value = stringValue(values[key]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        return ""
    }
}

enum RecoveryBarcodeOutcome {
    case invalid(response: [String: Any])
    case applied(serverURL: String, snapshot: [String: Any])
}

enum ConfigPairingBarcodeOutcome {
    case invalid(response: [String: Any])
    case applied(settings: [String: Any], wifiRequest: [String: Any]?)
}

struct RecoveryBarcodeHandler {
    typealias ApplyConfiguration = ([String: Any]) -> [String: Any]

    private let parser: RecoveryConfigParser
    private let invalidMessage: String
    private let applyConfiguration: ApplyConfiguration

    init(
        parser: RecoveryConfigParser = RecoveryConfigParser(),
        invalidMessage: String,
        applyConfiguration: @escaping ApplyConfiguration
    ) {
        self.parser = parser
        self.invalidMessage = invalidMessage
        self.applyConfiguration = applyConfiguration
    }

    static func isRecoveryRequest(_ request: [String: Any]?) -> Bool {
        stringValue(request?["source"]).trimmingCharacters(in: .whitespacesAndNewlines) == "recovery"
    }

    func handle(code: String, action: String) -> RecoveryBarcodeOutcome {
        guard let serverURL = parser.serverURL(from: code) else {
            return .invalid(response: BarcodeResponseBuilder.recoveryInvalidResponse(
                action: action,
                message: invalidMessage
            ))
        }

        let snapshot = applyConfiguration(["serverURL": serverURL])
        return .applied(serverURL: serverURL, snapshot: snapshot)
    }

    func handleConfigPairing(
        code: String,
        action: String,
        storedToken: String,
        invalidTokenMessage: String
    ) -> ConfigPairingBarcodeOutcome {
        if let configQR = ConfigQRCodeParser().parse(code: code) {
            guard allowsConfigQRToken(configQR.token, storedToken: storedToken) else {
                return .invalid(response: BarcodeResponseBuilder.recoveryInvalidResponse(
                    action: action,
                    message: invalidTokenMessage
                ))
            }

            return .applied(
                settings: applyConfiguration(configQR.settings),
                wifiRequest: configQR.wifiRequest
            )
        }

        if let serverURL = parser.serverURL(from: code) {
            return .applied(
                settings: applyConfiguration(["serverURL": serverURL]),
                wifiRequest: nil
            )
        }

        return .invalid(response: BarcodeResponseBuilder.recoveryInvalidResponse(
            action: action,
            message: invalidMessage
        ))
    }

    private func allowsConfigQRToken(_ token: String, storedToken: String) -> Bool {
        let stored = storedToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let incoming = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if stored.isEmpty {
            return incoming.isEmpty
        }
        return incoming == stored
    }
}
