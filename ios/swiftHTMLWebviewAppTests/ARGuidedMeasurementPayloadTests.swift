//
//  ARGuidedMeasurementPayloadTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class ARGuidedMeasurementPayloadTests: XCTestCase {
    func testIntervalWorldMapAndAnchorRequestsNormalizeWithoutARKit() {
        XCTAssertEqual(ARGuidedMeasurementPayload.intervalMs(from: [:]), 500)
        XCTAssertEqual(ARGuidedMeasurementPayload.intervalMs(from: ["intervalMs": 40]), 100)
        XCTAssertEqual(ARGuidedMeasurementPayload.intervalMs(from: ["intervalMs": "250.6"]), 251)
        XCTAssertEqual(ARGuidedMeasurementPayload.intervalMs(from: ["intervalMs": 4_000]), 2_000)
        XCTAssertEqual(ARGuidedMeasurementPayload.intervalMs(from: ["intervalMs": Double.nan]), 500)

        let request: [String: Any] = [
            "worldMapBase64": "  data:application/octet-stream;base64,abc  ",
            "anchors": [
                ["id": "ignore", "kind": "end"],
                ["id": "start-a", "kind": "start", "planX": 1.2]
            ],
            "floorPlan": [
                "planJson": ["floorY": -0.1]
            ]
        ]

        XCTAssertEqual(ARGuidedMeasurementPayload.worldMapBase64(from: request), "data:application/octet-stream;base64,abc")
        XCTAssertTrue(ARGuidedMeasurementPayload.worldMapAvailable(in: request))
        XCTAssertEqual(ARGuidedMeasurementPayload.startAnchor(in: request)?["id"] as? String, "start-a")
        XCTAssertEqual(ARGuidedMeasurementPayload.floorPlanPlan(in: request)?["floorY"] as? Double, -0.1)

        let update: [String: Any] = [
            "startAnchor": ["id": "start-b", "kind": "start"],
            "bounds": ["width": 4]
        ]
        let merged = ARGuidedMeasurementPayload.mergedAnchors(current: request, update: update)
        XCTAssertEqual((merged["startAnchor"] as? [String: Any])?["id"] as? String, "start-b")
        XCTAssertEqual((merged["bounds"] as? [String: Any])?["width"] as? Int, 4)
        XCTAssertNotNil(merged["anchors"])
    }

    func testStartAcknowledgementAndErrorResponsesUseCommonShape() {
        let request: [String: Any] = [
            "requestId": "req-guided",
            "startAnchor": ["id": "start-1", "kind": "start"],
            "worldMapAvailable": true
        ]
        let startAnchor = ARGuidedMeasurementPayload.startAnchor(in: request)

        let ready = ARGuidedMeasurementPayload.readyResponse(
            request: request,
            action: "arGuidedMeasurementStart",
            intervalMs: 750,
            startAnchor: startAnchor,
            worldMapAvailable: true
        )
        XCTAssertEqual(ready["platform"] as? String, "ios")
        XCTAssertEqual(ready["action"] as? String, "arGuidedMeasurementStart")
        XCTAssertEqual(ready["requestId"] as? String, "req-guided")
        XCTAssertEqual(ready["success"] as? Bool, true)
        XCTAssertEqual(ready["supported"] as? Bool, true)
        XCTAssertEqual(ready["source"] as? String, "arkit-guided")
        XCTAssertEqual(ready["coordinateSystem"] as? String, "arkit-gravity-local")
        XCTAssertEqual(ready["intervalMs"] as? Int, 750)
        XCTAssertEqual((ready["startAnchor"] as? [String: Any])?["id"] as? String, "start-1")
        XCTAssertEqual(ready["worldMapAvailable"] as? Bool, true)

        let pending = ARGuidedMeasurementPayload.pendingPermissionResponse(
            request: request,
            intervalMs: 500,
            startAnchor: startAnchor,
            worldMapAvailable: false
        )
        XCTAssertEqual(pending["success"] as? Bool, true)
        XCTAssertEqual(pending["pendingPermission"] as? Bool, true)
        XCTAssertEqual(pending["action"] as? String, "arGuidedMeasurementStart")

        let stop = ARGuidedMeasurementPayload.acknowledgementResponse(
            request: request,
            action: "arGuidedMeasurementStop"
        )
        XCTAssertEqual(stop["success"] as? Bool, true)
        XCTAssertEqual(stop["source"] as? String, "arkit-guided")

        let error = ARGuidedMeasurementPayload.errorResponse(
            request: request,
            action: "arGuidedError",
            error: "Camera permission was denied.",
            supported: false
        )
        XCTAssertEqual(error["success"] as? Bool, false)
        XCTAssertEqual(error["supported"] as? Bool, false)
        XCTAssertEqual(error["source"] as? String, "arkit-guided")
        XCTAssertEqual(error["error"] as? String, "Camera permission was denied.")
    }

    func testPositionAndRelocalizationEventsUseCatalogedPayloadShape() {
        let request: [String: Any] = ["requestId": "req-position"]
        let snapshot = ARGuidedMeasurementPayload.FrameSnapshot(
            arTimestampSeconds: 12.5,
            trackingState: "limited",
            trackingReason: "relocalizing",
            worldMappingStatus: "extending",
            position: .init(x: 1.0, y: 2.0, z: -3.0),
            orientation: .init(pitch: 0.1, yaw: 0.2, headingYaw: -1.2, roll: -0.3),
            transform: (0..<16).map(Double.init)
        )

        let position = ARGuidedMeasurementPayload.positionEvent(
            request: request,
            action: "arGuidedPosition",
            timestampMs: 1_710_000_000_123,
            elapsedSeconds: 3.25,
            snapshot: snapshot,
            startAnchorId: "start-1",
            worldMapAvailable: true
        )
        XCTAssertEqual(position["platform"] as? String, "ios")
        XCTAssertEqual(position["action"] as? String, "arGuidedPosition")
        XCTAssertEqual(position["success"] as? Bool, true)
        XCTAssertEqual(position["source"] as? String, "arkit-guided")
        XCTAssertEqual(position["coordinateSystem"] as? String, "arkit-gravity-local")
        XCTAssertEqual(position["timestampMs"] as? Int, 1_710_000_000_123)
        XCTAssertEqual(position["arTimestampSeconds"] as? Double, 12.5)
        XCTAssertEqual(position["elapsedSeconds"] as? Double, 3.25)
        XCTAssertEqual(position["trackingState"] as? String, "limited")
        XCTAssertEqual(position["trackingReason"] as? String, "relocalizing")
        XCTAssertEqual(position["worldMappingStatus"] as? String, "extending")
        XCTAssertEqual(position["startAnchorId"] as? String, "start-1")

        let positionPayload = position["position"] as? [String: Any]
        XCTAssertEqual(positionPayload?["x"] as? Double, 1.0)
        XCTAssertEqual(positionPayload?["y"] as? Double, 2.0)
        XCTAssertEqual(positionPayload?["z"] as? Double, -3.0)
        XCTAssertEqual(positionPayload?["unit"] as? String, "meters")

        let orientation = position["orientation"] as? [String: Any]
        XCTAssertEqual(orientation?["pitch"] as? Double, 0.1)
        XCTAssertEqual(orientation?["yaw"] as? Double, 0.2)
        XCTAssertEqual(orientation?["headingYaw"] as? Double, -1.2)
        XCTAssertEqual(orientation?["roll"] as? Double, -0.3)
        XCTAssertEqual(orientation?["unit"] as? String, "radians")
        XCTAssertEqual(position["transform"] as? [Double], (0..<16).map(Double.init))

        let relocalizing = ARGuidedMeasurementPayload.relocalizationEvent(
            request: request,
            action: "arGuidedRelocalizing",
            state: "relocalizing",
            message: "Searching",
            worldMapAvailable: true,
            trackingState: "limited",
            trackingReason: "relocalizing",
            worldMappingStatus: "limited"
        )
        XCTAssertEqual(relocalizing["action"] as? String, "arGuidedRelocalizing")
        XCTAssertEqual(relocalizing["state"] as? String, "relocalizing")
        XCTAssertEqual(relocalizing["message"] as? String, "Searching")
        XCTAssertEqual(relocalizing["trackingReason"] as? String, "relocalizing")
    }

    func testAnchorEventsWrapPositionPayloads() {
        let request: [String: Any] = ["requestId": "req-anchor"]
        let startAnchor: [String: Any] = ["id": "start-1", "kind": "start"]
        let snapshot = ARGuidedMeasurementPayload.FrameSnapshot(
            arTimestampSeconds: 4,
            trackingState: "normal",
            trackingReason: "",
            worldMappingStatus: "mapped",
            position: .init(x: 0, y: 1, z: 2),
            orientation: .init(pitch: 0, yaw: 0.5, headingYaw: 0.5, roll: 0),
            transform: []
        )

        let confirmed = ARGuidedMeasurementPayload.startAnchorConfirmedEvent(
            request: request,
            timestampMs: 10,
            elapsedSeconds: 1.5,
            snapshot: snapshot,
            startAnchor: startAnchor,
            worldMapAvailable: false,
            confirmationSource: "button"
        )
        XCTAssertEqual(confirmed["action"] as? String, "arGuidedStartAnchorConfirmed")
        XCTAssertEqual(confirmed["anchorId"] as? String, "start-1")
        XCTAssertEqual(confirmed["startAnchorId"] as? String, "start-1")
        XCTAssertEqual((confirmed["startAnchor"] as? [String: Any])?["kind"] as? String, "start")
        XCTAssertEqual(confirmed["confirmationSource"] as? String, "button")
        XCTAssertNil(confirmed["trackingReason"])

        let captured = ARGuidedMeasurementPayload.anchorCapturedEvent(
            request: request,
            timestampMs: 11,
            elapsedSeconds: 1.75,
            snapshot: snapshot,
            startAnchor: startAnchor,
            worldMapAvailable: false,
            label: "AR Messpunkt"
        )
        XCTAssertEqual(captured["action"] as? String, "arGuidedAnchorCaptured")
        XCTAssertEqual(captured["label"] as? String, "AR Messpunkt")
        XCTAssertEqual(captured["startAnchorId"] as? String, "start-1")
    }
}
