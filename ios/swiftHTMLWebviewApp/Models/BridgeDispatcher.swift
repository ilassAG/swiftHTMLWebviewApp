//
//  BridgeDispatcher.swift
//  swiftHTMLWebviewApp
//

import Foundation

enum BridgeDispatcher {
    static func action(from request: [String: Any]) -> String? {
        guard let action = request["action"] as? String else {
            return nil
        }
        let trimmed = action.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func missingActionResponse(request: [String: Any], message: String) -> [String: Any] {
        BridgeResponse.error(request: request, action: "unknown", message: message)
    }

    static func unknownActionResponse(request: [String: Any], action: String, message: String) -> [String: Any] {
        BridgeResponse.error(request: request, action: action, message: message)
    }
}
