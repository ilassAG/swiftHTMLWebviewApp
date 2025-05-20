//
//  Configuration.swift
//  swiftHTMLWebviewDemo
//
//  Created by KI-Generiert am 05.10.2023.
//  Korrektur: 02.04.2025
//  x

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
