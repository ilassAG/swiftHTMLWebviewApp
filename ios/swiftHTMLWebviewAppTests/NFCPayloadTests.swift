//
//  NFCPayloadTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class NFCPayloadTests: XCTestCase {
    func testTagPayloadNormalizesIdentifierAndExtraFields() {
        let payload = NFCPayload.tagPayload(
            type: "miFare",
            identifier: Data([0x04, 0xA1, 0xB2, 0x03]),
            extra: [
                "mifareFamily": "ultralight",
                "ndefAvailable": true
            ]
        )

        XCTAssertEqual(payload["type"] as? String, "miFare")
        XCTAssertEqual(payload["identifierHex"] as? String, "04A1B203")
        XCTAssertEqual(payload["identifierBase64"] as? String, "BKGyAw==")
        XCTAssertEqual(payload["mifareFamily"] as? String, "ultralight")
        XCTAssertEqual(payload["ndefAvailable"] as? Bool, true)
    }

    func testNdefPayloadsUseStableCommonShape() {
        let unavailable = NFCPayload.ndefUnavailablePayload(status: "notSupported", capacityBytes: 128)
        XCTAssertEqual(unavailable["available"] as? Bool, false)
        XCTAssertEqual(unavailable["status"] as? String, "notSupported")
        XCTAssertEqual(unavailable["capacityBytes"] as? Int, 128)
        XCTAssertEqual((unavailable["messages"] as? [Any])?.count, 0)
        XCTAssertEqual((unavailable["records"] as? [Any])?.count, 0)

        let record = NFCPayload.RecordInput(
            index: 0,
            typeNameFormatRawValue: NFCPayload.TypeNameFormat.media.rawValue,
            type: Data("text/plain".utf8),
            identifier: Data([0x01]),
            payload: Data("Hallo".utf8)
        )
        let payload = NFCPayload.ndefPayload(status: "readWrite", capacityBytes: 512, messages: [[record]])

        XCTAssertEqual(payload["available"] as? Bool, true)
        XCTAssertEqual(payload["status"] as? String, "readWrite")
        XCTAssertEqual(payload["capacityBytes"] as? Int, 512)
        XCTAssertEqual(payload["messageCount"] as? Int, 1)
        XCTAssertEqual(payload["recordCount"] as? Int, 1)
        let messages = payload["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.first?["recordCount"] as? Int, 1)
    }

    func testTextRecordDecodesLanguageAndUtf8Text() {
        let record = NFCPayload.RecordInput(
            index: 2,
            typeNameFormatRawValue: NFCPayload.TypeNameFormat.nfcWellKnown.rawValue,
            type: Data("T".utf8),
            identifier: Data(),
            payload: Data([0x02]) + Data("deHallo".utf8)
        )
        let payload = NFCPayload.recordPayload(record)

        XCTAssertEqual(payload["index"] as? Int, 2)
        XCTAssertEqual(payload["typeNameFormat"] as? String, "nfcWellKnown")
        XCTAssertEqual(payload["type"] as? String, "T")
        XCTAssertEqual(payload["typeHex"] as? String, "54")
        XCTAssertEqual(payload["payloadBase64"] as? String, "AmRlSGFsbG8=")
        XCTAssertEqual(payload["payloadHex"] as? String, "02646548616C6C6F")
        XCTAssertEqual(payload["text"] as? String, "Hallo")
        XCTAssertEqual(payload["languageCode"] as? String, "de")
        XCTAssertEqual(payload["encoding"] as? String, "utf8")
    }

    func testUriAndMimeRecordsKeepOptionalFields() {
        let uriRecord = NFCPayload.RecordInput(
            index: 1,
            typeNameFormatRawValue: NFCPayload.TypeNameFormat.nfcWellKnown.rawValue,
            type: Data("U".utf8),
            identifier: Data([0x10, 0x20]),
            payload: Data([0x04]) + Data("example.invalid".utf8)
        )
        let uriPayload = NFCPayload.recordPayload(uriRecord)

        XCTAssertEqual(uriPayload["typeNameFormat"] as? String, "nfcWellKnown")
        XCTAssertEqual(uriPayload["identifierHex"] as? String, "1020")
        XCTAssertEqual(uriPayload["uri"] as? String, "https://example.invalid")

        let mimeRecord = NFCPayload.RecordInput(
            index: 3,
            typeNameFormatRawValue: NFCPayload.TypeNameFormat.media.rawValue,
            type: Data("text/plain".utf8),
            identifier: Data([0x01]),
            payload: Data("Plain text".utf8)
        )
        let mimePayload = NFCPayload.recordPayload(mimeRecord)
        XCTAssertEqual(mimePayload["typeNameFormat"] as? String, "media")
        XCTAssertEqual(mimePayload["mimeType"] as? String, "text/plain")
        XCTAssertEqual(mimePayload["text"] as? String, "Plain text")
    }

    func testInvalidTextAndUnknownTypeNameFormatAreStable() {
        let invalidText = NFCPayload.RecordInput(
            index: 4,
            typeNameFormatRawValue: NFCPayload.TypeNameFormat.nfcWellKnown.rawValue,
            type: Data("T".utf8),
            identifier: Data(),
            payload: Data([0x05, 0x64])
        )
        let invalidPayload = NFCPayload.recordPayload(invalidText)
        XCTAssertNil(invalidPayload["languageCode"])

        let unknown = NFCPayload.RecordInput(
            index: 5,
            typeNameFormatRawValue: 99,
            type: Data([0xFF]),
            identifier: Data(),
            payload: Data([0x00])
        )
        let unknownPayload = NFCPayload.recordPayload(unknown)
        XCTAssertEqual(unknownPayload["typeNameFormat"] as? String, "unknown")
        XCTAssertEqual(unknownPayload["type"] as? String, "FF")
    }

    func testErrorResponseUsesCommonBridgeEnvelope() {
        let response = NFCPayload.errorResponse(
            request: ["requestId": "req-nfc"],
            error: "NFC is disabled on this device."
        )

        XCTAssertEqual(response["platform"] as? String, "ios")
        XCTAssertEqual(response["action"] as? String, "nfcTagRead")
        XCTAssertEqual(response["requestId"] as? String, "req-nfc")
        XCTAssertEqual(response["success"] as? Bool, false)
        XCTAssertEqual(response["error"] as? String, "NFC is disabled on this device.")
    }
}
