//
//  DeviceBridgePayload.swift
//  swiftHTMLWebviewApp
//
//  Pure payload and request helpers for device/runtime bridge actions.
//

import Foundation

enum DeviceBridgePayload {
    struct WifiConfigureRequest {
        let requestId: String?
        let ssid: String
        let passphrase: String
        let joinOnce: Bool
    }

    struct SoundRequest {
        let frequencyHz: Int
        let durationMs: Int
        let volume: Double
    }

    struct CurrentWiFi {
        let ssid: String
        let bssid: String
        let securityTypeRawValue: Int
    }

    enum WifiErrorKind {
        case userDenied
        case invalidSSID
        case invalidWPAPassphrase
        case invalidWEPPassphrase
        case pending
        case applicationIsNotInForeground
        case other
    }

    static func baseResponse(request: [String: Any], action: String) -> [String: Any] {
        BridgeResponse.base(request: request, action: action)
    }

    static func baseResponse(requestId: String?, action: String) -> [String: Any] {
        var response = BridgeResponse.base(request: [:], action: action)
        if let requestId {
            response["requestId"] = requestId
        }
        return response
    }

    static func errorResponse(request: [String: Any], action: String, error: String) -> [String: Any] {
        BridgeResponse.error(request: request, action: action, message: error)
    }

    static func capabilities(
        arPositionSupported: Bool,
        arGuidedMeasurementSupported: Bool,
        arOverlaySupported: Bool,
        roomPlanSupported: Bool,
        nfcTagReadAvailable: Bool,
        beaconAdvertiseSupported: Bool
    ) -> [String: Any] {
        [
            "deviceInfoGet": true,
            "settingsGet": true,
            "settingsSet": true,
            "storageGet": true,
            "storageSet": true,
            "storageRemove": true,
            "storageClear": true,
            "filesystemWrite": true,
            "filesystemRead": true,
            "filesystemList": true,
            "filesystemDelete": true,
            "sqliteExecute": true,
            "sqliteDeleteDatabase": true,
            "kioskReloadControlSet": true,
            "screenOrientationSet": true,
            "wifiConfigure": true,
            "screenshotGet": true,
            "geoLocationGet": true,
            "arPositionStart": arPositionSupported,
            "arPositionStop": true,
            "arPositionSupported": arPositionSupported,
            "arGuidedMeasurementStart": arGuidedMeasurementSupported,
            "arGuidedMeasurementSetAnchors": arGuidedMeasurementSupported,
            "arGuidedMeasurementUpdateStats": arGuidedMeasurementSupported,
            "arGuidedMeasurementStop": true,
            "arGuidedMeasurementSupported": arGuidedMeasurementSupported,
            "arOverlayOpen": arOverlaySupported,
            "arOverlayClose": true,
            "arOverlaySupported": arOverlaySupported,
            "arOverlayWGS84": arOverlaySupported,
            "arReplayOpen": arOverlaySupported,
            "arReplayClose": true,
            "roomPlanScanStart": roomPlanSupported,
            "roomPlanScanStop": roomPlanSupported,
            "roomPlanScanExport": true,
            "roomPlanSupported": roomPlanSupported,
            "screenStreamStart": true,
            "screenStreamFormats": ["jpeg"],
            "natsProvision": true,
            "natsStatus": true,
            "natsConnect": true,
            "natsDisconnect": true,
            "natsPublish": true,
            "soundPlay": true,
            "notificationPermissionGet": true,
            "notificationPermissionRequest": true,
            "notificationShow": true,
            "notificationSchedule": true,
            "notificationCancel": true,
            "notificationCancelAll": true,
            "notificationList": true,
            "idleTimerStart": true,
            "sensorStreamStart": true,
            "nfcTagRead": nfcTagReadAvailable,
            "beaconAdvertiseStart": beaconAdvertiseSupported,
            "beaconAdvertiseStop": true,
            "beaconAdvertiseSupported": beaconAdvertiseSupported
        ]
    }

    static func wifiConfigureRequest(from request: [String: Any]) -> WifiConfigureRequest {
        let passphraseValue = stringValue(request["passphrase"]).isEmpty
            ? stringValue(request["password"])
            : stringValue(request["passphrase"])
        return WifiConfigureRequest(
            requestId: requestId(from: request),
            ssid: stringValue(request["ssid"]).trimmingCharacters(in: .whitespacesAndNewlines),
            passphrase: passphraseValue.trimmingCharacters(in: .whitespacesAndNewlines),
            joinOnce: boolValue(request["joinOnce"]) ?? false
        )
    }

