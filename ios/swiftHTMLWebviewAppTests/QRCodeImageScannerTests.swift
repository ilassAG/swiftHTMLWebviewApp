//
//  QRCodeImageScannerTests.swift
//  swiftHTMLWebviewAppTests
//

import CoreImage
import UIKit
import XCTest
@testable import swiftHTMLWebviewApp

final class QRCodeImageScannerTests: XCTestCase {
    func testScansQRCodeFromDataURL() throws {
        let payload = "nats-qr-payload"
        let imageData = try qrPNGData(payload)
        let dataURL = "data:image/png;base64,\(imageData.base64EncodedString())"

        let response = QRCodeImageScanner.response(request: [
            "requestId": "qr-1",
            "dataURL": dataURL
        ])

        XCTAssertEqual(response["platform"] as? String, "ios")
        XCTAssertEqual(response["action"] as? String, "qrScanImage")
        XCTAssertEqual(response["requestId"] as? String, "qr-1")
        XCTAssertNil(response["error"] as? String)
        XCTAssertEqual(response["success"] as? Bool, true)
        XCTAssertEqual(response["code"] as? String, payload)
        XCTAssertEqual(response["format"] as? String, "qr")
        XCTAssertEqual(response["count"] as? Int, 1)
    }

    func testRejectsMissingImagePayload() {
        let response = QRCodeImageScanner.response(request: ["requestId": "qr-missing"])

        XCTAssertEqual(response["action"] as? String, "qrScanImage")
        XCTAssertEqual(response["success"] as? Bool, false)
        XCTAssertEqual(response["error"] as? String, "imageBase64 or dataUrl is required.")
    }

    private func qrPNGData(_ payload: String) throws -> Data {
        let filter = CIFilter(name: "CIQRCodeGenerator")!
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        let qr = try XCTUnwrap(filter.outputImage)

        let colored = qr.applyingFilter("CIFalseColor", parameters: [
            "inputColor0": CIColor(color: .black),
            "inputColor1": CIColor(color: .white)
        ])
        let scaled = colored.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let quietZone: CGFloat = 96
        let translated = scaled.transformed(by: CGAffineTransform(translationX: quietZone, y: quietZone))
        let extent = translated.extent.insetBy(dx: -quietZone, dy: -quietZone)
        let background = CIImage(color: CIColor(color: .white)).cropped(to: extent)
        let output = translated.composited(over: background).cropped(to: extent)
        let context = CIContext()
        let cgImage = try XCTUnwrap(context.createCGImage(output, from: output.extent))
        let rawImage = UIImage(cgImage: cgImage)
        let renderer = UIGraphicsImageRenderer(size: rawImage.size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: rawImage.size))
            rawImage.draw(in: CGRect(origin: .zero, size: rawImage.size))
        }
        return try XCTUnwrap(image.pngData())
    }
}
