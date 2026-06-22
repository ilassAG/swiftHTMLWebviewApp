//
//  NativeCommandPayloadTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class NativeCommandPayloadTests: XCTestCase {
    func testReloadResponseUsesNativeCommandEnvelope() {
        let response = NativeCommandPayload.reloadResponse(request: [
            "action": "reload",
            "requestId": "req-reload-1"
        ])

        XCTAssertEqual(response["platform"] as? String, "ios")
        XCTAssertEqual(response["action"] as? String, "reload")
        XCTAssertEqual(response["requestId"] as? String, "req-reload-1")
        XCTAssertEqual(response["success"] as? Bool, true)
    }

    func testLaunchConfettiResponseUsesNativeCommandEnvelopeAndMetadata() {
        let response = NativeCommandPayload.launchConfettiResponse(
            request: [
                "action": "launchConfetti",
                "requestId": "req-confetti-1"
            ],
            burstCount: 3
        )

        XCTAssertEqual(response["platform"] as? String, "ios")
        XCTAssertEqual(response["action"] as? String, "launchConfetti")
        XCTAssertEqual(response["requestId"] as? String, "req-confetti-1")
        XCTAssertEqual(response["success"] as? Bool, true)
        XCTAssertEqual(response["launched"] as? Bool, true)
        XCTAssertEqual(response["burstCount"] as? Int, 3)
    }
}
