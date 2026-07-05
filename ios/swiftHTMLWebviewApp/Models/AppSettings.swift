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

    private let userDefaults: UserDefaults
    private let variant: AppVariant
    private let startupURLResolver: StartupURLResolver
    private let serverUrlKey = "server_url_preference"
    private let securityTokenKey = "security_token_preference"
    private let highAvailabilityEnabledKey = "ha_enabled"
    private let highAvailabilityTimeoutKey = "ha_timeout"
    private let highAvailabilityUrl2Key = "ha_url2"
    private let highAvailabilityUrl3Key = "ha_url3"
    private let highAvailabilityUrl4Key = "ha_url4"
    private let activeServerUrlKey = "active_server_url"
    private let lastServerUrlKey = "last_server_url"
    private let beaconUUIDKey = "beacon_uuid"
    private let appUUIDKey = "app_uuid"
    private let deviceNameKey = "device_name"
    private let deviceUUIDKey = "device_uuid"
    private let deviceLocationKey = "device_location"
    private let appConfigKey = "app_config_json"

    init(
        userDefaults: UserDefaults = .standard,
        variant: AppVariant = .demo,
        startupURLResolver: StartupURLResolver = StartupURLResolver()
    ) {
        self.userDefaults = userDefaults
        self.variant = variant
        self.startupURLResolver = startupURLResolver
    }

    var serverURL: String {
        get {
            normalizedSettingValue(userDefaults.string(forKey: serverUrlKey), fallback: variant.defaults.serverURL)
        }
        set {
            userDefaults.set(newValue, forKey: serverUrlKey)
        }
    }

    var securityToken: String {
        get {
            userDefaults.string(forKey: securityTokenKey) ?? variant.defaults.securityToken
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
            return configuredValue > 0 ? configuredValue : variant.defaults.highAvailabilityTimeoutSeconds
        }
        set {
            userDefaults.set(max(1, newValue), forKey: highAvailabilityTimeoutKey)
        }
    }

    var beaconUUIDString: String {
        get {
            normalizedSettingValue(userDefaults.string(forKey: beaconUUIDKey), fallback: variant.defaults.beaconUUID)
        }
        set {
            userDefaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: beaconUUIDKey)
        }
    }

    var beaconUUID: UUID {
        UUID(uuidString: beaconUUIDString) ?? UUID(uuidString: variant.defaults.beaconUUID)!
    }

    var appUUIDString: String {
        ensureAppUUID()
        return normalizedOptionalValue(userDefaults.string(forKey: appUUIDKey)) ?? ""
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

    var appConfig: [String: Any] {
        get { storedJSONObject(forKey: appConfigKey) }
        set { storeJSONObject(newValue, forKey: appConfigKey) }
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

    var loadingImageName: String {
        variant.defaults.loadingImageName
    }

    var recoveryShortMark: String {
        variant.defaults.recoveryShortMark
    }

    var recoveryTitle: String {
        variant.defaults.recoveryTitle
    }

    var recoveryBody: String {
        variant.defaults.recoveryBody
    }

    var recoveryQRCodeDetectedMessage: String {
        variant.defaults.recoveryQRCodeDetectedMessage
    }

    var recoveryInvalidQRMessage: String {
        variant.defaults.recoveryInvalidQRMessage
    }

    func registerDefaults() {
        userDefaults.register(defaults: [
            serverUrlKey: variant.defaults.serverURL,
            securityTokenKey: variant.defaults.securityToken,
            highAvailabilityEnabledKey: false,
            highAvailabilityTimeoutKey: variant.defaults.highAvailabilityTimeoutSeconds,
            highAvailabilityUrl2Key: "",
            highAvailabilityUrl3Key: "",
            highAvailabilityUrl4Key: "",
            activeServerUrlKey: "",
            lastServerUrlKey: "",
            beaconUUIDKey: variant.defaults.beaconUUID,
            appUUIDKey: "",
            deviceNameKey: "",
            deviceUUIDKey: "",
            deviceLocationKey: "",
            appConfigKey: "{}"
        ])
        ensureAppUUID()
        ensureDeviceUUID()
    }

    func resetToDefaultURL() {
        serverURL = variant.defaults.serverURL
    }

    func resetToDefaultSecurityToken() {
        securityToken = variant.defaults.securityToken
    }

    func serverURLCandidates(primaryOverride: String? = nil) -> [String] {
        startupURLResolver.candidates(
            primary: primaryOverride,
            fallback: serverURL,
            highAvailabilityEnabled: highAvailabilityEnabled,
            failoverURLs: [
                userDefaults.string(forKey: highAvailabilityUrl2Key),
                userDefaults.string(forKey: highAvailabilityUrl3Key),
                userDefaults.string(forKey: highAvailabilityUrl4Key)
            ]
        )
    }

    func markActiveServerURL(_ urlString: String) {
        let normalizedValue = normalizedSettingValue(urlString, fallback: variant.defaults.serverURL)
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
            "appUUID": appUUIDString,
            "deviceName": deviceName,
            "deviceUUID": deviceUUIDString,
            "deviceLocation": deviceLocation,
            "appConfig": appConfig
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
        if let value = firstSettingString(values, keys: [
            "serverURL",
            "serverUrl",
            "defaultServerURL",
            "defaultServerUrl",
            "mobileURL",
            "mobileUrl",
            "url"
        ]) {
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
        mergeAppConfig(values["appConfig"] ?? values["app_config"] ?? values["store"])

        userDefaults.synchronize()
        return configurationSnapshot()
    }

    private func ensureAppUUID() {
        let value = normalizedOptionalValue(userDefaults.string(forKey: appUUIDKey))
        if value == nil || value.flatMap(UUID.init(uuidString:)) == nil {
            userDefaults.set(UUID().uuidString, forKey: appUUIDKey)
            userDefaults.synchronize()
        }
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

    private func storedJSONObject(forKey key: String) -> [String: Any] {
        guard let rawValue = userDefaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty,
              let data = rawValue.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return [:]
        }
        return object
    }

    private func storeJSONObject(_ object: [String: Any], forKey key: String) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let rawValue = String(data: data, encoding: .utf8) else {
            return
        }
        userDefaults.set(rawValue, forKey: key)
    }

    private func mergeAppConfig(_ value: Any?) {
        guard let incoming = jsonDictionary(value), !incoming.isEmpty else {
            return
        }
        var merged = appConfig
        for (key, item) in incoming {
            merged[key] = item
        }
        appConfig = merged
    }

    private func jsonDictionary(_ value: Any?) -> [String: Any]? {
        switch value {
        case let dictionary as [String: Any]:
            return sanitizeJSONObject(dictionary) as? [String: Any]
        case let stringValue as String:
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = trimmed.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                return nil
            }
            return sanitizeJSONObject(object) as? [String: Any]
        default:
            return nil
        }
    }

    private func sanitizeJSONObject(_ value: Any) -> Any? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number
        case let dictionary as [String: Any]:
            var result: [String: Any] = [:]
            for (key, item) in dictionary {
                if let sanitized = sanitizeJSONObject(item) {
                    result[key] = sanitized
                }
            }
            return result
        case let array as [Any]:
            return array.compactMap { sanitizeJSONObject($0) }
        default:
            return nil
        }
    }

    private func firstSettingString(_ values: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = settingString(values[key]), !value.isEmpty {
                return value
            }
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
