//
//  ARGuidedMeasurementPayload.swift
//  swiftHTMLWebviewApp
//

import Foundation

enum ARGuidedMeasurementPayload {
    static let source = "arkit-guided"
    static let coordinateSystem = "arkit-gravity-local"
    static let defaultIntervalMs = 500

    struct Vector3 {
        let x: Double
        let y: Double
        let z: Double
    }

    struct Orientation {
        let pitch: Double
        let yaw: Double
        let headingYaw: Double
        let roll: Double
    }

    struct FrameSnapshot {
        let arTimestampSeconds: Double
        let trackingState: String
        let trackingReason: String
        let worldMappingStatus: String
        let position: Vector3
        let orientation: Orientation
        let transform: [Double]
    }

    static func intervalMs(from request: [String: Any]) -> Int {
        guard let raw = doubleValue(request["intervalMs"]), raw.isFinite else {
            return defaultIntervalMs
        }
        return max(100, min(2000, Int(raw.rounded())))
    }

    static func worldMapBase64(from request: [String: Any]) -> String {
        stringValue(request["worldMapBase64"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func worldMapURL(from request: [String: Any]) -> URL? {
        let raw = stringValue(request["worldMapUrl"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    static func worldMapAvailable(in request: [String: Any]) -> Bool {
        if boolValue(request["worldMapAvailable"]) == true {
            return true
        }
        return !worldMapBase64(from: request).isEmpty || worldMapURL(from: request) != nil
    }

    static func startAnchor(in request: [String: Any]) -> [String: Any]? {
        if let anchor = request["startAnchor"] as? [String: Any] {
            return anchor
        }
        if let anchors = request["anchors"] as? [[String: Any]] {
            return anchors.first { stringValue($0["kind"]) == "start" }
        }
        return nil
    }

    static func floorPlanPlan(in request: [String: Any]) -> [String: Any]? {
        if let plan = request["floorPlanPlanJson"] as? [String: Any] {
            return plan
        }
        if let plan = request["normalizedPlan"] as? [String: Any] {
            return plan
        }
        if let floorPlan = request["floorPlan"] as? [String: Any],
           let plan = floorPlan["planJson"] as? [String: Any] {
            return plan
        }
        return nil
    }

    static func mergedAnchors(current: [String: Any], update: [String: Any]) -> [String: Any] {
        var next = current
        if let startAnchor = update["startAnchor"] {
            next["startAnchor"] = startAnchor
        }
        if let anchors = update["anchors"] {
            next["anchors"] = anchors
        }
        if let bounds = update["bounds"] {
            next["bounds"] = bounds
        }
        return next
    }

    static func readyResponse(
        request: [String: Any],
        action: String,
        intervalMs: Int,
        startAnchor: [String: Any]?,
        worldMapAvailable: Bool,
        supported: Bool = true
    ) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: action)
        response["success"] = true
        response["supported"] = supported
        response["source"] = source
        response["coordinateSystem"] = coordinateSystem
        response["intervalMs"] = intervalMs
        response["startAnchor"] = startAnchor
        response["worldMapAvailable"] = worldMapAvailable
        return response
    }

    static func pendingPermissionResponse(
        request: [String: Any],
        intervalMs: Int,
        startAnchor: [String: Any]?,
        worldMapAvailable: Bool
    ) -> [String: Any] {
        var response = readyResponse(
            request: request,
            action: "arGuidedMeasurementStart",
            intervalMs: intervalMs,
            startAnchor: startAnchor,
            worldMapAvailable: worldMapAvailable
        )
        response["pendingPermission"] = true
        return response
    }

    static func acknowledgementResponse(request: [String: Any], action: String) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: action)
        response["success"] = true
        response["source"] = source
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

    static func relocalizationEvent(
        request: [String: Any],
        action: String,
        state: String,
        message: String,
        worldMapAvailable: Bool,
        trackingState: String? = nil,
        trackingReason: String? = nil,
        worldMappingStatus: String? = nil
    ) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: action)
        response["success"] = true
        response["source"] = source
        response["state"] = state
        response["message"] = message
        response["worldMapAvailable"] = worldMapAvailable
        if let trackingState, !trackingState.isEmpty {
            response["trackingState"] = trackingState
        }
        if let trackingReason, !trackingReason.isEmpty {
            response["trackingReason"] = trackingReason
        }
        if let worldMappingStatus, !worldMappingStatus.isEmpty {
            response["worldMappingStatus"] = worldMappingStatus
        }
        return response
    }

    static func positionEvent(
        request: [String: Any],
        action: String,
        timestampMs: Int,
        elapsedSeconds: Double,
        snapshot: FrameSnapshot,
        startAnchorId: String?,
        worldMapAvailable: Bool,
        supported: Bool = true
    ) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: action)
        response["success"] = true
        response["source"] = source
        response["coordinateSystem"] = coordinateSystem
        response["timestampMs"] = timestampMs
        response["arTimestampSeconds"] = snapshot.arTimestampSeconds
        response["elapsedSeconds"] = elapsedSeconds
        response["supported"] = supported
        response["worldMapAvailable"] = worldMapAvailable
        response["trackingState"] = snapshot.trackingState
        if !snapshot.trackingReason.isEmpty {
            response["trackingReason"] = snapshot.trackingReason
        }
        response["worldMappingStatus"] = snapshot.worldMappingStatus
        response["position"] = vectorPayload(snapshot.position, unit: "meters")
        response["orientation"] = [
            "pitch": snapshot.orientation.pitch,
            "yaw": snapshot.orientation.yaw,
            "headingYaw": snapshot.orientation.headingYaw,
            "roll": snapshot.orientation.roll,
            "unit": "radians"
        ]
        response["transform"] = snapshot.transform
        if let startAnchorId, !startAnchorId.isEmpty {
            response["startAnchorId"] = startAnchorId
        }
        return response
    }

    static func startAnchorConfirmedEvent(
        request: [String: Any],
        timestampMs: Int,
        elapsedSeconds: Double,
        snapshot: FrameSnapshot,
        startAnchor: [String: Any]?,
        worldMapAvailable: Bool,
        confirmationSource: String
    ) -> [String: Any] {
        let anchorId = stringValue(startAnchor?["id"])
        var response = positionEvent(
            request: request,
            action: "arGuidedStartAnchorConfirmed",
            timestampMs: timestampMs,
            elapsedSeconds: elapsedSeconds,
            snapshot: snapshot,
            startAnchorId: anchorId,
            worldMapAvailable: worldMapAvailable
        )
        response["startAnchor"] = startAnchor
        response["anchor"] = startAnchor
        response["anchorId"] = anchorId
        response["startAnchorId"] = anchorId
        response["confirmationSource"] = confirmationSource
        return response
    }

    static func anchorCapturedEvent(
        request: [String: Any],
        timestampMs: Int,
        elapsedSeconds: Double,
        snapshot: FrameSnapshot,
        startAnchor: [String: Any]?,
        worldMapAvailable: Bool,
        label: String
    ) -> [String: Any] {
        var response = positionEvent(
            request: request,
            action: "arGuidedAnchorCaptured",
            timestampMs: timestampMs,
            elapsedSeconds: elapsedSeconds,
            snapshot: snapshot,
            startAnchorId: stringValue(startAnchor?["id"]),
            worldMapAvailable: worldMapAvailable
        )
        response["label"] = label
        return response
    }

    private static func vectorPayload(_ vector: Vector3, unit: String) -> [String: Any] {
        [
            "x": vector.x,
            "y": vector.y,
            "z": vector.z,
            "unit": unit
        ]
    }
}
