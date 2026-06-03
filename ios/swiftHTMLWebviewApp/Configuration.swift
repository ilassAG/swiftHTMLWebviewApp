//
//  Configuration.swift
//  swiftHTMLWebviewApp
//
//  This file defines global configuration constants for the application.
//  It includes settings like the JavaScript message handler name,
//  default JPEG compression quality, default barcode types for scanning,
//  the local HTML filename, and the server HTML path (retrieved from AppSettings).

import Foundation
import Vision
import CoreGraphics

enum Configuration {
    static let messageHandlerName = "swiftBridge"
    static let jpegCompressionQuality: CGFloat = 0.8
    static let defaultBarcodeTypes: [VNBarcodeSymbology] = [.qr, .ean13, .ean8]
    static let localHTMLFileName = "index"
    static let localHTMLPathValue = "local"
    static var serverHTMLPath: String {
        return AppSettings.shared.serverURL
    }

    static func isLocalHTMLPath(_ value: String?) -> Bool {
        let normalized = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty || normalized == localHTMLPathValue || normalized == "bundle" || normalized == "about:local"
    }

    static func localHTMLURL(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: localHTMLFileName, withExtension: "html", subdirectory: "HTML")
            ?? bundle.url(forResource: localHTMLFileName, withExtension: "html")
    }
}
