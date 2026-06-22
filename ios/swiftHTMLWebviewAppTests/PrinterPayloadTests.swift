//
//  PrinterPayloadTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class PrinterPayloadTests: XCTestCase {
    func testSelectedPrinterKindUsesDirectNestedAndDefaultEpson() {
        XCTAssertEqual(
            PrinterPayload.selectedPrinterKind([
                "kind": " sunmi_internal ",
                "printer": ["kind": "epson_epos_xml"]
            ]),
            "sunmi_internal"
        )
        XCTAssertEqual(
            PrinterPayload.selectedPrinterKind([
                "printer": ["kind": " escpos_raw "]
            ]),
            "escpos_raw"
        )
        XCTAssertEqual(PrinterPayload.selectedPrinterKind([:]), "epson_epos_xml")
    }

    func testSelectedPrinterLabelUsesNestedLabelOrFallback() {
        XCTAssertEqual(
            PrinterPayload.selectedPrinterLabel(
                ["printer": ["label": " Front Demo Printer "]],
                fallback: "Fallback"
            ),
            "Front Demo Printer"
        )
        XCTAssertEqual(PrinterPayload.selectedPrinterLabel([:], fallback: "Fallback"), "Fallback")
    }

    func testEpsonRequestTrimsAndDefaultsFields() {
        let defaults = PrinterPayload.epsonRequest(from: [:])

        XCTAssertEqual(defaults.host, "")
        XCTAssertEqual(defaults.devid, "local_printer")
        XCTAssertEqual(defaults.timeoutMs, 20_000)
        XCTAssertEqual(defaults.title, "Hallo Welt")
        XCTAssertEqual(defaults.subtitle, "swiftHTMLWebviewApp")
        XCTAssertEqual(defaults.body, "iOS bridge test")

        let request = PrinterPayload.epsonRequest(from: [
            "host": " 192.168.1.44 ",
            "devid": " printer-1 ",
            "timeoutMs": "1500",
            "title": " Test ",
            "subtitle": " Sub ",
            "body": " Body "
        ])

        XCTAssertEqual(request.host, "192.168.1.44")
        XCTAssertEqual(request.devid, "printer-1")
        XCTAssertEqual(request.timeoutMs, 1500)
        XCTAssertEqual(request.title, "Test")
        XCTAssertEqual(request.subtitle, "Sub")
        XCTAssertEqual(request.body, "Body")
    }

    func testDiscoveryOptionsJSONFallsBackForInvalidJSONObject() throws {
        let json = PrinterPayload.discoveryOptionsJSON(from: [
            "hosts": ["192.168.1.44"],
            "timeoutMs": 1200
        ])
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(decoded["timeoutMs"] as? Int, 1200)
        XCTAssertEqual(decoded["hosts"] as? [String], ["192.168.1.44"])
        XCTAssertEqual(PrinterPayload.discoveryOptionsJSON(from: ["invalid": Date()]), "{}")
    }

    func testCoreResponseParsesJSONAndReportsInvalidJSON() {
        let parsed = PrinterPayload.coreResponse(from: #"{"success":true,"message":"ok"}"#)

        XCTAssertEqual(parsed["success"] as? Bool, true)
        XCTAssertEqual(parsed["message"] as? String, "ok")

        let invalid = PrinterPayload.coreResponse(from: "not-json")
        XCTAssertEqual(invalid["success"] as? Bool, false)
        XCTAssertEqual(invalid["error"] as? String, "Printercore returned invalid JSON.")
        XCTAssertEqual(invalid["responseText"] as? String, "not-json")
    }

    func testUnavailableResponsesUseCommonEnvelope() {
        let request: [String: Any] = ["requestId": "printer-1"]

        let unavailable = PrinterPayload.printercoreUnavailable(
            request: request,
            action: "printerEpsonHelloWorld"
        )
        XCTAssertEqual(unavailable["platform"] as? String, "ios")
        XCTAssertEqual(unavailable["action"] as? String, "printerEpsonHelloWorld")
        XCTAssertEqual(unavailable["requestId"] as? String, "printer-1")
        XCTAssertEqual(unavailable["success"] as? Bool, false)
        XCTAssertEqual(unavailable["available"] as? Bool, false)
        XCTAssertEqual(unavailable["printerKind"] as? String, "epson_epos_xml")

        let discovery = PrinterPayload.discoveryUnavailable(request: request)
        XCTAssertEqual(discovery["action"] as? String, "printerDiscover")
        XCTAssertEqual(discovery["success"] as? Bool, false)
        XCTAssertEqual(discovery["available"] as? Bool, false)
        XCTAssertEqual((discovery["printers"] as? [Any])?.count, 0)
    }

    func testUnsupportedKindResponseEchoesKindAndLabel() {
        let response = PrinterPayload.unsupportedKindResponse(
            request: [
                "requestId": "printer-2",
                "printer": ["label": "Bar"]
            ],
            kind: "sunmi_internal"
        )

        XCTAssertEqual(response["platform"] as? String, "ios")
        XCTAssertEqual(response["action"] as? String, "printerHelloWorld")
        XCTAssertEqual(response["requestId"] as? String, "printer-2")
        XCTAssertEqual(response["success"] as? Bool, false)
        XCTAssertEqual(response["available"] as? Bool, false)
        XCTAssertEqual(response["printerKind"] as? String, "sunmi_internal")
        XCTAssertEqual(response["printerLabel"] as? String, "Bar")
        XCTAssertEqual(response["error"] as? String, "Printer kind 'sunmi_internal' is not available on iOS in this demo build.")
    }

    func testEpsonJobResponseMergesCoreFieldsAndBackfillsError() {
        let job = PrinterPayload.EpsonHelloWorldRequest(
            host: "192.168.1.44",
            devid: "local_printer",
            timeoutMs: 1500,
            title: "Test",
            subtitle: "Sub",
            body: "Body"
        )
        let success = PrinterPayload.epsonJobResponse(
            request: ["requestId": "printer-3"],
            action: "printerHelloWorld",
            job: job,
            core: ["success": true, "message": "printed"],
            goCoreVersion: "1.2.3",
            printerLabel: "Epson"
        )

        XCTAssertEqual(success["action"] as? String, "printerHelloWorld")
        XCTAssertEqual(success["requestId"] as? String, "printer-3")
        XCTAssertEqual(success["host"] as? String, "192.168.1.44")
        XCTAssertEqual(success["devid"] as? String, "local_printer")
        XCTAssertEqual(success["printerKind"] as? String, "epson_epos_xml")
        XCTAssertEqual(success["printerLabel"] as? String, "Epson")
        XCTAssertEqual(success["goCoreVersion"] as? String, "1.2.3")
        XCTAssertEqual(success["success"] as? Bool, true)
        XCTAssertNil(success["error"])

        let failed = PrinterPayload.epsonJobResponse(
            request: [:],
            action: "printerHelloWorld",
            job: job,
            core: ["success": false, "message": "offline"],
            goCoreVersion: "1.2.3",
            printerLabel: "Epson"
        )

        XCTAssertEqual(failed["success"] as? Bool, false)
        XCTAssertEqual(failed["error"] as? String, "offline")
    }
}
