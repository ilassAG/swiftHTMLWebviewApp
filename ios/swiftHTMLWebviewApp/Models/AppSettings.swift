//
//  AppSettings.swift
//  swiftHTMLWebviewApp
//
//  This class manages application settings using UserDefaults.
//  Default values are registered here so Settings.bundle and runtime code stay
//  aligned.
//

import Foundation

class AppSettings {
    static let shared = AppSettings()

    private let userDefaults = UserDefaults.standard
    private let serverUrlKey = "server_url_preference"
    private let defaultServerUrl = "local"
    private let securityTokenKey = "security_token_preference"
    private let defaultSecurityToken = "change-me-before-production"
    private let highAvailabilityEnabledKey = "ha_enabled"
    private let highAvailabilityTimeoutKey = "ha_timeout"
    private let highAvailabilityUrl2Key = "ha_url2"
    private let highAvailabilityUrl3Key = "ha_url3"
    private let highAvailabilityUrl4Key = "ha_url4"
    private let activeServerUrlKey = "active_server_url"
    private let lastServerUrlKey = "last_server_url"
    private let beaconUUIDKey = "beacon_uuid"
    private let deviceNameKey = "device_name"
    private let deviceUUIDKey = "device_uuid"
    private let deviceLocationKey = "device_location"
    private let defaultHighAvailabilityTimeoutSeconds = 5
    private let defaultBeaconUUID = "7763A937-B779-4D31-A20C-49E83047048F"

    var serverURL: String {
        get {
            normalizedSettingValue(userDefaults.string(forKey: serverUrlKey), fallback: defaultServerUrl)
        }
        set {
            userDefaults.set(newValue, forKey: serverUrlKey)
        }
    }

    var securityToken: String {
        get {
            userDefaults.string(forKey: securityTokenKey) ?? defaultSecurityToken
        }
        set {
            userDefaults.set(newValue, forKey: securityTokenKey)
        }
    }

    var highAvailabilityEnabled: Bool {
        get {
            userDefaults.bool(forKey: highAvailabilityEnabledKey)
        }
        set {
            userDefaults.set(newValue, forKey: highAvailabilityEnabledKey)
        }
    }

    var highAvailabilityTimeoutSeconds: Int {
        get {
            let configuredValue: Int
            switch userDefaults.object(forKey: highAvailabilityTimeoutKey) {
            case let intValue as Int:
                configuredValue = intValue
            case let numberValue as NSNumber:
                configuredValue = numberValue.intValue
            case let stringValue as String:
                configuredValue = Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            default:
                configuredValue = 0
            }
            return configuredValue > 0 ? configuredValue : defaultHighAvailabilityTimeoutSeconds
        }
        set {
            userDefaults.set(max(1, newValue), forKey: highAvailabilityTimeoutKey)
        }
    }

