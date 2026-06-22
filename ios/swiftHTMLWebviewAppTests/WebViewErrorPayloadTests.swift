//
//  WebViewErrorPayloadTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class WebViewErrorPayloadTests: XCTestCase {
    func testResponseUsesSharedBridgeErrorShapeForAppErrors() {
        let response = WebViewErrorPayload.response(
            action: "scanBarcode",
            error: AppError.featureNotAvailable("Barcode Scanner")
        )

        XCTAssertEqual(response["platform"] as? String, "ios")
        XCTAssertEqual(response["action"] as? String, "scanBarcode")
        XCTAssertEqual(response["success"] as? Bool, false)
        XCTAssertNotNil(response["error"] as? String)
    }

    func testResponseWrapsGenericErrorsAsInternalErrors() {
        let response = WebViewErrorPayload.response(
            action: nil,
            error: NSError(domain: "Tests", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
        )

        XCTAssertEqual(response["platform"] as? String, "ios")
        XCTAssertEqual(response["action"] as? String, "unknown")
        XCTAssertEqual(response["success"] as? Bool, false)
        XCTAssertTrue((response["error"] as? String)?.contains("boom") == true)
    }
}
