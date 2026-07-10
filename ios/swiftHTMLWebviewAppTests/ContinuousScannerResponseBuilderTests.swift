//
//  ContinuousScannerResponseBuilderTests.swift
//  swiftHTMLWebviewAppTests
//

import CoreGraphics
import XCTest
@testable import swiftHTMLWebviewApp

final class ContinuousScannerResponseBuilderTests: XCTestCase {
    func testLoginScanDefaultsToLoginModeAndFrontCamera() {
        let config = ContinuousScannerResponseBuilder.config(
            action: "loginScanStart",
            request: ["action": "loginScanStart"],
            current: nil
        )

        XCTAssertEqual(config.action, "loginScanStart")
        XCTAssertEqual(config.mode, "login")
        XCTAssertEqual(config.camera, "front")
        XCTAssertEqual(config.types, ["qr", "ean13", "ean8", "code128", "datamatrix"])
        XCTAssertTrue(config.showCloseButton)
    }

    func testConfigPairingDefaultsToQRFrontCameraAndFlipButton() {
        let config = ContinuousScannerResponseBuilder.config(
            action: "continuousScanStart",
            request: ["action": "continuousScanStart", "purpose": "configPairing"],
            current: nil
        )

        XCTAssertEqual(config.mode, "configPairing")
        XCTAssertEqual(config.purpose, "configPairing")
        XCTAssertEqual(config.camera, "front")
        XCTAssertEqual(config.types, ["qr"])
        XCTAssertTrue(config.showFlipButton)
    }

    func testRequestOverridesTypesRepeatDelayAndPreviewRect() {
        let config = ContinuousScannerResponseBuilder.config(
            action: "dataScanStart",
            request: [
                "action": "dataScanStart",
                "camera": "front",
                "mode": "inventory",
                "types": ["qr", "code128"],
                "repeatDelay": "2.25",
                "showCloseButton": false,
                "previewRect": ["x": 80, "y": -10, "width": 35, "height": 200]
            ],
            current: nil
        )

        XCTAssertEqual(config.mode, "inventory")
        XCTAssertEqual(config.camera, "front")
        XCTAssertEqual(config.types, ["qr", "code128"])
        XCTAssertEqual(config.repeatDelaySeconds, 2.25)
        XCTAssertFalse(config.showCloseButton)
        XCTAssertEqual(config.previewRect.minX, 0.65, accuracy: 0.0001)
        XCTAssertEqual(config.previewRect.minY, 0, accuracy: 0.0001)
        XCTAssertEqual(config.previewRect.width, 0.35, accuracy: 0.0001)
        XCTAssertEqual(config.previewRect.height, 1, accuracy: 0.0001)
    }

    func testStartResponseUsesNormalizedConfig() {
        let config = ContinuousScannerResponseBuilder.config(
            action: "continuousScanStart",
            request: ["repeatDelaySeconds": 1.75],
            current: nil
        )
        let response = ContinuousScannerResponseBuilder.startResponse(
            action: "continuousScanStart",
            config: config
        )

        XCTAssertEqual(response["platform"] as? String, "ios")
        XCTAssertEqual(response["action"] as? String, "continuousScanStart")
        XCTAssertEqual(response["success"] as? Bool, true)
        XCTAssertEqual(response["repeatDelaySeconds"] as? TimeInterval, 1.75)
        XCTAssertEqual(response["purpose"] as? String, "")
        XCTAssertEqual(response["camera"] as? String, "back")
        XCTAssertEqual(response["showCloseButton"] as? Bool, true)
        XCTAssertEqual(response["showFlipButton"] as? Bool, false)
        XCTAssertNotNil(response["previewRect"] as? [String: Double])
    }

    func testStopResponseEchoesRequestId() {
        let response = ContinuousScannerResponseBuilder.stopResponse(
            action: "dataScanEnd",
            request: ["requestId": "req-stop"]
        )

        XCTAssertEqual(response["action"] as? String, "dataScanEnd")
        XCTAssertEqual(response["requestId"] as? String, "req-stop")
        XCTAssertEqual(response["success"] as? Bool, true)
    }

    func testScannerFrameKeepsMinimumSizeInsideViewport() {
        let frame = ContinuousScannerResponseBuilder.scannerFrame(
            for: CGRect(x: 0.95, y: 0.95, width: 0.1, height: 0.1),
            in: CGSize(width: 320, height: 240)
        )

        XCTAssertEqual(frame.width, 120)
        XCTAssertEqual(frame.height, 120)
        XCTAssertEqual(frame.maxX, 320)
        XCTAssertEqual(frame.maxY, 240)
    }
}
