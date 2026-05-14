//
//  Models/AppError.swift
//  swiftHTMLWebviewApp
//
//  This file defines a custom error enum `AppError` that conforms to `LocalizedError`.
//  It's used throughout the app to provide specific, user-friendly error messages
//  for various scenarios, such as user cancellations, feature unavailability,
//  permission denials, and internal issues. These errors are often sent to the WebView.
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
    case invalidConfiguration(String) // z.B. "Ungültiges Sicherheitstoken."

    var errorDescription: String? {
        switch self {
        case .userCancelled:
            return NSLocalizedString("error.appError.userCancelled", comment: "User cancelled action")
        case .featureNotAvailable(let feature):
            // Der 'feature'-String selbst wird bereits lokalisiert übergeben (z.B. NSLocalizedString("error.featureNotAvailable.camera", comment: ""))
            return String(format: NSLocalizedString("error.appError.featureNotAvailable", comment: "Feature not available message format"), feature)
        case .cameraPermissionDenied:
            return NSLocalizedString("error.appError.cameraPermissionDenied", comment: "Camera permission denied")
        case .internalError(let message):
            // Die 'message' wird oft einen bereits lokalisierten String enthalten oder einen dynamischen Wert
            return String(format: NSLocalizedString("error.appError.internalError", comment: "Internal error message format"), message)
        case .pdfCreationFailed:
            return NSLocalizedString("error.appError.pdfCreationFailed", comment: "PDF creation failed")
        case .ocrFailed(let underlyingError):
            if let error = underlyingError {
                return String(format: NSLocalizedString("error.appError.ocrFailed.withError", comment: "OCR failed with specific error"), error.localizedDescription)
            }
            return NSLocalizedString("error.appError.ocrFailed.base", comment: "OCR failed")
        case .imageConversionFailed(let reason):
            // Die 'reason' wird oft einen bereits lokalisierten String enthalten oder einen dynamischen Wert
            return String(format: NSLocalizedString("error.appError.imageConversionFailed", comment: "Image conversion failed message format"), reason)
        case .invalidRequest(let reason):
            // Die 'reason' wird oft einen bereits lokalisierten String enthalten oder einen dynamischen Wert
            return String(format: NSLocalizedString("error.appError.invalidRequest", comment: "Invalid request message format"), reason)
        case .webViewCommunicationError(let reason):
            // Die 'reason' wird oft einen bereits lokalisierten String enthalten oder einen dynamischen Wert
            return String(format: NSLocalizedString("error.appError.webViewCommunicationError", comment: "WebView communication error message format"), reason)
        case .invalidConfiguration(let reason):
            // Die 'reason' wird oft einen bereits lokalisierten String enthalten oder einen dynamischen Wert
            return String(format: NSLocalizedString("error.appError.invalidConfiguration", comment: "Invalid configuration message format"), reason)
        }
    }
}