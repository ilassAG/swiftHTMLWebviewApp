//
//  DeviceBridgePayloadTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class DeviceBridgePayloadTests: XCTestCase {
    func testCapabilitiesReflectInjectedRuntimeSupport() {
        let capabilities = DeviceBridgePayload.capabilities(
            arPositionSupported: false,
            arGuidedMeasurementSupported: true,
            arOverlaySupported: false,
            roomPlanSupported: true,
            nfcTagReadAvailable: false,
            beaconAdvertiseSupported: true
        )

        XCTAssertEqual(capabilities["deviceInfoGet"] as? Bool, true)
        XCTAssertEqual(capabilities["settingsGet"] as? Bool, true)
        XCTAssertEqual(capabilities["settingsSet"] as? Bool, true)
        XCTAssertEqual(capabilities["storageGet"] as? Bool, true)
        XCTAssertEqual(capabilities["filesystemWrite"] as? Bool, true)
        XCTAssertEqual(capabilities["sqliteExecute"] as? Bool, true)
        XCTAssertEqual(capabilities["kioskReloadControlSet"] as? Bool, true)
        XCTAssertEqual(capabilities["wifiConfigure"] as? Bool, true)
        XCTAssertEqual(capabilities["screenshotGet"] as? Bool, true)
        XCTAssertEqual(capabilities["soundPlay"] as? Bool, true)
        XCTAssertEqual(capabilities["screenStreamFormats"] as? [String], ["jpeg"])
        XCTAssertEqual(capabilities["arPositionStart"] as? Bool, false)
        XCTAssertEqual(capabilities["arGuidedMeasurementStart"] as? Bool, true)
        XCTAssertEqual(capabilities["arOverlayOpen"] as? Bool, false)
        XCTAssertEqual(capabilities["roomPlanScanStart"] as? Bool, true)
        XCTAssertEqual(capabilities["nfcTagRead"] as? Bool, false)
        XCTAssertEqual(capabilities["beaconAdvertiseStart"] as? Bool, true)
    }

    func testWifiConfigureRequestNormalizesFields() {
        let request = DeviceBridgePayload.wifiConfigureRequest(from: [
            "requestId": "req-wifi",
            "ssid": " Standort-WLAN ",
            "password": " fallback-password ",
            "passphrase": " preferred-password ",
            "joinOnce": "true"
        ])

        XCTAssertEqual(request.requestId, "req-wifi")
        XCTAssertEqual(request.ssid, "Standort-WLAN")
        XCTAssertEqual(request.passphrase, "preferred-password")
        XCTAssertEqual(request.joinOnce, true)

        let fallback = DeviceBridgePayload.wifiConfigureRequest(from: [
            "requestId": "",
            "ssid": "Open",
            "password": " fallback-password "
        ])
        XCTAssertNil(fallback.requestId)
        XCTAssertEqual(fallback.passphrase, "fallback-password")
        XCTAssertEqual(fallback.joinOnce, false)
    }

    func testWifiStatusPayloadsUseStableShape() {
        let unavailable = DeviceBridgePayload.wifiInfo(
            ipAddresses: ["192.0.2.10"],
            wifiIpAddresses: ["192.0.2.11"]
        )

        XCTAssertEqual(unavailable["ipAddresses"] as? [String], ["192.0.2.10"])
        XCTAssertEqual(unavailable["wifiIpAddresses"] as? [String], ["192.0.2.11"])
        XCTAssertEqual(unavailable["ssid"] as? String, "unavailable")
        XCTAssertEqual(unavailable["ssidAvailable"] as? Bool, false)
        XCTAssertNotNil(unavailable["unavailableReason"] as? String)

        let current = DeviceBridgePayload.wifiInfo(
            ipAddresses: ["192.0.2.10"],
            wifiIpAddresses: ["192.0.2.11"],
            currentNetwork: .init(ssid: "Office", bssid: "aa:bb:cc", securityTypeRawValue: 2)
        )

        XCTAssertEqual(current["ssidAvailable"] as? Bool, true)
        XCTAssertEqual(current["ssid"] as? String, "Office")
        XCTAssertEqual(current["bssid"] as? String, "aa:bb:cc")
        XCTAssertEqual(current["securityType"] as? String, "personal")
        XCTAssertEqual(current["securityTypeRawValue"] as? Int, 2)
        XCTAssertEqual(DeviceBridgePayload.hotspotSecurityTypeName(rawValue: 0), "open")
        XCTAssertEqual(DeviceBridgePayload.hotspotSecurityTypeName(rawValue: 1), "wep")
        XCTAssertEqual(DeviceBridgePayload.hotspotSecurityTypeName(rawValue: 3), "enterprise")
        XCTAssertEqual(DeviceBridgePayload.hotspotSecurityTypeName(rawValue: 99), "unknown")
    }

    func testWifiResponsesAndErrorsUseContractShape() {
        let status = DeviceBridgePayload.wifiStatusResponse(
            requestId: "req-status",
            wifi: ["ssidAvailable": false]
        )
        XCTAssertEqual(status["platform"] as? String, "ios")
        XCTAssertEqual(status["action"] as? String, "wifiStatusGet")
        XCTAssertEqual(status["requestId"] as? String, "req-status")
        XCTAssertEqual(status["success"] as? Bool, true)

        let configure = DeviceBridgePayload.wifiConfigureResponse(
            requestId: "req-config",
            ssid: "Office",
            joinOnce: true,
            persistedServerURL: "https://example.invalid/mobile/"
        )
        XCTAssertEqual(configure["action"] as? String, "wifiConfigure")
        XCTAssertEqual(configure["method"] as? String, "NEHotspotConfiguration")
        XCTAssertEqual(configure["ssid"] as? String, "Office")
        XCTAssertEqual(configure["joinOnce"] as? Bool, true)
        XCTAssertEqual(configure["serverURL"] as? String, "https://example.invalid/mobile/")
        XCTAssertEqual(configure["serverURLPersisted"] as? Bool, true)

        var response: [String: Any] = [:]
        DeviceBridgePayload.applyWifiErrorDetails(kind: .userDenied, message: "", response: &response)
        XCTAssertEqual(response["capabilityRequired"] as? String, "Hotspot Configuration")
        XCTAssertEqual(response["error"] as? String, "The user cancelled the Wi-Fi join request.")

        response = [:]
        DeviceBridgePayload.applyWifiErrorDetails(kind: .invalidSSID, message: "", response: &response)
        XCTAssertEqual(response["error"] as? String, "The SSID is invalid.")

        response = [:]
        DeviceBridgePayload.applyWifiErrorDetails(kind: .invalidWPAPassphrase, message: "", response: &response)
        XCTAssertEqual(response["error"] as? String, "The Wi-Fi password is invalid for the selected security mode.")

        response = [:]
        DeviceBridgePayload.applyWifiErrorDetails(kind: .pending, message: "", response: &response)
        XCTAssertEqual(response["error"] as? String, "A Wi-Fi configuration request is already pending.")

        response = [:]
        DeviceBridgePayload.applyWifiErrorDetails(kind: .applicationIsNotInForeground, message: "", response: &response)
        XCTAssertEqual(response["error"] as? String, "The app must be in the foreground to configure Wi-Fi.")

        response = [:]
        DeviceBridgePayload.applyWifiErrorDetails(kind: .other, message: "internal error.", response: &response)
        XCTAssertEqual(response["error"] as? String, "NEHotspotConfiguration returned an internal error. The app is probably not signed with the Hotspot Configuration capability/entitlement.")
    }

    func testSoundRequestClampsAndResponseEchoesNormalizedValues() {
        let sound = DeviceBridgePayload.soundRequest(from: [
            "frequencyHz": 10,
            "durationMs": 9000,
            "volume": 2.5
        ])

        XCTAssertEqual(sound.frequencyHz, 80)
        XCTAssertEqual(sound.durationMs, 5000)
        XCTAssertEqual(sound.volume, 1.0)

        let response = DeviceBridgePayload.soundResponse(
            request: ["requestId": "req-sound"],
            sound: sound
        )
        XCTAssertEqual(response["platform"] as? String, "ios")
        XCTAssertEqual(response["action"] as? String, "soundPlay")
        XCTAssertEqual(response["requestId"] as? String, "req-sound")
        XCTAssertEqual(response["success"] as? Bool, true)
        XCTAssertEqual(response["frequencyHz"] as? Int, 80)
        XCTAssertEqual(response["durationMs"] as? Int, 5000)
        XCTAssertEqual(response["volume"] as? Double, 1.0)
    }
}