    static func wifiStatusResponse(requestId: String?, wifi: [String: Any]) -> [String: Any] {
        var response = baseResponse(requestId: requestId, action: "wifiStatusGet")
        response["success"] = true
        response["wifi"] = wifi
        return response
    }

    static func wifiInfo(
        ipAddresses: [String],
        wifiIpAddresses: [String],
        currentNetwork: CurrentWiFi? = nil
    ) -> [String: Any] {
        var info: [String: Any] = [
            "ipAddresses": ipAddresses,
            "wifiIpAddresses": wifiIpAddresses
        ]

        guard let currentNetwork else {
            info["ssid"] = "unavailable"
            info["ssidAvailable"] = false
            info["unavailableReason"] = "No current Wi-Fi details returned by iOS. The app needs the Access WiFi Information entitlement and either precise location authorization, a current network configured through NEHotspotConfiguration, an active VPN configuration, or an active DNS settings configuration."
            return info
        }

        info["ssidAvailable"] = true
        info["ssid"] = currentNetwork.ssid
        info["bssid"] = currentNetwork.bssid
        info["securityType"] = hotspotSecurityTypeName(rawValue: currentNetwork.securityTypeRawValue)
        info["securityTypeRawValue"] = currentNetwork.securityTypeRawValue
        return info
    }

    static func wifiConfigureResponse(
        requestId: String?,
        ssid: String,
        joinOnce: Bool,
        persistedServerURL: String?
    ) -> [String: Any] {
        var response = baseResponse(requestId: requestId, action: "wifiConfigure")
        response["success"] = true
        response["method"] = "NEHotspotConfiguration"
        response["ssid"] = ssid
        response["joinOnce"] = joinOnce
        if let persistedServerURL {
            response["serverURL"] = persistedServerURL
            response["serverURLPersisted"] = true
        }
        return response
    }

    static func applyWifiErrorDetails(kind: WifiErrorKind, message: String, response: inout [String: Any]) {
        response["capabilityRequired"] = "Hotspot Configuration"

        switch kind {
        case .userDenied:
            response["error"] = "The user cancelled the Wi-Fi join request."
        case .invalidSSID:
            response["error"] = "The SSID is invalid."
        case .invalidWPAPassphrase, .invalidWEPPassphrase:
            response["error"] = "The Wi-Fi password is invalid for the selected security mode."
        case .pending:
            response["error"] = "A Wi-Fi configuration request is already pending."
        case .applicationIsNotInForeground:
            response["error"] = "The app must be in the foreground to configure Wi-Fi."
        case .other:
            let nativeMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if nativeMessage.lowercased().contains("internal") {
                response["error"] = "NEHotspotConfiguration returned an internal error. The app is probably not signed with the Hotspot Configuration capability/entitlement."
            } else {
                response["error"] = nativeMessage.isEmpty ? "Wi-Fi configuration failed." : nativeMessage
            }
        }
    }

    static func soundRequest(from request: [String: Any]) -> SoundRequest {
        SoundRequest(
            frequencyHz: max(80, min(4000, intValue(request["frequencyHz"]) ?? 880)),
            durationMs: max(40, min(5000, intValue(request["durationMs"]) ?? 240)),
            volume: max(0.0, min(1.0, doubleValue(request["volume"]) ?? 0.85))
        )
    }

    static func soundResponse(request: [String: Any], sound: SoundRequest) -> [String: Any] {
        var response = baseResponse(request: request, action: "soundPlay")
        response["success"] = true
        response["frequencyHz"] = sound.frequencyHz
        response["durationMs"] = sound.durationMs
        response["volume"] = sound.volume
        return response
    }

    static func requestId(from request: [String: Any]) -> String? {
        request["requestId"]
            .map { stringValue($0) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    static func hotspotSecurityTypeName(rawValue: Int) -> String {
        switch rawValue {
        case 0: return "open"
        case 1: return "wep"
        case 2: return "personal"
        case 3: return "enterprise"
        default: return "unknown"
        }
    }
}
