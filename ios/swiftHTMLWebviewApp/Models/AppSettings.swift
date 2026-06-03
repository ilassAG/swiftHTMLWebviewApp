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
            beaconUUIDKey: defaultBeaconUUID
        ])
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
}
