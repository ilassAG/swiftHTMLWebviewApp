//
//  ContinuousScannerEventBuilder.swift
//  swiftHTMLWebviewApp
//
//  Builds continuous scanner event payloads.
//

import Foundation

enum ContinuousScannerEventBuilder {
    private static let timestampFormatter = ISO8601DateFormatter()

    static func event(
        config: ContinuousBarcodeScannerConfig,
        code: String,
        format: String,
        date: Date
    ) -> [String: Any] {
        [
            "action": eventAction(for: config.mode),
            "sourceAction": config.action,
            "mode": config.mode,
            "camera": config.camera,
            "code": code,
            "format": format,
            "timestamp": timestampFormatter.string(from: date)
        ]
    }

    static func eventAction(for mode: String) -> String {
        mode == "login" ? "barcodeLogin" : "barcodeData"
    }
}
