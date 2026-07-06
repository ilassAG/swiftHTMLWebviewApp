//
//  QRCodeImageScanner.swift
//  swiftHTMLWebviewApp
//
//  Decodes QR codes from image payloads supplied through native/NATS commands.
//

import Foundation
import CoreImage
import UIKit
import Vision

enum QRCodeImageScanner {
    static func response(request: [String: Any]) -> [String: Any] {
        do {
            let data = try imageData(from: request)
            guard let image = UIImage(data: data),
                  let cgImage = image.cgImage else {
                return BridgeResponse.error(request: request, action: "qrScanImage", message: "Image payload could not be decoded.")
            }

            var matches: [String] = []
            do {
                matches = try scan(cgImage: cgImage)
            } catch {
                matches = []
            }
            if matches.isEmpty {
                matches = scan(ciImage: CIImage(cgImage: cgImage))
            }
            var response = BridgeResponse.base(request: request, action: "qrScanImage")
            response["success"] = !matches.isEmpty
            response["format"] = "qr"
            response["count"] = matches.count
            response["codes"] = matches.map { ["code": $0, "format": "qr"] }
            if let first = matches.first {
                response["code"] = first
            } else {
                response["error"] = "No QR code found."
            }
            return response
        } catch {
            return BridgeResponse.error(request: request, action: "qrScanImage", message: error.localizedDescription)
        }
    }

    static func imageData(from request: [String: Any]) throws -> Data {
        let candidates = [
            stringValue(request["imageBase64"]),
            stringValue(request["imageData"]),
            stringValue(request["dataUrl"]),
            stringValue(request["dataURL"]),
            stringValue(request["image"])
        ]
        guard let raw = candidates.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw QRCodeImageScannerError("imageBase64 or dataUrl is required.")
        }
        let base64 = stripDataURLPrefix(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let data = Data(base64Encoded: base64, options: [.ignoreUnknownCharacters]) else {
            throw QRCodeImageScannerError("Image payload is not valid base64.")
        }
        return data
    }

    private static func stripDataURLPrefix(_ value: String) -> String {
        guard let comma = value.firstIndex(of: ","),
              value[..<comma].lowercased().hasPrefix("data:") else {
            return value
        }
        return String(value[value.index(after: comma)...])
    }

    private static func scan(cgImage: CGImage) throws -> [String] {
        var observations: [VNBarcodeObservation] = []
        let request = VNDetectBarcodesRequest { request, error in
            if error != nil {
                return
            }
            observations = request.results as? [VNBarcodeObservation] ?? []
        }
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        return observations.compactMap { $0.payloadStringValue }.filter { !$0.isEmpty }
    }

    private static func scan(ciImage: CIImage) -> [String] {
        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
        return detector?.features(in: ciImage)
            .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            .filter { !$0.isEmpty } ?? []
    }
}

private struct QRCodeImageScannerError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
