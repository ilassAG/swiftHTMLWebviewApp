//
//  Models/AppError.swift
//  swiftHTMLWebviewDemo
//
//  Created by KI-Generiert am 05.10.2023.
//

import Foundation

// Eigene Fehler für eine bessere Fehlerbehandlung und Meldungen an JS
enum AppError: LocalizedError {
    case userCancelled
    case featureNotAvailable(String) // z.B. "DataScanner", "FrontCamera"
    case cameraPermissionDenied
    case internalError(String)
    case pdfCreationFailed
    case ocrFailed(Error?)
    case imageConversionFailed(String) // z.B. "Could not get JPEG data"
    case invalidRequest(String) // z.B. "Missing action parameter"
    case webViewCommunicationError(String)

    var errorDescription: String? {
        switch self {
        case .userCancelled:
            return "Aktion vom Benutzer abgebrochen."
        case .featureNotAvailable(let feature):
            return "\(feature) ist auf diesem Gerät oder unter den aktuellen Bedingungen nicht verfügbar."
        case .cameraPermissionDenied:
            return "Zugriff auf die Kamera wurde verweigert. Bitte in den Einstellungen erlauben."
        case .internalError(let message):
            return "Ein interner Fehler ist aufgetreten: \(message)"
        case .pdfCreationFailed:
            return "PDF-Dokument konnte nicht erstellt werden."
        case .ocrFailed(let underlyingError):
            let baseMessage = "Texterkennung (OCR) ist fehlgeschlagen."
            if let error = underlyingError {
                return "\(baseMessage) Fehler: \(error.localizedDescription)"
            }
            return baseMessage
        case .imageConversionFailed(let reason):
            return "Bild konnte nicht konvertiert werden: \(reason)"
        case .invalidRequest(let reason):
            return "Ungültige Anfrage von JavaScript: \(reason)"
        case .webViewCommunicationError(let reason):
             return "Fehler bei der Kommunikation mit WebView: \(reason)"
        }
    }
}