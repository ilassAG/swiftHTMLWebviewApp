//
//  ContinuousScannerEventBuilderTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class ContinuousScannerEventBuilderTests: XCTestCase {
    func testDataEventUsesBarcodeDataAndSourceAction() {
        var config = ContinuousBarcodeScannerConfig()
        config.action = "dataScanStart"
        config.mode = "data"
        config.camera = "back"

        let event = ContinuousScannerEventBuilder.event(
            config: config,
            code: "ABC-123",
            format: "qr",
            date: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(event["action"] as? String, "barcodeData")
        XCTAssertEqual(event["sourceAction"] as? String, "dataScanStart")
        XCTAssertEqual(event["mode"] as? String, "data")
        XCTAssertEqual(event["camera"] as? String, "back")
        XCTAssertEqual(event["code"] as? String, "ABC-123")
        XCTAssertEqual(event["format"] as? String, "qr")
        XCTAssertEqual(event["timestamp"] as? String, "1970-01-01T00:00:00Z")
    }

    func testLoginEventUsesBarcodeLogin() {
        var config = ContinuousBarcodeScannerConfig()
        config.action = "loginScanStart"
        config.mode = "login"
        config.camera = "front"

        let event = ContinuousScannerEventBuilder.event(
            config: config,
            code: "LOGIN",
            format: "code128",
            date: Date(timeIntervalSince1970: 1)
        )

        XCTAssertEqual(event["action"] as? String, "barcodeLogin")
        XCTAssertEqual(event["sourceAction"] as? String, "loginScanStart")
        XCTAssertEqual(event["mode"] as? String, "login")
        XCTAssertEqual(event["camera"] as? String, "front")
        XCTAssertEqual(event["code"] as? String, "LOGIN")
        XCTAssertEqual(event["format"] as? String, "code128")
    }

    func testContinuousScanStartUsesExplicitModeForEventAction() {
        var loginConfig = ContinuousBarcodeScannerConfig()
        loginConfig.action = "continuousScanStart"
        loginConfig.mode = "login"

        var dataConfig = ContinuousBarcodeScannerConfig()
        dataConfig.action = "continuousScanStart"
        dataConfig.mode = "data"

        let loginEvent = ContinuousScannerEventBuilder.event(
            config: loginConfig,
            code: "LOGIN",
            format: "qr",
            date: Date(timeIntervalSince1970: 2)
        )
        let dataEvent = ContinuousScannerEventBuilder.event(
            config: dataConfig,
            code: "DATA",
            format: "qr",
            date: Date(timeIntervalSince1970: 2)
        )

        XCTAssertEqual(loginEvent["action"] as? String, "barcodeLogin")
        XCTAssertEqual(loginEvent["sourceAction"] as? String, "continuousScanStart")
        XCTAssertEqual(dataEvent["action"] as? String, "barcodeData")
        XCTAssertEqual(dataEvent["sourceAction"] as? String, "continuousScanStart")
    }
}
