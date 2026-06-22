//
//  BarcodeResponseBuilder.swift
//  swiftHTMLWebviewApp
//
//  Builds one-shot barcode scanner bridge payloads.
//

import Foundation

enum BarcodeResponseBuilder {
    static func response(action: String, code: String, format: String) -> [String: Any] {
        [
            "action": action,
            "code": code,
            "format": format
        ]
    }

    static func configChangedResponse(request: [String: Any], settings: [String: Any]) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: "scanBarcode")
        response["success"] = true
        response["code"] = "configChanged"
        response["format"] = "JSONConfig"
        response["settings"] = settings
        return response
    }

    static func recoveryInvalidResponse(action: String, message: String) -> [String: Any] {
        [
            "platform": "ios",
            "action": action,
            "success": false,
            "error": message
        ]
    }
}
