//
//  BridgeResponse.swift
//  swiftHTMLWebviewApp
//

import Foundation

enum BridgeResponse {
    static func base(request: [String: Any], action: String) -> [String: Any] {
        var response: [String: Any] = [
            "platform": "ios",
            "action": action
        ]
        if let requestId = request["requestId"] {
            response["requestId"] = requestId
        }
        if let paymentId = request["paymentId"] {
            response["paymentId"] = paymentId
        }
        return response
    }

    static func error(request: [String: Any], action: String, message: String) -> [String: Any] {
        var response = base(request: request, action: action)
        response["success"] = false
        response["error"] = message
        return response
    }

    static func unavailable(request: [String: Any], action: String, message: String) -> [String: Any] {
        var response = error(request: request, action: action, message: message)
        response["available"] = false
        return response
    }
}
