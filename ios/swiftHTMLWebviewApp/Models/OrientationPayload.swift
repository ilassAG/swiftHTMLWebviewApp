//
//  OrientationPayload.swift
//  swiftHTMLWebviewApp
//
//  Pure payload helpers for screen orientation bridge actions.
//

import Foundation

enum OrientationPayload {
    static func mode(from request: [String: Any]) -> String {
        let rawMode = string(request["mode"])
        let rawOrientation = string(request["orientation"])
        let requested = rawMode.isEmpty ? rawOrientation : rawMode

        switch requested.lowercased() {
        case "portrait":
            return "portrait"
        case "landscape":
            return "landscape"
        case "locked", "current":
            return "locked"
        case "unlocked", "auto":
            return "unlocked"
        default:
            return "unlocked"
        }
    }

    static func mode(from requestedMode: String) -> String {
        mode(from: ["mode": requestedMode])
    }

    static func setResponse(request: [String: Any], mode: String, mask: String) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: "screenOrientationSet")
        response["success"] = true
        response["mode"] = mode
        response["mask"] = mask
        return response
    }

    static func statusResponse(
        request: [String: Any],
        mode: String,
        mask: String,
        currentOrientation: String
    ) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: "screenOrientationGet")
        response["success"] = true
        response["mode"] = mode
        response["mask"] = mask
        response["currentOrientation"] = currentOrientation
        return response
    }

    static func string(_ value: Any?) -> String {
        guard let raw = value as? String else {
            return ""
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
