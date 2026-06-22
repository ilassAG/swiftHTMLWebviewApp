//
//  RecoveryPageBuilderTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class RecoveryPageBuilderTests: XCTestCase {
    func testHTMLUsesVariantBrandingAndEscapesText() {
        let html = RecoveryPageBuilder.html(config: RecoveryPageBuilder.Config(
            failedCandidates: [
                "https://primary.invalid/?a=1&b=2",
                "https://backup.invalid/<bad>"
            ],
            reason: "Timeout <wifi> & retry",
            shortMark: "W<i>",
            title: "Demo <Verbindung>",
            body: "Server & WLAN pruefen",
            qrDetectedMessage: "QR <ok> & weiter"
        ))

        XCTAssertTrue(html.contains("<title>Demo &lt;Verbindung&gt; Verbindung</title>"))
        XCTAssertTrue(html.contains("<div class=\"logo\">W&lt;i&gt;</div>"))
        XCTAssertTrue(html.contains("Server &amp; WLAN pruefen"))
        XCTAssertTrue(html.contains("Timeout &lt;wifi&gt; &amp; retry"))
        XCTAssertTrue(html.contains("https://primary.invalid/?a=1&amp;b=2"))
        XCTAssertTrue(html.contains("https://backup.invalid/&lt;bad&gt;"))
        XCTAssertTrue(html.contains("QR \\u003Cok\\u003E \\u0026 weiter"))
        XCTAssertFalse(html.contains("Timeout <wifi>"))
    }

    func testHTMLKeepsRecoveryBridgeActions() {
        let html = RecoveryPageBuilder.html(config: RecoveryPageBuilder.Config())

        XCTAssertTrue(html.contains("window.webkit?.messageHandlers?.swiftBridge"))
        XCTAssertTrue(html.contains("action: 'scanBarcode', source: 'recovery', types: ['qr']"))
        XCTAssertTrue(html.contains("action: 'reload', source: 'recovery'"))
        XCTAssertTrue(html.contains("window.handleNativeResult"))
    }

    func testCandidateLabelUsesSingularAndPlural() {
        let singular = RecoveryPageBuilder.html(config: RecoveryPageBuilder.Config(failedCandidates: ["https://one.invalid"]))
        let plural = RecoveryPageBuilder.html(config: RecoveryPageBuilder.Config(failedCandidates: [
            "https://one.invalid",
            "https://two.invalid"
        ]))

        XCTAssertTrue(singular.contains("Gepruefte Adresse</p>"))
        XCTAssertTrue(plural.contains("Gepruefte Adressen</p>"))
    }
}
