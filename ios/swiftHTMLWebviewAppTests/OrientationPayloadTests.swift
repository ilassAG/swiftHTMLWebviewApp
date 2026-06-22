//
//  OrientationPayloadTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class OrientationPayloadTests: XCTestCase {
    func testModePrefersModeOverOrientationAndNormalizesAliases() {
        XCTAssertEqual(OrientationPayload.mode(from: ["mode": " portrait "]), "portrait")
        XCTAssertEqual(OrientationPayload.mode(from: ["orientation": "landscape"]), "landscape")
        XCTAssertEqual(OrientationPayload.mode(from: ["mode": "", "orientation": "auto"]), "unlocked")
        XCTAssertEqual(OrientationPayload.mode(from: ["mode": "current"]), "locked")
        XCTAssertEqual(OrientationPayload.mode(from: ["mode": "locked"]), "locked")
        XCTAssertEqual(OrientationPayload.mode(from: ["mode": "sideways"]), "unlocked")
        XCTAssertEqual(OrientationPayload.mode(from: ["mode": "portrait", "orientation": "landscape"]), "portrait")
    }

    func testSetResponseUsesCommonEnvelopeAndEchoesMask() {
        let response = OrientationPayload.setResponse(
            request: [
                "requestId": "orientation-1",
                "paymentId": "pay-1"
            ],
            mode: "portrait",
            mask: "portrait"
        )

        XCTAssertEqual(response["platform"] as? String, "ios")
        XCTAssertEqual(response["action"] as? String, "screenOrientationSet")
        XCTAssertEqual(response["requestId"] as? String, "orientation-1")
        XCTAssertEqual(response["paymentId"] as? String, "pay-1")
        XCTAssertEqual(response["success"] as? Bool, true)
        XCTAssertEqual(response["mode"] as? String, "portrait")
        XCTAssertEqual(response["mask"] as? String, "portrait")
    }

    func testStatusResponseUsesCommonEnvelopeAndCurrentOrientation() {
        let response = OrientationPayload.statusResponse(
            request: ["requestId": "orientation-2"],
            mode: "unlocked",
            mask: "allButUpsideDown",
            currentOrientation: "landscapeRight"
        )

        XCTAssertEqual(response["platform"] as? String, "ios")
        XCTAssertEqual(response["action"] as? String, "screenOrientationGet")
        XCTAssertEqual(response["requestId"] as? String, "orientation-2")
        XCTAssertEqual(response["success"] as? Bool, true)
        XCTAssertEqual(response["mode"] as? String, "unlocked")
        XCTAssertEqual(response["mask"] as? String, "allButUpsideDown")
        XCTAssertEqual(response["currentOrientation"] as? String, "landscapeRight")
    }
}
