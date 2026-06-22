//
//  BridgeDispatcherTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class BridgeDispatcherTests: XCTestCase {
    func testActionTrimsValidStringActions() {
        XCTAssertEqual(BridgeDispatcher.action(from: ["action": " settingsGet "]), "settingsGet")
    }

    func testActionRejectsMissingBlankAndNonStringActions() {
        XCTAssertNil(BridgeDispatcher.action(from: [:]))
        XCTAssertNil(BridgeDispatcher.action(from: ["action": "  "]))
        XCTAssertNil(BridgeDispatcher.action(from: ["action": 42]))
    }

    func testMissingActionResponseUsesStructuredErrorShape() {
        let response = BridgeDispatcher.missingActionResponse(
            request: ["requestId": "req-1"],
            message: "Missing action."
        )

        XCTAssertEqual(response["platform"] as? String, "ios")
        XCTAssertEqual(response["action"] as? String, "unknown")
        XCTAssertEqual(response["requestId"] as? String, "req-1")
        XCTAssertEqual(response["success"] as? Bool, false)
        XCTAssertEqual(response["error"] as? String, "Missing action.")
    }

    func testUnknownActionResponseEchoesUnknownAction() {
        let response = BridgeDispatcher.unknownActionResponse(
            request: ["requestId": "req-2"],
            action: "madeUpAction",
            message: "Unknown action."
        )

        XCTAssertEqual(response["action"] as? String, "madeUpAction")
        XCTAssertEqual(response["requestId"] as? String, "req-2")
        XCTAssertEqual(response["success"] as? Bool, false)
        XCTAssertEqual(response["error"] as? String, "Unknown action.")
    }
}
