//
//  BeaconPayloadTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class BeaconPayloadTests: XCTestCase {
    private let defaultUUID = UUID(uuidString: "7763A937-B779-4D31-A20C-49E83047048F")!

    func testRangingUUIDUsesFallbackAndNormalizesValidRequests() {
        XCTAssertEqual(BeaconPayload.rangingUUID(from: [:], defaultUUID: defaultUUID), defaultUUID)
        XCTAssertEqual(BeaconPayload.rangingUUID(from: ["uuid": "bad"], defaultUUID: defaultUUID), defaultUUID)

        let requested = BeaconPayload.rangingUUID(
            from: ["uuid": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"],
            defaultUUID: defaultUUID
        )
        XCTAssertEqual(requested.uuidString, "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
    }

    func testRangingStartStopAndErrorResponsesUseCommonBridgeShape() {
        let request: [String: Any] = ["requestId": "req-beacon"]
        let start = BeaconPayload.rangingStartResponse(
            request: request,
            uuid: defaultUUID,
            success: true
        )

        XCTAssertEqual(start["platform"] as? String, "ios")
        XCTAssertEqual(start["action"] as? String, "beaconsStart")
        XCTAssertEqual(start["requestId"] as? String, "req-beacon")
        XCTAssertEqual(start["success"] as? Bool, true)
        XCTAssertEqual(start["uuid"] as? String, defaultUUID.uuidString)
        XCTAssertEqual(start["provider"] as? String, BeaconPayload.rangingProvider)

        let denied = BeaconPayload.rangingStartResponse(
            request: request,
            uuid: defaultUUID,
            success: false,
            error: "Location permission is required for iBeacon ranging."
        )
        XCTAssertEqual(denied["success"] as? Bool, false)
        XCTAssertEqual(denied["error"] as? String, "Location permission is required for iBeacon ranging.")

        let stop = BeaconPayload.rangingStopResponse(request: request)
        XCTAssertEqual(stop["platform"] as? String, "ios")
        XCTAssertEqual(stop["action"] as? String, "beaconsStop")
        XCTAssertEqual(stop["requestId"] as? String, "req-beacon")
        XCTAssertEqual(stop["success"] as? Bool, true)
    }

    func testBeaconEventUsesCatalogedPayloadShape() {
        let beacon = BeaconPayload.beaconObject(
            proximityUUID: defaultUUID,
            major: 10,
            minor: 20,
            proximity: "near",
            accuracy: 2.25,
            rssi: -71
        )
        let timestamp = Date(timeIntervalSince1970: 1_710_000_000.123)
        let event = BeaconPayload.rangingEvent(uuid: defaultUUID, beacons: [beacon], timestamp: timestamp)

        XCTAssertEqual(event["platform"] as? String, "ios")
        XCTAssertEqual(event["action"] as? String, "beacons")
        XCTAssertEqual(event["success"] as? Bool, true)
        XCTAssertEqual(event["uuid"] as? String, defaultUUID.uuidString)
        XCTAssertEqual(event["count"] as? Int, 1)
        XCTAssertEqual(event["timestamp"] as? String, "2024-03-09T16:00:00Z")

        let beacons = event["beacons"] as? [[String: Any]]
        XCTAssertEqual(beacons?.first?["proximityUUID"] as? String, defaultUUID.uuidString)
        XCTAssertEqual(beacons?.first?["major"] as? Int, 10)
        XCTAssertEqual(beacons?.first?["minor"] as? Int, 20)
        XCTAssertEqual(beacons?.first?["proximity"] as? String, "near")
        XCTAssertEqual(beacons?.first?["accuracy"] as? Double, 2.25)
        XCTAssertEqual(beacons?.first?["rssi"] as? Int, -71)
    }

    func testAdvertiseConfigAcceptsAliasesDefaultsAndRejectsInvalidValues() {
        let config = BeaconPayload.advertiseConfig(
            from: [
                "beaconUuid": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                "major": "7",
                "minor": 9,
                "txPower": "-65"
            ],
            defaultUUID: defaultUUID
        )

        XCTAssertEqual(config?.uuid.uuidString, "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        XCTAssertEqual(config?.major, 7)
        XCTAssertEqual(config?.minor, 9)
        XCTAssertEqual(config?.measuredPower, -65)

        let defaults = BeaconPayload.advertiseConfig(from: [:], defaultUUID: defaultUUID)
        XCTAssertEqual(defaults?.uuid, defaultUUID)
        XCTAssertEqual(defaults?.major, 1)
        XCTAssertEqual(defaults?.minor, 1)
        XCTAssertNil(defaults?.measuredPower)

        XCTAssertNil(BeaconPayload.advertiseConfig(from: ["uuid": "bad"], defaultUUID: defaultUUID))
        XCTAssertNil(BeaconPayload.advertiseConfig(from: ["major": -1], defaultUUID: defaultUUID))
        XCTAssertNil(BeaconPayload.advertiseConfig(from: ["minor": 65_536], defaultUUID: defaultUUID))
        XCTAssertNil(BeaconPayload.advertiseConfig(from: ["measuredPower": -128], defaultUUID: defaultUUID))
        XCTAssertNil(BeaconPayload.advertiseConfig(from: ["measuredPowerDbm": 21], defaultUUID: defaultUUID))
    }

    func testAdvertiseStartStopStateAndErrorResponsesUseCommonShape() {
        let request: [String: Any] = ["requestId": "req-adv"]
        let config = BeaconPayload.advertiseConfig(
            from: [
                "uuid": defaultUUID.uuidString,
                "major": 2,
                "minor": 3,
                "measuredPower": -70
            ],
            defaultUUID: defaultUUID
        )!

        let start = BeaconPayload.advertiseStartResponse(
            request: request,
            config: config,
            state: "starting"
        )
        XCTAssertEqual(start["platform"] as? String, "ios")
        XCTAssertEqual(start["action"] as? String, "beaconAdvertiseStart")
        XCTAssertEqual(start["requestId"] as? String, "req-adv")
        XCTAssertEqual(start["success"] as? Bool, true)
        XCTAssertEqual(start["provider"] as? String, BeaconPayload.advertiserProvider)
        XCTAssertEqual(start["state"] as? String, "starting")
        XCTAssertEqual(start["uuid"] as? String, defaultUUID.uuidString)
        XCTAssertEqual(start["major"] as? Int, 2)
        XCTAssertEqual(start["minor"] as? Int, 3)
        XCTAssertEqual(start["measuredPower"] as? Int, -70)

        let event = BeaconPayload.advertiseStateEvent(
            request: request,
            config: config,
            success: false,
            state: "advertisingFailed",
            advertising: false,
            error: "Bluetooth is required."
        )
        XCTAssertEqual(event["action"] as? String, "beaconAdvertiseStart")
        XCTAssertEqual(event["success"] as? Bool, false)
        XCTAssertEqual(event["advertising"] as? Bool, false)
        XCTAssertEqual(event["error"] as? String, "Bluetooth is required.")

        let stop = BeaconPayload.advertiseStopResponse(request: request)
        XCTAssertEqual(stop["action"] as? String, "beaconAdvertiseStop")
        XCTAssertEqual(stop["success"] as? Bool, true)
        XCTAssertEqual(stop["state"] as? String, "stopped")

        let error = BeaconPayload.errorResponse(
            request: request,
            action: "beaconAdvertiseStart",
            error: "Invalid iBeacon parameters."
        )
        XCTAssertEqual(error["success"] as? Bool, false)
        XCTAssertEqual(error["error"] as? String, "Invalid iBeacon parameters.")
    }
}
