//
//  RecoveryConfigParserTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class RecoveryConfigParserTests: XCTestCase {
    func testParsesDirectServerURLFromJSONAndAddsLink() {
        let parser = RecoveryConfigParser()
        let rawCode = """
        {
          "serverURL": " https://example.invalid ",
          "linkId": " install-42 "
        }
        """

        XCTAssertEqual(
            parser.serverURL(from: rawCode),
            "https://example.invalid/mobile/?link=install-42"
        )
    }

    func testParsesBackendURLFallbackFromJSON() {
        let parser = RecoveryConfigParser()
        let rawCode = """
        {
          "backendUrl": "https://backend.invalid/api",
          "linkId": "abc"
        }
        """

        XCTAssertEqual(
            parser.serverURL(from: rawCode),
            "https://backend.invalid/api?link=abc"
        )
    }

    func testKeepsExistingLinkAndRemovesFragment() {
        let parser = RecoveryConfigParser()

        XCTAssertEqual(
            parser.serverURL(from: "https://example.invalid/mobile/?link=existing#ignored"),
            "https://example.invalid/mobile/?link=existing"
        )
    }

    func testRejectsBlankAndNonHTTPValues() {
        let parser = RecoveryConfigParser()

        XCTAssertNil(parser.serverURL(from: " "))
        XCTAssertNil(parser.serverURL(from: "ftp://example.invalid/mobile/"))
        XCTAssertNil(parser.serverURL(from: #"{"serverURL":"not a url"}"#))
    }

    func testRecoveryBarcodeHandlerAppliesNormalizedServerURL() {
        var appliedValues: [String: Any]?
        let handler = RecoveryBarcodeHandler(
            invalidMessage: "Invalid recovery QR",
            applyConfiguration: { values in
                appliedValues = values
                return [
                    "serverURL": values["serverURL"] as? String ?? ""
                ]
            }
        )

        let outcome = handler.handle(
            code: #"{"serverURL":"https://example.invalid","linkId":"recovery-1"}"#,
            action: "scanBarcode"
        )

        guard case let .applied(serverURL, snapshot) = outcome else {
            return XCTFail("Expected recovery barcode to apply server URL.")
        }
        XCTAssertEqual(serverURL, "https://example.invalid/mobile/?link=recovery-1")
        XCTAssertEqual(appliedValues?["serverURL"] as? String, "https://example.invalid/mobile/?link=recovery-1")
        XCTAssertEqual(snapshot["serverURL"] as? String, "https://example.invalid/mobile/?link=recovery-1")
    }

    func testRecoveryBarcodeHandlerReturnsInvalidResponseWithoutApplyingSettings() {
        var didApply = false
        let handler = RecoveryBarcodeHandler(
            invalidMessage: "Invalid recovery QR",
            applyConfiguration: { values in
                didApply = true
                return values
            }
        )

        let outcome = handler.handle(code: "not-a-url", action: "scanBarcode")

        guard case let .invalid(response) = outcome else {
            return XCTFail("Expected recovery barcode to be rejected.")
        }
        XCTAssertFalse(didApply)
        XCTAssertEqual(response["action"] as? String, "scanBarcode")
        XCTAssertEqual(response["success"] as? Bool, false)
        XCTAssertEqual(response["error"] as? String, "Invalid recovery QR")
    }

    func testRecoveryBarcodeRequestDetectionUsesSourceField() {
        XCTAssertTrue(RecoveryBarcodeHandler.isRecoveryRequest(["source": " recovery "]))
        XCTAssertFalse(RecoveryBarcodeHandler.isRecoveryRequest(["source": "scanner"]))
        XCTAssertFalse(RecoveryBarcodeHandler.isRecoveryRequest(nil))
    }

    func testConfigQRCodeParserReadsJSONSettingsStoreAndWifi() {
        let rawCode = """
        {
          "toolmode": "changeConfig",
          "securityToken": "token-1",
          "defaultServerUrl": "https://demo.example.invalid",
          "store": { "siteKey": "Demo Site" },
          "wifi": { "ssid": "Demo WLAN", "pw": "secret" }
        }
        """

        let config = ConfigQRCodeParser().parse(code: rawCode)
        let appConfig = config?.settings["appConfig"] as? [String: Any]

        XCTAssertEqual(config?.token, "token-1")
        XCTAssertEqual(config?.settings["defaultServerUrl"] as? String, "https://demo.example.invalid")
        XCTAssertEqual(appConfig?["siteKey"] as? String, "Demo Site")
        XCTAssertEqual(config?.wifiRequest?["ssid"] as? String, "Demo WLAN")
        XCTAssertEqual(config?.wifiRequest?["password"] as? String, "secret")
    }

    func testConfigQRCodeParserReadsQuerySettingsStoreAndWifi() {
        let rawCode = "swifthtml-config://set?token=token-1&serverURL=https%3A%2F%2Fdemo.example.invalid%2Fmobile%2F&terminal=A1&store%5BsiteKey%5D=Demo%20Site&wifi%5Bssid%5D=Demo%20WLAN&wifi%5Bpw%5D=secret"

        let config = ConfigQRCodeParser().parse(code: rawCode)
        let appConfig = config?.settings["appConfig"] as? [String: Any]

        XCTAssertEqual(config?.token, "token-1")
        XCTAssertEqual(config?.settings["serverURL"] as? String, "https://demo.example.invalid/mobile/")
        XCTAssertEqual(appConfig?["siteKey"] as? String, "Demo Site")
        XCTAssertEqual(appConfig?["terminal"] as? String, "A1")
        XCTAssertEqual(config?.wifiRequest?["ssid"] as? String, "Demo WLAN")
        XCTAssertEqual(config?.wifiRequest?["password"] as? String, "secret")
    }

    func testConfigQRCodeParserLeavesOrdinaryURLBarcodesAlone() {
        XCTAssertNil(ConfigQRCodeParser().parse(code: "https://example.invalid/item?id=123"))
    }
}
