//
//  NativeCommandPayload.swift
//  swiftHTMLWebviewApp
//

import Foundation

enum NativeCommandPayload {
    static func reloadResponse(request: [String: Any]) -> [String: Any] {
        successResponse(request: request, action: "reload")
    }

    static func launchConfettiResponse(request: [String: Any], burstCount: Int) -> [String: Any] {
        var response = successResponse(request: request, action: "launchConfetti")
        response["launched"] = true
        response["burstCount"] = burstCount
        return response
    }

    static func successResponse(request: [String: Any], action: String) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: action)
        response["success"] = true
        return response
    }
}