    var beaconUUIDString: String {
        get {
            normalizedSettingValue(userDefaults.string(forKey: beaconUUIDKey), fallback: defaultBeaconUUID)
        }
        set {
            userDefaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: beaconUUIDKey)
        }
    }

    var beaconUUID: UUID {
        UUID(uuidString: beaconUUIDString) ?? UUID(uuidString: defaultBeaconUUID)!
    }

    var deviceName: String {
        get { normalizedOptionalValue(userDefaults.string(forKey: deviceNameKey)) ?? "" }
        set { userDefaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: deviceNameKey) }
    }

    var deviceUUIDString: String {
        get {
            ensureDeviceUUID()
            return normalizedOptionalValue(userDefaults.string(forKey: deviceUUIDKey)) ?? ""
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let uuid = UUID(uuidString: trimmed) ?? UUID()
            userDefaults.set(uuid.uuidString, forKey: deviceUUIDKey)
        }
    }

    var deviceLocation: String {
        get { normalizedOptionalValue(userDefaults.string(forKey: deviceLocationKey)) ?? "" }
        set { userDefaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: deviceLocationKey) }
    }

    var highAvailabilityURL2: String {
        get { normalizedOptionalValue(userDefaults.string(forKey: highAvailabilityUrl2Key)) ?? "" }
        set { userDefaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: highAvailabilityUrl2Key) }
    }

    var highAvailabilityURL3: String {
        get { normalizedOptionalValue(userDefaults.string(forKey: highAvailabilityUrl3Key)) ?? "" }
        set { userDefaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: highAvailabilityUrl3Key) }
    }

    var highAvailabilityURL4: String {
        get { normalizedOptionalValue(userDefaults.string(forKey: highAvailabilityUrl4Key)) ?? "" }
        set { userDefaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: highAvailabilityUrl4Key) }
    }

    var activeServerURL: String? {
        normalizedOptionalValue(userDefaults.string(forKey: activeServerUrlKey))
    }

    var lastServerURL: String? {
        normalizedOptionalValue(userDefaults.string(forKey: lastServerUrlKey))
    }

    func registerDefaults() {
        userDefaults.register(defaults: [
            serverUrlKey: defaultServerUrl,
            securityTokenKey: defaultSecurityToken,
            highAvailabilityEnabledKey: false,
            highAvailabilityTimeoutKey: defaultHighAvailabilityTimeoutSeconds,
            highAvailabilityUrl2Key: "",
            highAvailabilityUrl3Key: "",
            highAvailabilityUrl4Key: "",
            activeServerUrlKey: "",
            lastServerUrlKey: "",
            beaconUUIDKey: defaultBeaconUUID,
            deviceNameKey: "",
            deviceUUIDKey: "",
            deviceLocationKey: ""
        ])
        ensureDeviceUUID()
    }

    func resetToDefaultURL() {
        serverURL = defaultServerUrl
    }

    func resetToDefaultSecurityToken() {
        securityToken = defaultSecurityToken
    }

    func serverURLCandidates(primaryOverride: String? = nil) -> [String] {
        var candidates = [normalizedSettingValue(primaryOverride, fallback: serverURL)]

        if highAvailabilityEnabled {
            candidates.append(contentsOf: [
                userDefaults.string(forKey: highAvailabilityUrl2Key),
                userDefaults.string(forKey: highAvailabilityUrl3Key),
                userDefaults.string(forKey: highAvailabilityUrl4Key)
            ].compactMap { normalizedOptionalValue($0) })
        }

        return candidates.reduce(into: [String]()) { uniqueCandidates, candidate in
            let normalizedCandidate = normalizedURLIdentity(candidate)
            let alreadyExists = uniqueCandidates.contains {
                normalizedURLIdentity($0) == normalizedCandidate
            }
            if !alreadyExists {
                uniqueCandidates.append(candidate)
            }
        }
    }

    func markActiveServerURL(_ urlString: String) {
        let normalizedValue = normalizedSettingValue(urlString, fallback: defaultServerUrl)
        userDefaults.set(normalizedValue, forKey: activeServerUrlKey)
        userDefaults.set(normalizedValue, forKey: lastServerUrlKey)
    }

    func configurationSnapshot(includeSensitive: Bool = false) -> [String: Any] {
        var snapshot: [String: Any] = [
            "serverURL": serverURL,
            "highAvailabilityEnabled": highAvailabilityEnabled,
            "highAvailabilityTimeoutSeconds": highAvailabilityTimeoutSeconds,
            "highAvailabilityURL2": highAvailabilityURL2,
            "highAvailabilityURL3": highAvailabilityURL3,
            "highAvailabilityURL4": highAvailabilityURL4,
            "activeServerURL": activeServerURL ?? "",
            "lastServerURL": lastServerURL ?? "",
            "beaconUUID": beaconUUIDString,
            "deviceName": deviceName,
            "deviceUUID": deviceUUIDString,
            "deviceLocation": deviceLocation
        ]

        if includeSensitive {
            snapshot["securityToken"] = securityToken
        } else {
            snapshot["securityTokenSet"] = !securityToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return snapshot
    }

    @discardableResult
    func applyConfiguration(_ values: [String: Any]) -> [String: Any] {
        if let value = settingString(values["serverURL"] ?? values["serverUrl"] ?? values["url"]) {
            serverURL = value
        }
        if let value = settingBool(values["highAvailabilityEnabled"] ?? values["haEnabled"] ?? values["ha_enabled"]) {
            highAvailabilityEnabled = value
        }
        if let value = settingInt(values["highAvailabilityTimeoutSeconds"] ?? values["haTimeout"] ?? values["ha_timeout"]) {
            highAvailabilityTimeoutSeconds = value
        }
        if let value = settingString(values["highAvailabilityURL2"] ?? values["haURL2"] ?? values["ha_url2"]) {
            highAvailabilityURL2 = value
        }
        if let value = settingString(values["highAvailabilityURL3"] ?? values["haURL3"] ?? values["ha_url3"]) {
            highAvailabilityURL3 = value
        }
        if let value = settingString(values["highAvailabilityURL4"] ?? values["haURL4"] ?? values["ha_url4"]) {
            highAvailabilityURL4 = value
        }
        if let value = settingString(values["beaconUUID"] ?? values["beaconUuid"] ?? values["beacon_uuid"]) {
            beaconUUIDString = value
        }
        if let value = settingString(values["deviceName"] ?? values["device_name"] ?? values["name"]) {
            deviceName = value
        }
        if let value = settingString(values["deviceUUID"] ?? values["deviceUuid"] ?? values["device_uuid"] ?? values["uuid"]) {
            deviceUUIDString = value
        }
        if let value = settingString(values["deviceLocation"] ?? values["device_location"] ?? values["location"]) {
            deviceLocation = value
        }
        if let value = settingString(values["newSecurityToken"] ?? values["securityToken"]) {
            securityToken = value
        }

        userDefaults.synchronize()
        return configurationSnapshot()
    }

    private func ensureDeviceUUID() {
        let value = normalizedOptionalValue(userDefaults.string(forKey: deviceUUIDKey))
        if value == nil || value.flatMap(UUID.init(uuidString:)) == nil {
            userDefaults.set(UUID().uuidString, forKey: deviceUUIDKey)
            userDefaults.synchronize()
        }
    }

    private func normalizedSettingValue(_ value: String?, fallback: String) -> String {
        normalizedOptionalValue(value) ?? fallback
    }

    private func normalizedOptionalValue(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedURLIdentity(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if Configuration.isLocalHTMLPath(trimmed) {
            return Configuration.localHTMLPathValue
        }
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }

    private func settingString(_ value: Any?) -> String? {
        guard let value else { return nil }
        if value is NSNull {
            return ""
        }
        if let stringValue = value as? String {
            return stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let numberValue = value as? NSNumber {
            return numberValue.stringValue
        }
        return nil
    }

    private func settingBool(_ value: Any?) -> Bool? {
        guard let value else { return nil }
        if let boolValue = value as? Bool {
            return boolValue
        }
        if let numberValue = value as? NSNumber {
            return numberValue.boolValue
        }
        if let stringValue = value as? String {
            switch stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes", "ja", "on":
                return true
            case "0", "false", "no", "nein", "off":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    private func settingInt(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if let intValue = value as? Int {
            return intValue
        }
        if let numberValue = value as? NSNumber {
            return numberValue.intValue
        }
        if let stringValue = value as? String {
            return Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}
