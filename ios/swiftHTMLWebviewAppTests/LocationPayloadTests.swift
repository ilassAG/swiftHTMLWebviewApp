//
//  LocationPayloadTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class LocationPayloadTests: XCTestCase {
    func testLocationPayloadIncludesProviderTimestampAndAvailableSignals() {
        let payload = LocationPayload.locationPayload(.init(
            latitude: 52.520008,
            longitude: 13.404954,
            accuracyMeters: 4.5,
            altitudeMeters: 37.25,
            speedMetersPerSecond: 1.2,
            bearingDegrees: 88.0,
            provider: "corelocation",
            timestampMs: 1_710_000_000_123
        ))

        XCTAssertEqual(payload["latitude"] as? Double, 52.520008)
        XCTAssertEqual(payload["longitude"] as? Double, 13.404954)
        XCTAssertEqual(payload["accuracyMeters"] as? Double, 4.5)
        XCTAssertEqual(payload["altitudeMeters"] as? Double, 37.25)
        XCTAssertEqual(payload["speedMetersPerSecond"] as? Double, 1.2)
        XCTAssertEqual(payload["bearingDegrees"] as? Double, 88.0)
        XCTAssertEqual(payload["provider"] as? String, "corelocation")
        XCTAssertEqual(payload["timestampMs"] as? Int, 1_710_000_000_123)
    }

    func testLocationPayloadUsesNullForMissingOptionalSignals() {
        let payload = LocationPayload.locationPayload(.init(
            latitude: 47.3769,
            longitude: 8.5417,
            accuracyMeters: nil,
            altitudeMeters: nil,
            speedMetersPerSecond: nil,
            bearingDegrees: nil,
            provider: "",
            timestampMs: 1_710_000_000_456
        ))

        XCTAssertTrue(payload["accuracyMeters"] is NSNull)
        XCTAssertTrue(payload["altitudeMeters"] is NSNull)
        XCTAssertTrue(payload["speedMetersPerSecond"] is NSNull)
        XCTAssertTrue(payload["bearingDegrees"] is NSNull)
        XCTAssertEqual(payload["provider"] as? String, "")
        XCTAssertEqual(payload["timestampMs"] as? Int, 1_710_000_000_456)
    }

    func testResponseWrapsLocationInCommonBridgeEnvelope() {
        let response = LocationPayload.response(
            request: ["requestId": "req-location"],
            action: "geoLocationGet",
            location: .init(
                latitude: 48.137154,
                longitude: 11.576124,
                accuracyMeters: 3.0,
                altitudeMeters: nil,
                speedMetersPerSecond: nil,
                bearingDegrees: nil,
                provider: "corelocation",
                timestampMs: 1_710_000_000_789
            )
        )

        XCTAssertEqual(response["platform"] as? String, "ios")
        XCTAssertEqual(response["action"] as? String, "geoLocationGet")
        XCTAssertEqual(response["requestId"] as? String, "req-location")
        XCTAssertEqual(response["success"] as? Bool, true)
        let location = response["location"] as? [String: Any]
        XCTAssertEqual(location?["latitude"] as? Double, 48.137154)
        XCTAssertEqual(location?["longitude"] as? Double, 11.576124)
        XCTAssertEqual(location?["provider"] as? String, "corelocation")
    }

    func testStartStopErrorsAndDistanceUseCommonShape() {
        let request: [String: Any] = ["requestId": "req-location-stream"]
        let start = LocationPayload.startResponse(
            request: request,
            authorized: false,
            minDistanceMeters: 12.5
        )

        XCTAssertEqual(start["platform"] as? String, "ios")
        XCTAssertEqual(start["action"] as? String, "geoLocationStart")
        XCTAssertEqual(start["requestId"] as? String, "req-location-stream")
        XCTAssertEqual(start["success"] as? Bool, false)
        XCTAssertEqual(start["pendingPermission"] as? Bool, true)
        XCTAssertEqual(start["minDistanceMeters"] as? Double, 12.5)

        let stop = LocationPayload.stopResponse(request: request)
        XCTAssertEqual(stop["action"] as? String, "geoLocationStop")
        XCTAssertEqual(stop["success"] as? Bool, true)

        let error = LocationPayload.errorResponse(
            request: request,
            action: "geoLocationGet",
            error: "Location permission was denied."
        )
        XCTAssertEqual(error["action"] as? String, "geoLocationGet")
        XCTAssertEqual(error["success"] as? Bool, false)
        XCTAssertEqual(error["error"] as? String, "Location permission was denied.")

        XCTAssertEqual(LocationPayload.minDistanceMeters(from: [:], fallback: -1), -1)
        XCTAssertEqual(LocationPayload.minDistanceMeters(from: ["minDistanceMeters": "25.5"], fallback: -1), 25.5)
    }
}
