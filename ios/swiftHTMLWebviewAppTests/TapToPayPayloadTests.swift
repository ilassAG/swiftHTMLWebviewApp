//
//  TapToPayPayloadTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class TapToPayPayloadTests: XCTestCase {
    func testAvailabilityUnavailableUsesContractEnvelope() {
        let response = TapToPayPayload.availability(
            request: ["requestId": "req-availability-1"],
            available: false,
            readerType: "apple_built_in",
            reason: "StripeTerminal SDK is not linked in this build."
        )

        XCTAssertEqual(response["platform"] as? String, "ios")
        XCTAssertEqual(response["action"] as? String, "tapToPayAvailability")
        XCTAssertEqual(response["requestId"] as? String, "req-availability-1")
        XCTAssertEqual(response["success"] as? Bool, true)
        XCTAssertEqual(response["available"] as? Bool, false)
        XCTAssertEqual(response["readerType"] as? String, "apple_built_in")
        XCTAssertEqual(response["reason"] as? String, "StripeTerminal SDK is not linked in this build.")
    }

    func testCollectErrorUsesContractEnvelopeAndPaymentId() {
        let response = TapToPayPayload.error(
            request: [
                "requestId": "req-collect-1",
                "paymentId": "payment-1"
            ],
            message: "StripeTerminal SDK is not linked in this build."
        )

        XCTAssertEqual(response["platform"] as? String, "ios")
        XCTAssertEqual(response["action"] as? String, "tapToPayCollect")
        XCTAssertEqual(response["requestId"] as? String, "req-collect-1")
        XCTAssertEqual(response["paymentId"] as? String, "payment-1")
        XCTAssertEqual(response["success"] as? Bool, false)
        XCTAssertEqual(response["error"] as? String, "StripeTerminal SDK is not linked in this build.")
    }
}
