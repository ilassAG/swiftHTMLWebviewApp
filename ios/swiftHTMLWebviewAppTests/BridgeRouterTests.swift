//
//  BridgeRouterTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class BridgeRouterTests: XCTestCase {
    func testPostMessageRoutesKnownActions() {
        var results: [[String: Any]] = []
        var routedRequestId: String?
        let router = BridgeRouter.Builder(
            resultHandler: { results.append($0) },
            missingActionMessage: "Missing action.",
            unknownActionMessage: { "Unknown action: \($0)" }
        )
        .on("settingsGet") { request in
            routedRequestId = request["requestId"] as? String
            var response = BridgeResponse.base(request: request, action: "settingsGet")
            response["success"] = true
            results.append(response)
        }
        .build()

        router.postMessage(["action": " settingsGet ", "requestId": "req-1"])

        XCTAssertEqual(routedRequestId, "req-1")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0]["action"] as? String, "settingsGet")
        XCTAssertEqual(results[0]["requestId"] as? String, "req-1")
        XCTAssertEqual(results[0]["success"] as? Bool, true)
    }

    func testPostMessageReturnsStructuredMissingActionError() {
        var results: [[String: Any]] = []
        let router = BridgeRouter.Builder(
            resultHandler: { results.append($0) },
            missingActionMessage: "Missing action.",
            unknownActionMessage: { "Unknown action: \($0)" }
        ).build()

        router.postMessage(["requestId": "req-2"])

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0]["platform"] as? String, "ios")
        XCTAssertEqual(results[0]["action"] as? String, "unknown")
        XCTAssertEqual(results[0]["requestId"] as? String, "req-2")
        XCTAssertEqual(results[0]["success"] as? Bool, false)
        XCTAssertEqual(results[0]["error"] as? String, "Missing action.")
    }

    func testPostMessageReturnsStructuredUnknownActionErrorAndCallsHandler() {
        var results: [[String: Any]] = []
        var unknownHandled = false
        let router = BridgeRouter.Builder(
            resultHandler: { results.append($0) },
            missingActionMessage: "Missing action.",
            unknownActionMessage: { "Unknown action: \($0)" },
            unknownActionHandler: { unknownHandled = true }
        ).build()

        router.postMessage(["action": "madeUpAction", "requestId": "req-3"])

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0]["platform"] as? String, "ios")
        XCTAssertEqual(results[0]["action"] as? String, "madeUpAction")
        XCTAssertEqual(results[0]["requestId"] as? String, "req-3")
        XCTAssertEqual(results[0]["success"] as? Bool, false)
        XCTAssertEqual(results[0]["error"] as? String, "Unknown action: madeUpAction")
        XCTAssertTrue(unknownHandled)
    }

    func testBuilderRegistersGroupedActions() {
        let router = BridgeRouter.Builder(
            resultHandler: { _ in },
            missingActionMessage: "Missing action.",
            unknownActionMessage: { "Unknown action: \($0)" }
        )
        .onAll(["continuousScanStart", "dataScanStart", "loginScanStart"]) { _ in }
        .build()

        XCTAssertTrue(router.actions.contains("continuousScanStart"))
        XCTAssertTrue(router.actions.contains("dataScanStart"))
        XCTAssertTrue(router.actions.contains("loginScanStart"))
    }
}
