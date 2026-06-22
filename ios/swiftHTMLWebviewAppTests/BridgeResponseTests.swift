//
//  BridgeResponseTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class BridgeResponseTests: XCTestCase {
    func testBaseResponseIncludesPlatformActionRequestAndPaymentIds() {
        let response = BridgeResponse.base(
            request: [
                "requestId": "req-1",
                "paymentId": "pay-1"
            ],
            action: "tapToPayCollect"
        )

        XCTAssertEqual(response["platform"] as? String, "ios")
        XCTAssertEqual(response["action"] as? String, "tapToPayCollect")
        XCTAssertEqual(response["requestId"] as? String, "req-1")
        XCTAssertEqual(response["paymentId"] as? String, "pay-1")
    }

    func testErrorResponseUsesCommonShape() {
        let response = BridgeResponse.error(
            request: ["requestId": "req-2"],
            action: "settingsSet",
            message: "securityToken is required for settingsSet."
        )

        XCTAssertEqual(response["platform"] as? String, "ios")
        XCTAssertEqual(response["action"] as? String, "settingsSet")
        XCTAssertEqual(response["requestId"] as? String, "req-2")
        XCTAssertEqual(response["success"] as? Bool, false)
        XCTAssertEqual(response["error"] as? String, "securityToken is required for settingsSet.")
    }

    func testUnavailableResponseMarksAvailability() {
        let response = BridgeResponse.unavailable(
            request: ["requestId": "req-3"],
            action: "printerPrint",
            message: "Not available."
        )

        XCTAssertEqual(response["success"] as? Bool, false)
        XCTAssertEqual(response["available"] as? Bool, false)
        XCTAssertEqual(response["error"] as? String, "Not available.")
    }
}
