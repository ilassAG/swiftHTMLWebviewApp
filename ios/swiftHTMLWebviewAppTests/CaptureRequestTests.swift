//
//  CaptureRequestTests.swift
//  swiftHTMLWebviewAppTests
//

import UIKit
import XCTest
@testable import swiftHTMLWebviewApp

final class CaptureRequestTests: XCTestCase {
    func testDocumentRequestDefaultsToScanDocumentPngAndNoOCR() {
        let request = DocumentCaptureRequest(nil)

        XCTAssertEqual(request.action, "scanDocument")
        XCTAssertFalse(request.requiresOCR)
        XCTAssertEqual(request.outputType, "png")
        XCTAssertEqual(request.imageFormat, .png)
        XCTAssertEqual(request.responseFormat, "png")
    }

    func testDocumentRequestNormalizesJpegAliases() {
        let request = DocumentCaptureRequest([
            "action": "customDocumentAction",
            "ocr": true,
            "outputType": " JPG "
        ])

        XCTAssertEqual(request.action, "customDocumentAction")
        XCTAssertTrue(request.requiresOCR)
        XCTAssertEqual(request.imageFormat, .jpeg())
        XCTAssertEqual(request.responseFormat, "jpeg")
    }

    func testPhotoRequestParsesCameraAndBackgroundOptions() {
        let request = PhotoCaptureRequest([
            "camera": "front",
            "outputType": "png",
            "removeBackground": true,
            "cropTransparent": true,
            "background": "color",
            "backgroundColor": "#123"
        ])

        XCTAssertEqual(request.action, "takePhoto")
        XCTAssertEqual(request.cameraDevice, .front)
        XCTAssertTrue(request.shouldRemoveBackground)
        XCTAssertTrue(request.cropTransparent)
        XCTAssertEqual(request.backgroundStyle.responseMode, "color")
        XCTAssertEqual(request.backgroundStyle.responseColorHex, "#112233")
        XCTAssertEqual(request.imageFormat(backgroundRemoved: false), .png)
        XCTAssertEqual(request.responseFormat(backgroundRemoved: false), "png")
    }

    func testPhotoRequestForcesPngForTransparentBackgroundRemoval() {
        let request = PhotoCaptureRequest([
            "outputType": "jpeg",
            "removeBackground": true,
            "background": "transparent"
        ])

        XCTAssertEqual(request.cameraDevice, .rear)
        XCTAssertEqual(request.imageFormat(backgroundRemoved: true), .png)
        XCTAssertEqual(request.responseFormat(backgroundRemoved: true), "png")
        XCTAssertEqual(request.imageFormat(backgroundRemoved: false), .jpeg())
        XCTAssertEqual(request.responseFormat(backgroundRemoved: false), "jpeg")
    }

    func testPortraitRequestParsesLegacyAliasesAndStringBooleans() {
        let request = PortraitCaptureRequest([
            "action": "portraitCapture",
            "amountFaces": "1",
            "secondsDelay": "2.5",
            "withVariation": 6,
            "captureIntervalMs": "200",
            "camera": "back",
            "removeBackground": "yes",
            "mirror": "yes",
            "background": "transparent"
        ])

        XCTAssertEqual(request.action, "portraitCapture")
        XCTAssertEqual(request.requiredFaces, 1)
        XCTAssertEqual(request.countdownSeconds, 2.5)
        XCTAssertEqual(request.variationCount, 6)
        XCTAssertEqual(request.captureIntervalSeconds, 0.2)
        XCTAssertEqual(request.cameraPosition, .back)
        XCTAssertTrue(request.shouldRemoveBackground)
        XCTAssertTrue(request.mirrorOutput)
        XCTAssertTrue(request.faceCenteredCrop)
        XCTAssertEqual(request.responseFormat(backgroundRemoved: true), "png")
    }

    func testPortraitRequestMirrorOutputDefaultsToFalse() {
        let request = PortraitCaptureRequest([:])

        XCTAssertFalse(request.mirrorOutput)
    }

    func testBarcodeRequestDefaultsActionAndKeepsRequestedTypes() {
        let request = BarcodeCaptureRequest([
            "types": ["qr", "ean13"]
        ])

        XCTAssertEqual(request.action, "scanBarcode")
        XCTAssertEqual(request.types, ["qr", "ean13"])
    }
}
