//
//  IdleTimerPayload.swift
//  swiftHTMLWebviewApp
//
//  Pure request and payload helpers for the native idle timer bridge.
//

import Foundation

enum IdleTimerPayload {
    struct StartRequest {
        let timeoutSeconds: TimeInterval
        let intervalSeconds: TimeInterval
    }

    static func startRequest(from request: [String: Any]) -> StartRequest {
        StartRequest(
            timeoutSeconds: max(1, doubleValue(request["timeoutSeconds"]) ?? 30),
            intervalSeconds: max(0.25, doubleValue(request["intervalSeconds"]) ?? 1)
        )
    }

    static func startResponse(request: [String: Any], config: StartRequest) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: "idleTimerStart")
        response["success"] = true
        response["timeoutSeconds"] = config.timeoutSeconds
        response["intervalSeconds"] = config.intervalSeconds
        return response
    }

    static func stopResponse(request: [String: Any]) -> [String: Any] {
        successResponse(request: request, action: "idleTimerStop")
    }

    static func resetResponse(request: [String: Any]) -> [String: Any] {
        successResponse(request: request, action: "idleTimerReset")
    }

    static func event(action: String, idleSeconds: TimeInterval, timeoutSeconds: TimeInterval) -> [String: Any] {
        [
            "platform": "ios",
            "action": action,
            "success": true,
            "idleSeconds": idleSeconds,
            "timeoutSeconds": timeoutSeconds
        ]
    }

    private static func successResponse(request: [String: Any], action: String) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: action)
        response["success"] = true
        return response
    }
}
