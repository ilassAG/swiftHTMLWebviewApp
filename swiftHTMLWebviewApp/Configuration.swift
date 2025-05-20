//
//  Configuration.swift
//  swiftHTMLWebviewApp
//
//  This file defines global configuration constants for the application.
//  It includes settings like the JavaScript message handler name,
//  default JPEG compression quality, default barcode types for scanning,
//  the local HTML filename, and the server HTML path (retrieved from AppSettings).

import Foundation
import Vision // <--- Hinzugefügt für VNBarcodeSymbology
import CoreGraphics // Für CGFloat

enum Configuration {
    // Name des JavaScript Message Handlers
    static let messageHandlerName = "swiftBridge"

    // Standard Bildqualität für JPEG
    static let jpegCompressionQuality: CGFloat = 0.8

    // Standard Barcode-Typen, falls keine von JS angegeben werden
    // Korrektur: Voller Typname VNBarcodeSymbology verwenden
    static let defaultBarcodeTypes: [VNBarcodeSymbology] = [.qr, .ean13, .ean8]

    // Dateiname der lokalen HTML-Datei (im HTML-Ordner)
    static let localHTMLFileName = "index"
    static var serverHTMLPath: String {
        return AppSettings.shared.serverURL
    }

    
}
