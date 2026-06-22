//
//  BarcodeResponseBuilderTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class BarcodeResponseBuilderTests: XCTestCase {
    func testBarcodeResponseUsesLegacyScannerFields() {
        let response = BarcodeResponseBuilder.response(
            action: "scanBarcode",
            code: "ABC-123",
            format: "qr"
        )

        XCTAssertEqual(response["action"] as? String, "scanBarcode")
        XCTAssertEqual(response["code"] as? String, "ABC-123")
        XCTAssertEqual(response["format"] as? String, "qr")
        XCTAssertNil(response["platform"])
        XCTAssertNil(response["success"])
    }

    func testRecoveryInvalidResponseUsesStructuredErrorShape() {
        let response = BarcodeResponseBuilder.recoveryInvalidResponse(
            action: "scanBarcode",
            message: "Der QR-Code enthaelt keine Server-URL."
        )

        XCTAssertEqual(response["platform"] as? String, "ios")
        XCTAssertEqual(response["action"] as? String, "scanBarcode")
        XCTAssertEqual(response["success"] as? Bool, false)
        XCTAssertEqual(response["error"] as? String, "Der QR-Code enthaelt keine Server-URL.")
    }

    func testConfigChangedResponseAcknowledgesScannerRequestBeforeReload() {
        let response = BarcodeResponseBuilder.configChangedResponse(
            request: [
                "action": "scanBarcode",
                "requestId": "req-config-1"
            ],
            settings: [
                "serverURL": "https://example.invalid/mobile/"
            ]
        )

        XCTAssertEqual(response["platform"] as? String, "ios")
        XCTAssertEqual(response["action"] as? String, "scanBarcode")
        XCTAssertEqual(response["requestId"] as? String, "req-config-1")
        XCTAssertEqual(response["success"] as? Bool, true)
        XCTAssertEqual(response["code"] as? String, "configChanged")
        XCTAssertEqual(response["format"] as? String, "JSONConfig")

        let settings = response["settings"] as? [String: Any]
        XCTAssertEqual(settings?["serverURL"] as? String, "https://example.invalid/mobile/")
    }
}
