//
//  IdleTimerPayloadTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class IdleTimerPayloadTests: XCTestCase {
    func testStartRequestClampsTimeoutAndInterval() {
        let defaults = IdleTimerPayload.startRequest(from: [:])

        XCTAssertEqual(defaults.timeoutSeconds, 30)
        XCTAssertEqual(defaults.intervalSeconds, 1)

        let clamped = IdleTimerPayload.startRequest(from: [
            "timeoutSeconds": "0.2",
            "intervalSeconds": 0.1
        ])

        XCTAssertEqual(clamped.timeoutSeconds, 1)
        XCTAssertEqual(clamped.intervalSeconds, 0.25)

        let configured = IdleTimerPayload.startRequest(from: [
            "timeoutSeconds": "45.5",
            "intervalSeconds": "2.25"
        ])

        XCTAssertEqual(configured.timeoutSeconds, 45.5)
        XCTAssertEqual(configured.intervalSeconds, 2.25)
    }

    func testStartStopAndResetResponsesUseCommonEnvelope() {
        let request: [String: Any] = ["requestId": "idle-1"]
        let config = IdleTimerPayload.StartRequest(timeoutSeconds: 12, intervalSeconds: 0.5)
        let start = IdleTimerPayload.startResponse(request: request, config: config)

        XCTAssertEqual(start["platform"] as? String, "ios")
        XCTAssertEqual(start["action"] as? String, "idleTimerStart")
        XCTAssertEqual(start["requestId"] as? String, "idle-1")
        XCTAssertEqual(start["success"] as? Bool, true)
        XCTAssertEqual(start["timeoutSeconds"] as? Double, 12)
        XCTAssertEqual(start["intervalSeconds"] as? Double, 0.5)

        let stop = IdleTimerPayload.stopResponse(request: request)
        XCTAssertEqual(stop["action"] as? String, "idleTimerStop")
        XCTAssertEqual(stop["success"] as? Bool, true)
        XCTAssertEqual(stop["requestId"] as? String, "idle-1")

        let reset = IdleTimerPayload.resetResponse(request: request)
        XCTAssertEqual(reset["action"] as? String, "idleTimerReset")
        XCTAssertEqual(reset["success"] as? Bool, true)
        XCTAssertEqual(reset["requestId"] as? String, "idle-1")
    }

    func testTickAndTimeoutEventsUseCatalogedPayloadShape() {
        let tick = IdleTimerPayload.event(
            action: "idleTick",
            idleSeconds: 3.5,
            timeoutSeconds: 30
        )

        XCTAssertEqual(tick["platform"] as? String, "ios")
        XCTAssertEqual(tick["action"] as? String, "idleTick")
        XCTAssertEqual(tick["success"] as? Bool, true)
        XCTAssertEqual(tick["idleSeconds"] as? Double, 3.5)
        XCTAssertEqual(tick["timeoutSeconds"] as? Double, 30)

        let timeout = IdleTimerPayload.event(
            action: "idleTimeout",
            idleSeconds: 31,
            timeoutSeconds: 30
        )

        XCTAssertEqual(timeout["action"] as? String, "idleTimeout")
        XCTAssertEqual(timeout["success"] as? Bool, true)
        XCTAssertEqual(timeout["idleSeconds"] as? Double, 31)
        XCTAssertEqual(timeout["timeoutSeconds"] as? Double, 30)
    }
}
