//
//  ScreenStreamPayloadTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class ScreenStreamPayloadTests: XCTestCase {
    func testStreamRequestNormalizesAliasesAndClampsValues() {
        let request = ScreenStreamPayload.streamRequest(from: [
            "url": " ws://example.invalid/screen ",
            "format": "JPG",
            "fps": 99,
            "quality": 2,
            "maxWidth": 99
        ])

        XCTAssertEqual(request.targetUrl, "ws://example.invalid/screen")
        XCTAssertEqual(request.source, "app")
        XCTAssertEqual(request.transport, "websocket")
        XCTAssertEqual(request.format, "jpeg")
        XCTAssertEqual(request.fps, 10)
        XCTAssertEqual(request.quality, 0.25)
        XCTAssertEqual(request.maxWidth, 240)
        XCTAssertTrue(request.hasTargetUrl)
        XCTAssertTrue(request.isJpeg)
    }

    func testNATSStreamRequestUsesSubjectsAndNoTargetURL() {
        let request = ScreenStreamPayload.streamRequest(from: [
            "transport": "nats",
            "subject": "swift.wrapper.APP.screen.frames",
            "metaSubject": "swift.wrapper.APP.screen.meta",
            "eventSubject": "swift.wrapper.APP.screen.events",
            "quality": 65
        ])

        XCTAssertEqual(request.transport, "nats")
        XCTAssertEqual(request.source, "app")
        XCTAssertTrue(request.isNats)
        XCTAssertFalse(request.hasTargetUrl)
        XCTAssertEqual(request.subject, "swift.wrapper.APP.screen.frames")
        XCTAssertEqual(request.metaSubject, "swift.wrapper.APP.screen.meta")
        XCTAssertEqual(request.eventSubject, "swift.wrapper.APP.screen.events")
        XCTAssertEqual(request.quality, 0.65)
    }

    func testStreamRequestKeepsUnsupportedFormatForErrorPath() {
        let request = ScreenStreamPayload.streamRequest(from: [
            "targetUrl": "ws://example.invalid/screen",
            "format": "png"
        ])

        XCTAssertEqual(request.format, "png")
        XCTAssertFalse(request.isJpeg)
    }

    func testStreamRequestPrefersTargetUrlAndRejectsNonFiniteQuality() {
        let request = ScreenStreamPayload.streamRequest(from: [
            "url": "ws://fallback.invalid/screen",
            "targetUrl": " ws://primary.invalid/screen ",
            "quality": Double.nan
        ])

        XCTAssertEqual(request.targetUrl, "ws://primary.invalid/screen")
        XCTAssertEqual(request.quality, 0.65)
    }

    func testStartAndStopAcksUseCommonBridgeShape() {
        let source: [String: Any] = ["requestId": "req-stream"]
        let streamRequest = ScreenStreamPayload.streamRequest(from: [
            "targetUrl": "ws://example.invalid/screen",
            "fps": 4,
            "quality": 70,
            "maxWidth": 800
        ])

        let start = ScreenStreamPayload.startAck(request: source, streamRequest: streamRequest)
        XCTAssertEqual(start["platform"] as? String, "ios")
        XCTAssertEqual(start["action"] as? String, "screenStreamStart")
        XCTAssertEqual(start["requestId"] as? String, "req-stream")
        XCTAssertEqual(start["success"] as? Bool, true)
        XCTAssertEqual(start["source"] as? String, "app")
        XCTAssertEqual(start["targetUrl"] as? String, "ws://example.invalid/screen")
        XCTAssertEqual(start["transport"] as? String, "websocket")
        XCTAssertEqual(start["format"] as? String, "jpeg")
        XCTAssertEqual(start["fps"] as? Int, 4)
        XCTAssertEqual(start["quality"] as? Double, 0.7)
        XCTAssertEqual(start["maxWidth"] as? Int, 800)

        let stop = ScreenStreamPayload.stopAck(request: source, framesSent: 12, bytesSent: 3456)
        XCTAssertEqual(stop["platform"] as? String, "ios")
        XCTAssertEqual(stop["action"] as? String, "screenStreamStop")
        XCTAssertEqual(stop["requestId"] as? String, "req-stream")
        XCTAssertEqual(stop["success"] as? Bool, true)
        XCTAssertEqual(stop["frames"] as? Int64, 12)
        XCTAssertEqual(stop["bytes"] as? Int64, 3456)
    }

    func testNATSStartAckIncludesSubjects() {
        let source: [String: Any] = ["requestId": "req-nats-stream"]
        let streamRequest = ScreenStreamPayload.streamRequest(from: [
            "transport": "nats",
            "subject": "swift.wrapper.APP.screen.frames",
            "metaSubject": "swift.wrapper.APP.screen.meta",
            "eventSubject": "swift.wrapper.APP.screen.events",
            "fps": 3
        ])

        let start = ScreenStreamPayload.startAck(request: source, streamRequest: streamRequest)

        XCTAssertEqual(start["transport"] as? String, "nats")
        XCTAssertNil(start["targetUrl"])
        XCTAssertEqual(start["subject"] as? String, "swift.wrapper.APP.screen.frames")
        XCTAssertEqual(start["metaSubject"] as? String, "swift.wrapper.APP.screen.meta")
        XCTAssertEqual(start["eventSubject"] as? String, "swift.wrapper.APP.screen.events")
        XCTAssertEqual(start["fps"] as? Int, 3)
    }

    func testMetaEventsAndStatsUseCatalogedEventShapes() {
        let request = ScreenStreamPayload.StreamRequest(
            source: "app",
            transport: "websocket",
            targetUrl: "ws://example.invalid/screen",
            subject: "",
            metaSubject: "",
            eventSubject: "",
            format: "jpeg",
            fps: 2,
            quality: 0.65,
            maxWidth: 720
        )
        let meta = ScreenStreamPayload.meta(streamRequest: request)
        XCTAssertEqual(meta["type"] as? String, "screenStreamMeta")
        XCTAssertEqual(meta["platform"] as? String, "ios")
        XCTAssertEqual(meta["source"] as? String, "app")
        XCTAssertEqual(meta["format"] as? String, "jpeg")
        XCTAssertEqual(meta["fps"] as? Int, 2)
        XCTAssertEqual(meta["quality"] as? Double, 0.65)
        XCTAssertEqual(meta["maxWidth"] as? Int, 720)

        let closed = ScreenStreamPayload.event(action: "screenStreamClosed", success: true, message: "finished")
        XCTAssertEqual(closed["platform"] as? String, "ios")
        XCTAssertEqual(closed["action"] as? String, "screenStreamClosed")
        XCTAssertEqual(closed["success"] as? Bool, true)
        XCTAssertEqual(closed["message"] as? String, "finished")

        let error = ScreenStreamPayload.event(action: "screenStreamError", success: false, message: "network failed")
        XCTAssertEqual(error["action"] as? String, "screenStreamError")
        XCTAssertEqual(error["success"] as? Bool, false)
        XCTAssertEqual(error["error"] as? String, "network failed")

        let stats = ScreenStreamPayload.stats(
            framesSent: 3,
            bytesSent: 4096,
            lastFrameBytes: 1024,
            startedAt: Date(timeIntervalSince1970: 1),
            now: Date(timeIntervalSince1970: 3.5)
        )
        XCTAssertEqual(stats["platform"] as? String, "ios")
        XCTAssertEqual(stats["action"] as? String, "screenStreamStats")
        XCTAssertEqual(stats["success"] as? Bool, true)
        XCTAssertEqual(stats["frames"] as? Int64, 3)
        XCTAssertEqual(stats["bytes"] as? Int64, 4096)
        XCTAssertEqual(stats["lastFrameBytes"] as? Int, 1024)
        XCTAssertEqual(stats["durationSeconds"] as! Double, 2.5, accuracy: 0.001)
    }

    func testErrorResponseKeepsRequestIdAndContractShape() {
        let response = ScreenStreamPayload.response(
            request: ["requestId": "req-stream-error"],
            action: "screenStreamStart",
            success: false,
            error: "targetUrl is required."
        )

        XCTAssertEqual(response["platform"] as? String, "ios")
        XCTAssertEqual(response["action"] as? String, "screenStreamStart")
        XCTAssertEqual(response["requestId"] as? String, "req-stream-error")
        XCTAssertEqual(response["success"] as? Bool, false)
        XCTAssertEqual(response["error"] as? String, "targetUrl is required.")
    }
}
