//
//  RoomPlanPayload.swift
//  swiftHTMLWebviewApp
//

import Foundation

enum RoomPlanPayload {
    static let source = "roomplan"
    static let coordinateSystem = "roomplan-local-meter"

    static func startResponse(request: [String: Any], supported: Bool) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: "roomPlanScanStart")
        response["success"] = true
        response["supported"] = supported
        response["source"] = source
        response["coordinateSystem"] = coordinateSystem
        return response
    }

    static func stopProcessingResponse(request: [String: Any]) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: "roomPlanScanStop")
        response["success"] = true
        response["state"] = "processing"
        response["message"] = "RoomPlan scan stopped. Processing result."
        return response
    }

    static func stateEvent(request: [String: Any], state: String, message: String = "") -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: "roomPlanScanState")
        response["success"] = true
        response["source"] = source
        response["state"] = state
        if !message.isEmpty {
            response["message"] = message
        }
        return response
    }

    static func errorResponse(
        request: [String: Any],
        action: String,
        error: String,
        supported: Bool
    ) -> [String: Any] {
        var response = BridgeResponse.error(request: request, action: action, message: error)
        response["supported"] = supported
        response["source"] = source
        return response
    }

    static func resultEvent(
        request: [String: Any],
        normalizedPlan: [String: Any],
        previewSVG: String,
        rawRoomPlan: [String: Any],
        worldMapPayload: [String: Any]?,
        counts: [String: Int]
    ) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: "roomPlanScanResult")
        response["success"] = true
        response["supported"] = true
        response["source"] = source
        response["coordinateSystem"] = coordinateSystem
        response["normalizedPlan"] = normalizedPlan
        response["previewSvg"] = previewSVG
        response["raw"] = rawRoomPlan
        if let worldMapPayload {
            response.merge(worldMapPayload) { _, new in new }
        } else {
            response["worldMapAvailable"] = false
        }
        response["counts"] = counts
        return response
    }

    static func exportResponse(latestResult: [String: Any], request: [String: Any]) -> [String: Any] {
        var response = latestResult
        response["action"] = "roomPlanScanExport"
        if let requestId = request["requestId"] {
            response["requestId"] = requestId
        }
        return response
    }
}
