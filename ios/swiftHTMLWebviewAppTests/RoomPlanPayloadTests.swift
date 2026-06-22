//
//  RoomPlanPayloadTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class RoomPlanPayloadTests: XCTestCase {
    func testStartStopAndStateResponsesUseCommonShape() {
        let request: [String: Any] = ["requestId": "req-room"]

        let start = RoomPlanPayload.startResponse(request: request, supported: true)
        XCTAssertEqual(start["platform"] as? String, "ios")
        XCTAssertEqual(start["action"] as? String, "roomPlanScanStart")
        XCTAssertEqual(start["requestId"] as? String, "req-room")
        XCTAssertEqual(start["success"] as? Bool, true)
        XCTAssertEqual(start["supported"] as? Bool, true)
        XCTAssertEqual(start["source"] as? String, "roomplan")
        XCTAssertEqual(start["coordinateSystem"] as? String, "roomplan-local-meter")

        let stop = RoomPlanPayload.stopProcessingResponse(request: request)
        XCTAssertEqual(stop["action"] as? String, "roomPlanScanStop")
        XCTAssertEqual(stop["requestId"] as? String, "req-room")
        XCTAssertEqual(stop["success"] as? Bool, true)
        XCTAssertEqual(stop["state"] as? String, "processing")
        XCTAssertEqual(stop["message"] as? String, "RoomPlan scan stopped. Processing result.")

        let state = RoomPlanPayload.stateEvent(request: request, state: "running", message: "RoomPlan scan running.")
        XCTAssertEqual(state["action"] as? String, "roomPlanScanState")
        XCTAssertEqual(state["success"] as? Bool, true)
        XCTAssertEqual(state["source"] as? String, "roomplan")
        XCTAssertEqual(state["state"] as? String, "running")
        XCTAssertEqual(state["message"] as? String, "RoomPlan scan running.")
    }

    func testStateOmitsBlankMessageAndErrorUsesCommonShape() {
        let request: [String: Any] = ["requestId": "req-room-error"]

        let state = RoomPlanPayload.stateEvent(request: request, state: "processing")
        XCTAssertEqual(state["action"] as? String, "roomPlanScanState")
        XCTAssertEqual(state["state"] as? String, "processing")
        XCTAssertNil(state["message"])

        let error = RoomPlanPayload.errorResponse(
            request: request,
            action: "roomPlanScanError",
            error: "No active RoomPlan scan.",
            supported: false
        )
        XCTAssertEqual(error["platform"] as? String, "ios")
        XCTAssertEqual(error["action"] as? String, "roomPlanScanError")
        XCTAssertEqual(error["requestId"] as? String, "req-room-error")
        XCTAssertEqual(error["success"] as? Bool, false)
        XCTAssertEqual(error["supported"] as? Bool, false)
        XCTAssertEqual(error["source"] as? String, "roomplan")
        XCTAssertEqual(error["error"] as? String, "No active RoomPlan scan.")
    }

    func testResultEventUsesCatalogedPayloadShapeAndWorldMapFallback() {
        let request: [String: Any] = ["requestId": "req-room-result"]
        let normalizedPlan: [String: Any] = [
            "bounds": ["minX": 0.0, "minY": 0.0, "maxX": 4.0, "maxY": 3.0],
            "walls": [["id": "wall-1"]]
        ]
        let rawRoomPlan: [String: Any] = ["encoded": true]
        let counts = ["walls": 1, "doors": 2, "windows": 3, "openings": 4, "objects": 5]

        let result = RoomPlanPayload.resultEvent(
            request: request,
            normalizedPlan: normalizedPlan,
            previewSVG: "<svg/>",
            rawRoomPlan: rawRoomPlan,
            worldMapPayload: nil,
            counts: counts
        )

        XCTAssertEqual(result["platform"] as? String, "ios")
        XCTAssertEqual(result["action"] as? String, "roomPlanScanResult")
        XCTAssertEqual(result["requestId"] as? String, "req-room-result")
        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(result["supported"] as? Bool, true)
        XCTAssertEqual(result["source"] as? String, "roomplan")
        XCTAssertEqual(result["coordinateSystem"] as? String, "roomplan-local-meter")
        XCTAssertEqual(result["previewSvg"] as? String, "<svg/>")
        XCTAssertEqual(result["worldMapAvailable"] as? Bool, false)
        XCTAssertEqual(result["counts"] as? [String: Int], counts)
        XCTAssertEqual((result["raw"] as? [String: Any])?["encoded"] as? Bool, true)

        let plan = result["normalizedPlan"] as? [String: Any]
        XCTAssertEqual((plan?["walls"] as? [[String: Any]])?.count, 1)
    }

    func testResultEventMergesWorldMapPayloadAndExportOverridesActionAndRequestId() {
        let latest = RoomPlanPayload.resultEvent(
            request: ["requestId": "old-request"],
            normalizedPlan: [:],
            previewSVG: "<svg/>",
            rawRoomPlan: [:],
            worldMapPayload: [
                "worldMapAvailable": true,
                "worldMapFormat": "arkit-arworldmap-keyedarchive-v1",
                "worldMapByteCount": 123
            ],
            counts: ["walls": 0, "doors": 0, "windows": 0, "openings": 0, "objects": 0]
        )

        XCTAssertEqual(latest["worldMapAvailable"] as? Bool, true)
        XCTAssertEqual(latest["worldMapFormat"] as? String, "arkit-arworldmap-keyedarchive-v1")
        XCTAssertEqual(latest["worldMapByteCount"] as? Int, 123)

        let export = RoomPlanPayload.exportResponse(
            latestResult: latest,
            request: ["requestId": "new-request"]
        )
        XCTAssertEqual(export["action"] as? String, "roomPlanScanExport")
        XCTAssertEqual(export["requestId"] as? String, "new-request")
        XCTAssertEqual(export["source"] as? String, "roomplan")
    }
}
