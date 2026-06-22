//
//  BridgeScriptBuilderTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class BridgeScriptBuilderTests: XCTestCase {
    func testNativeResultScriptWrapsSerializablePayload() {
        let result = BridgeScriptBuilder.nativeResultScript(payload: [
            "action": "settingsGet",
            "success": true,
            "requestId": "req-1"
        ])

        XCTAssertEqual(result.kind, .payload)
        XCTAssertTrue(result.script.hasPrefix("window.handleNativeResult("))
        XCTAssertTrue(result.script.hasSuffix(");"))
        XCTAssertTrue(result.script.contains("\"action\":\"settingsGet\""))
        XCTAssertTrue(result.script.contains("\"requestId\":\"req-1\""))
    }

    func testNativeResultScriptUsesJSONEscapingForStringValues() {
        let result = BridgeScriptBuilder.nativeResultScript(payload: [
            "action": "echo",
            "value": "line 1\n\"quoted\""
        ])

        XCTAssertEqual(result.kind, .payload)
        XCTAssertTrue(result.script.contains("\\n"))
        XCTAssertTrue(result.script.contains("\\\"quoted\\\""))
    }

    func testNativeResultScriptFallsBackForInvalidJSONPayload() {
        let result = BridgeScriptBuilder.nativeResultScript(payload: [
            "action": "badPayload",
            "value": Double.nan
        ])

        XCTAssertEqual(result.kind, .fallback)
        XCTAssertTrue(result.script.contains("window.handleNativeResult("))
        XCTAssertTrue(result.script.contains("\"error\""))
        XCTAssertFalse(result.script.contains("badPayload"))
    }
}
