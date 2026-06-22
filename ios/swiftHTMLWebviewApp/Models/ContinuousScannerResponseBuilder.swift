//
//  ContinuousScannerResponseBuilder.swift
//  swiftHTMLWebviewApp
//
//  Normalizes continuous scanner requests and bridge payloads.
//

import CoreGraphics
import Foundation

enum ContinuousScannerResponseBuilder {
    static func config(
        action: String,
        request: [String: Any],
        current: ContinuousBarcodeScannerConfig?
    ) -> ContinuousBarcodeScannerConfig {
        var config = current ?? ContinuousBarcodeScannerConfig()
        config.action = action
        config.purpose = scannerPurpose(request: request)
        config.mode = scannerMode(for: action, request: request)
        config.camera = scannerCamera(for: action, request: request)
        config.types = scannerTypes(request: request, purpose: config.purpose, fallback: config.types)
        config.repeatDelaySeconds = numericValue(request["repeatDelaySeconds"])
            ?? numericValue(request["repeatDelay"])
            ?? config.repeatDelaySeconds
        config.previewRect = previewRect(from: request["previewRect"] as? [String: Any]) ?? config.previewRect
        config.showFlipButton = boolValue(request["showFlipButton"])
            ?? boolValue(request["flipButton"])
            ?? boolValue(request["allowCameraFlip"])
            ?? (config.purpose == "configPairing")
        return config
    }

    static func startResponse(action: String, config: ContinuousBarcodeScannerConfig) -> [String: Any] {
        [
            "platform": "ios",
            "action": action,
            "success": true,
            "mode": config.mode,
            "purpose": config.purpose,
            "camera": config.camera,
            "types": config.types,
            "repeatDelaySeconds": config.repeatDelaySeconds,
            "previewRect": previewRectPayload(config.previewRect),
            "showFlipButton": config.showFlipButton
        ]
    }

    static func stopResponse(action: String, request: [String: Any]) -> [String: Any] {
        var response: [String: Any] = [
            "platform": "ios",
            "action": action,
            "success": true
        ]
        if let requestId = request["requestId"] {
            response["requestId"] = requestId
        }
        return response
    }

    static func previewUpdateResponse(action: String, previewRect: CGRect) -> [String: Any] {
        [
            "platform": "ios",
            "action": action,
            "success": true,
            "previewRect": previewRectPayload(previewRect)
        ]
    }

    static func errorResponse(action: String, message: String) -> [String: Any] {
        [
            "platform": "ios",
            "action": action,
            "success": false,
            "error": message
        ]
    }

    static func scannerMode(for action: String, request: [String: Any]) -> String {
        if let mode = request["mode"] as? String, !mode.isEmpty {
            return mode
        }
        if scannerPurpose(request: request) == "configPairing" {
            return "configPairing"
        }
        return action == "loginScanStart" ? "login" : "data"
    }

    static func scannerCamera(for action: String, request: [String: Any]) -> String {
        if let camera = request["camera"] as? String, camera == "front" || camera == "back" {
            return camera
        }
        if scannerPurpose(request: request) == "configPairing" {
            return "front"
        }
        return action == "loginScanStart" ? "front" : "back"
    }

    static func scannerPurpose(request: [String: Any]) -> String {
        let rawPurpose = stringValue(request["purpose"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if rawPurpose == "configPairing" {
            return rawPurpose
        }
        let rawSource = stringValue(request["source"]).trimmingCharacters(in: .whitespacesAndNewlines)
        return rawSource == "configPairing" ? rawSource : ""
    }

    static func scannerTypes(request: [String: Any], purpose: String, fallback: [String]) -> [String] {
        if let requested = request["types"] as? [String], !requested.isEmpty {
            return requested
        }
        return purpose == "configPairing" ? ["qr"] : fallback
    }

    static func previewRect(from value: [String: Any]?) -> CGRect? {
        guard let value,
              let left = normalizedRectValue(value["left"] ?? value["x"]),
              let top = normalizedRectValue(value["top"] ?? value["y"]),
              let width = normalizedRectValue(value["width"]),
              let height = normalizedRectValue(value["height"]) else {
            return nil
        }

        let safeWidth = min(max(width, 0.1), 1)
        let safeHeight = min(max(height, 0.1), 1)
        let safeLeft = min(max(left, 0), 1 - safeWidth)
        let safeTop = min(max(top, 0), 1 - safeHeight)
        return CGRect(x: safeLeft, y: safeTop, width: safeWidth, height: safeHeight)
    }

    static func previewRectPayload(_ rect: CGRect) -> [String: Double] {
        [
            "left": Double(rect.minX),
            "top": Double(rect.minY),
            "width": Double(rect.width),
            "height": Double(rect.height)
        ]
    }

    static func scannerFrame(for rect: CGRect, in size: CGSize) -> CGRect {
        let width = max(size.width * rect.width, 120)
        let height = max(size.height * rect.height, 120)
        let x = min(max(size.width * rect.minX, 0), max(size.width - width, 0))
        let y = min(max(size.height * rect.minY, 0), max(size.height - height, 0))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func normalizedRectValue(_ value: Any?) -> CGFloat? {
        guard let rawValue = numericValue(value) else { return nil }
        let normalized = rawValue > 1 ? rawValue / 100 : rawValue
        return CGFloat(normalized)
    }

    private static func numericValue(_ value: Any?) -> Double? {
        switch value {
        case let doubleValue as Double:
            return doubleValue
        case let intValue as Int:
            return Double(intValue)
        case let numberValue as NSNumber:
            return numberValue.doubleValue
        case let stringValue as String:
            return Double(stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        switch value {
        case let boolValue as Bool:
            return boolValue
        case let numberValue as NSNumber:
            return numberValue.boolValue
        case let stringValue as String:
            let normalized = stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["1", "true", "yes", "ja", "on"].contains(normalized) {
                return true
            }
            if ["0", "false", "no", "nein", "off"].contains(normalized) {
                return false
            }
            return nil
        default:
            return nil
        }
    }
}
