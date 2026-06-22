//
//  ARPositionPayload.swift
//  swiftHTMLWebviewApp
//

import Foundation

enum ARPositionPayload {
    static let source = "arkit"
    static let coordinateSystem = "arkit-gravity-local"
    static let defaultIntervalMs = 500

    struct Vector3 {
        let x: Double
        let y: Double
        let z: Double
    }

    static func intervalMs(from request: [String: Any]) -> Int {
        guard let raw = doubleValue(request["intervalMs"]), raw.isFinite else {
            return defaultIntervalMs
        }
        return max(100, min(2000, Int(raw.rounded())))
    }

    static func startResponse(
        request: [String: Any],
        intervalMs: Int,
        trackingSupported: Bool,
        pendingPermission: Bool = false
    ) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: "arPositionStart")
        response["success"] = !pendingPermission
        response["source"] = source
        response["intervalMs"] = intervalMs
        response["coordinateSystem"] = coordinateSystem
        response["trackingSupported"] = trackingSupported
        if pendingPermission {
            response["pendingPermission"] = true
        }
        return response
    }

    static func stopResponse(request: [String: Any]) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: "arPositionStop")
        response["success"] = true
        return response
    }

    static func errorResponse(
        request: [String: Any],
        action: String,
        error: String,
        trackingSupported: Bool
    ) -> [String: Any] {
        var response = BridgeResponse.error(request: request, action: action, message: error)
        response["source"] = source
        response["trackingSupported"] = trackingSupported
        return response
    }

    static func interruptionEvent(request: [String: Any]) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: "arPosition")
        response["success"] = false
        response["source"] = source
        response["interrupted"] = true
        response["error"] = "AR session was interrupted."
        return response
    }

    static func positionEvent(
        request: [String: Any],
        timestampMs: Int,
        arTimestampSeconds: Double,
        elapsedSeconds: Double,
        trackingState: String,
        trackingReason: String,
        position: Vector3,
        orientation: Vector3,
        transform: [Double],
        trackingSupported: Bool = true
    ) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: "arPosition")
        response["success"] = true
        response["source"] = source
        response["coordinateSystem"] = coordinateSystem
        response["timestampMs"] = timestampMs
        response["arTimestampSeconds"] = arTimestampSeconds
        response["elapsedSeconds"] = elapsedSeconds
        response["trackingSupported"] = trackingSupported
        response["trackingState"] = trackingState
        if !trackingReason.isEmpty {
            response["trackingReason"] = trackingReason
        }
        response["position"] = [
            "x": position.x,
            "y": position.y,
            "z": position.z,
            "unit": "meters"
        ]
        response["orientation"] = [
            "pitch": orientation.x,
            "yaw": orientation.y,
            "roll": orientation.z,
            "unit": "radians"
        ]
        response["transform"] = transform
        return response
    }
}
