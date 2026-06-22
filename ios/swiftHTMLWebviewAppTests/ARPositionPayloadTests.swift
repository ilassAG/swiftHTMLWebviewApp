//
//  ARPositionPayloadTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class ARPositionPayloadTests: XCTestCase {
    func testIntervalDefaultsRoundsAndClamps() {
        XCTAssertEqual(ARPositionPayload.intervalMs(from: [:]), 500)
        XCTAssertEqual(ARPositionPayload.intervalMs(from: ["intervalMs": 33]), 100)
        XCTAssertEqual(ARPositionPayload.intervalMs(from: ["intervalMs": 250.6]), 251)
        XCTAssertEqual(ARPositionPayload.intervalMs(from: ["intervalMs": "750"]), 750)
        XCTAssertEqual(ARPositionPayload.intervalMs(from: ["intervalMs": 5_000]), 2_000)
        XCTAssertEqual(ARPositionPayload.intervalMs(from: ["intervalMs": Double.nan]), 500)
    }

    func testStartPendingAndStopResponsesUseCommonShape() {
        let request: [String: Any] = ["requestId": "req-ar"]

        let start = ARPositionPayload.startResponse(
            request: request,
            intervalMs: 250,
            trackingSupported: true
        )
        XCTAssertEqual(start["platform"] as? String, "ios")
        XCTAssertEqual(start["action"] as? String, "arPositionStart")
        XCTAssertEqual(start["requestId"] as? String, "req-ar")
        XCTAssertEqual(start["success"] as? Bool, true)
        XCTAssertEqual(start["source"] as? String, "arkit")
        XCTAssertEqual(start["intervalMs"] as? Int, 250)
        XCTAssertEqual(start["coordinateSystem"] as? String, "arkit-gravity-local")
        XCTAssertEqual(start["trackingSupported"] as? Bool, true)

        let pending = ARPositionPayload.startResponse(
            request: request,
            intervalMs: 500,
            trackingSupported: true,
            pendingPermission: true
        )
        XCTAssertEqual(pending["success"] as? Bool, false)
        XCTAssertEqual(pending["pendingPermission"] as? Bool, true)

        let stop = ARPositionPayload.stopResponse(request: request)
        XCTAssertEqual(stop["platform"] as? String, "ios")
        XCTAssertEqual(stop["action"] as? String, "arPositionStop")
        XCTAssertEqual(stop["requestId"] as? String, "req-ar")
        XCTAssertEqual(stop["success"] as? Bool, true)
    }

    func testErrorAndInterruptionResponsesUseCommonShape() {
        let request: [String: Any] = ["requestId": "req-ar-error"]

        let error = ARPositionPayload.errorResponse(
            request: request,
            action: "arPositionStart",
            error: "Camera permission is required.",
            trackingSupported: false
        )
        XCTAssertEqual(error["platform"] as? String, "ios")
        XCTAssertEqual(error["action"] as? String, "arPositionStart")
        XCTAssertEqual(error["requestId"] as? String, "req-ar-error")
        XCTAssertEqual(error["success"] as? Bool, false)
        XCTAssertEqual(error["source"] as? String, "arkit")
        XCTAssertEqual(error["trackingSupported"] as? Bool, false)
        XCTAssertEqual(error["error"] as? String, "Camera permission is required.")

        let interrupted = ARPositionPayload.interruptionEvent(request: request)
        XCTAssertEqual(interrupted["action"] as? String, "arPosition")
        XCTAssertEqual(interrupted["success"] as? Bool, false)
        XCTAssertEqual(interrupted["source"] as? String, "arkit")
        XCTAssertEqual(interrupted["interrupted"] as? Bool, true)
        XCTAssertEqual(interrupted["error"] as? String, "AR session was interrupted.")
    }

    func testPositionEventUsesCatalogedPayloadShape() {
        let request: [String: Any] = ["requestId": "req-ar-event"]
        let transform = (0..<16).map(Double.init)
        let event = ARPositionPayload.positionEvent(
            request: request,
            timestampMs: 1_710_000_000_123,
            arTimestampSeconds: 12.25,
            elapsedSeconds: 3.5,
            trackingState: "limited",
            trackingReason: "initializing",
            position: .init(x: 1.0, y: 2.0, z: -3.0),
            orientation: .init(x: 0.1, y: -0.2, z: 0.3),
            transform: transform
        )

        XCTAssertEqual(event["platform"] as? String, "ios")
        XCTAssertEqual(event["action"] as? String, "arPosition")
        XCTAssertEqual(event["requestId"] as? String, "req-ar-event")
        XCTAssertEqual(event["success"] as? Bool, true)
        XCTAssertEqual(event["source"] as? String, "arkit")
        XCTAssertEqual(event["coordinateSystem"] as? String, "arkit-gravity-local")
        XCTAssertEqual(event["timestampMs"] as? Int, 1_710_000_000_123)
        XCTAssertEqual(event["arTimestampSeconds"] as? Double, 12.25)
        XCTAssertEqual(event["elapsedSeconds"] as? Double, 3.5)
        XCTAssertEqual(event["trackingSupported"] as? Bool, true)
        XCTAssertEqual(event["trackingState"] as? String, "limited")
        XCTAssertEqual(event["trackingReason"] as? String, "initializing")

        let position = event["position"] as? [String: Any]
        XCTAssertEqual(position?["x"] as? Double, 1.0)
        XCTAssertEqual(position?["y"] as? Double, 2.0)
        XCTAssertEqual(position?["z"] as? Double, -3.0)
        XCTAssertEqual(position?["unit"] as? String, "meters")

        let orientation = event["orientation"] as? [String: Any]
        XCTAssertEqual(orientation?["pitch"] as? Double, 0.1)
        XCTAssertEqual(orientation?["yaw"] as? Double, -0.2)
        XCTAssertEqual(orientation?["roll"] as? Double, 0.3)
        XCTAssertEqual(orientation?["unit"] as? String, "radians")

        XCTAssertEqual(event["transform"] as? [Double], transform)
    }

    func testPositionEventOmitsBlankTrackingReason() {
        let event = ARPositionPayload.positionEvent(
            request: [:],
            timestampMs: 1,
            arTimestampSeconds: 2,
            elapsedSeconds: 3,
            trackingState: "normal",
            trackingReason: "",
            position: .init(x: 0, y: 0, z: 0),
            orientation: .init(x: 0, y: 0, z: 0),
            transform: []
        )

        XCTAssertNil(event["trackingReason"])
    }
}
