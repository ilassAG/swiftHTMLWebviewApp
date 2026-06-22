//
//  CaptureResponseBuilder.swift
//  swiftHTMLWebviewApp
//
//  Builds document/photo bridge payloads after native capture data is ready.
//

import Foundation

enum DocumentCaptureResponseBuilder {
    static func imageResponse(
        action: String,
        pageCount: Int,
        text: String?,
        imageDataURLs: [String],
        format: String
    ) -> [String: Any] {
        var response = baseResponse(action: action, pageCount: pageCount, text: text)
        response["images"] = imageDataURLs
        response["format"] = format
        return response
    }

    static func pdfResponse(
        action: String,
        pageCount: Int,
        text: String?,
        pdfDataURL: String
    ) -> [String: Any] {
        var response = baseResponse(action: action, pageCount: pageCount, text: text)
        response["pdfData"] = pdfDataURL
        response["format"] = "pdf"
        return response
    }

    private static func baseResponse(action: String, pageCount: Int, text: String?) -> [String: Any] {
        var response: [String: Any] = [
            "action": action,
            "pages": pageCount
        ]
        if let text, !text.isEmpty {
            response["text"] = text
        }
        return response
    }
}

enum PhotoCaptureResponseBuilder {
    static func response(
        action: String,
        imageDataURL: String,
        format: String,
        backgroundRemoved: Bool,
        backgroundMode: String,
        cropped: Bool,
        backgroundColorHex: String?
    ) -> [String: Any] {
        var response: [String: Any] = [
            "action": action,
            "imageData": imageDataURL,
            "format": format
        ]

        if backgroundRemoved {
            response["backgroundRemoved"] = true
            response["background"] = backgroundMode
            response["cropped"] = cropped
            if let backgroundColorHex {
                response["backgroundColor"] = backgroundColorHex
            }
        }

        return response
    }
}

enum PortraitCaptureResponseBuilder {
    static func response(
        action: String,
        imageDataURL: String,
        format: String,
        selectedIndex: Int,
        variantsCaptured: Int,
        requiredFaces: Int,
        detectedFaces: Int,
        faceCentered: Bool,
        backgroundRemoved: Bool,
        backgroundMode: String,
        cropped: Bool,
        backgroundColorHex: String?
    ) -> [String: Any] {
        var response: [String: Any] = [
            "platform": "ios",
            "action": action,
            "success": true,
            "imageData": imageDataURL,
            "format": format,
            "selectedIndex": selectedIndex,
            "variantsCaptured": variantsCaptured,
            "requiredFaces": requiredFaces,
            "detectedFaces": detectedFaces,
            "faceCentered": faceCentered,
            "backgroundRemoved": backgroundRemoved,
            "background": backgroundMode,
            "cropped": cropped
        ]

        if let backgroundColorHex {
            response["backgroundColor"] = backgroundColorHex
        }

        return response
    }
}
