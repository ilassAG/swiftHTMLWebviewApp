//
//  ConfigPairingPayloadTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class ConfigPairingPayloadTests: XCTestCase {
    func testPairingPayloadRoundTripsIdentityFields() {
        let identity = ConfigPairingPayload.identity(
            settings: [
                "appUUID": "app-123",
                "deviceName": "Demo Tablet 03",
                "deviceUUID": "device-123",
                "deviceLocation": "Hall A / Entrance"
            ],
            fallbackName: "Fallback"
        )

        let payload = ConfigPairingPayload.pairingPayload(
            sessionID: "session-1",
            secret: "secret+/=",
            expiresAt: Date(timeIntervalSince1970: 300),
            identity: identity
        )
        let target = ConfigPairingPayload.PairingTarget(payload: payload)

        XCTAssertNotNil(target)
        XCTAssertEqual(target?.sessionID, "session-1")
        XCTAssertEqual(target?.secret, "secret+/=")
        XCTAssertEqual(target?.serviceUUID, ConfigPairingPayload.serviceUUID)
        XCTAssertEqual(target?.name, "Demo Tablet 03")
        XCTAssertEqual(target?.appUUID, "app-123")
        XCTAssertEqual(target?.deviceName, "Demo Tablet 03")
        XCTAssertEqual(target?.deviceUUID, "device-123")
        XCTAssertEqual(target?.deviceLocation, "Hall A / Entrance")
        XCTAssertEqual(target?.identity["appUUID"], "app-123")
        XCTAssertEqual(target?.identity["deviceLocation"], "Hall A / Entrance")
    }

    func testPairingTargetParseSupportsLegacyAliasesDuplicatesAndRejectsInvalidPayloads() {
        let payload = "swifthtml-config://pair?id=first&id=session-2&secret=t&device_name=Legacy%20Name&device_uuid=uuid-1&device_location=Bar"
        let target = ConfigPairingPayload.PairingTarget(payload: payload)

        XCTAssertNotNil(target)
        XCTAssertEqual(target?.sessionID, "session-2")
        XCTAssertEqual(target?.appUUID, "")
        XCTAssertEqual(target?.deviceName, "Legacy Name")
        XCTAssertEqual(target?.deviceUUID, "uuid-1")
        XCTAssertEqual(target?.deviceLocation, "Bar")
        XCTAssertEqual(target?.name, "Legacy Name")

        XCTAssertNil(ConfigPairingPayload.PairingTarget(payload: "https://example.invalid/?id=s&secret=t"))
        XCTAssertNil(ConfigPairingPayload.PairingTarget(payload: "swifthtml-config://pair?id=s"))
    }

    func testCommandUsesDefaultsAliasesAndTrimming() {
        let target = ConfigPairingPayload.PairingTarget(payload: "swifthtml-config://pair?id=session-1&secret=secret-1")!
        let settings = ["serverURL": "https://example.invalid/app/"]
        let command = ConfigPairingPayload.command(
            target: target,
            request: [
                "requestId": "req-1",
                "configCommand": "wifiConfigure",
                "securityToken": " token ",
                "settings": settings,
                "ssid": " Standort ",
                "password": " pass ",
                "joinOnce": true
            ],
            requestId: "req-1"
        )

        XCTAssertEqual(command["sessionId"] as? String, "session-1")
        XCTAssertEqual(command["secret"] as? String, "secret-1")
        XCTAssertEqual(command["requestId"] as? String, "req-1")
        XCTAssertEqual(command["command"] as? String, "wifiConfigure")
        XCTAssertEqual(command["token"] as? String, "token")
        XCTAssertEqual(command["settings"] as? [String: String], settings)
        XCTAssertEqual(command["ssid"] as? String, "Standort")
        XCTAssertEqual(command["passphrase"] as? String, "pass")
        XCTAssertEqual(command["joinOnce"] as? Bool, true)

        let defaultCommand = ConfigPairingPayload.command(target: target, request: [:], requestId: "generated")
        XCTAssertEqual(defaultCommand["command"] as? String, "statusGet")
        XCTAssertEqual(defaultCommand["requestId"] as? String, "generated")
    }

    func testResponseErrorAndEventPayloadsUseBridgeContractShape() {
        let request: [String: Any] = ["requestId": "req-show"]
        let show = ConfigPairingPayload.showResponse(
            request: request,
            payload: "swifthtml-config://pair?id=s&secret=t",
            expiresAt: Date(timeIntervalSince1970: 300),
            identity: ["name": "Target", "appUUID": "app-123", "deviceName": "Target", "deviceUUID": "uuid", "deviceLocation": "Bar"]
        )
        XCTAssertEqual(show["action"] as? String, "configPairingShow")
        XCTAssertEqual(show["platform"] as? String, "ios")
        XCTAssertEqual(show["requestId"] as? String, "req-show")
        XCTAssertEqual(show["success"] as? Bool, true)
        XCTAssertEqual(show["transport"] as? String, "ble-gatt")
        XCTAssertEqual(show["serviceUUID"] as? String, ConfigPairingPayload.serviceUUID)
        XCTAssertEqual(show["appUUID"] as? String, "app-123")

        let response = ConfigPairingPayload.responsePayload(
            command: "settingsGet",
            requestId: "req-2",
            sessionID: "session-2"
        )
        XCTAssertEqual(response["action"] as? String, "configPairingResponse")
        XCTAssertEqual(response["platform"] as? String, "ios")
        XCTAssertEqual(response["role"] as? String, "target")
        XCTAssertEqual(response["command"] as? String, "settingsGet")
        XCTAssertEqual(response["requestId"] as? String, "req-2")
        XCTAssertEqual(response["sessionId"] as? String, "session-2")

        let error = ConfigPairingPayload.errorPayload(
            command: "reload",
            requestId: "req-3",
            sessionID: "session-3",
            error: "no token"
        )
        XCTAssertEqual(error["success"] as? Bool, false)
        XCTAssertEqual(error["command"] as? String, "reload")
        XCTAssertEqual(error["error"] as? String, "no token")

        let event = ConfigPairingPayload.eventPayload(role: "configurator", event: "ready", success: true)
        XCTAssertEqual(event["action"] as? String, "configPairingEvent")
        XCTAssertEqual(event["platform"] as? String, "ios")
        XCTAssertEqual(event["role"] as? String, "configurator")
        XCTAssertEqual(event["event"] as? String, "ready")
        XCTAssertEqual(event["success"] as? Bool, true)
        XCTAssertNil(event["error"])
    }

    func testChunkAccumulatorReassemblesOutOfOrderPayloads() {
        var accumulator = ConfigPairingPayload.ChunkAccumulator(count: 3)
        accumulator.chunks[2] = Data("ld".utf8)
        accumulator.chunks[0] = Data("he".utf8)
        XCTAssertFalse(accumulator.isComplete)
        accumulator.chunks[1] = Data("llo wor".utf8)

        XCTAssertTrue(accumulator.isComplete)
        XCTAssertEqual(String(data: accumulator.assembled, encoding: .utf8), "hello world")
    }

    func testChunkEnvelopeValidationRejectsMalformedChunks() {
        let valid: [String: Any] = [
            "id": "chunk-1",
            "i": 0,
            "n": 1,
            "d": Data("abc".utf8).base64EncodedString()
        ]
        XCTAssertTrue(ConfigPairingPayload.isValidChunkEnvelope(valid))

        var badIndex = valid
        badIndex["i"] = 1
        XCTAssertFalse(ConfigPairingPayload.isValidChunkEnvelope(badIndex))

        var emptyID = valid
        emptyID["id"] = ""
        XCTAssertFalse(ConfigPairingPayload.isValidChunkEnvelope(emptyID))

        var emptyData = valid
        emptyData["d"] = ""
        XCTAssertFalse(ConfigPairingPayload.isValidChunkEnvelope(emptyData))

        var invalidData = valid
        invalidData["d"] = "not-base64!"
        XCTAssertFalse(ConfigPairingPayload.isValidChunkEnvelope(invalidData))
    }
}
