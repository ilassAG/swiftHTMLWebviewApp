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
        XCTAssertTrue(html.contains("<div class=\"logo\" aria-label=\"W&lt;i&gt;\">"))
        XCTAssertTrue(html.contains("<svg viewBox=\"0 0 64 64\""))
        XCTAssertTrue(html.contains("<h1>Demo &lt;Verbindung&gt;</h1>"))
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
        XCTAssertTrue(html.contains("action: 'continuousScanStart'"))
        XCTAssertTrue(html.contains("purpose: 'configPairing'"))
        XCTAssertTrue(html.contains("source: 'recovery'"))
        XCTAssertTrue(html.contains("action: 'reload', source: 'recovery'"))
        XCTAssertTrue(html.contains("window.handleNativeResult"))
    }

    func testCandidateLabelUsesSingularAndPlural() {
        let singular = RecoveryPageBuilder.html(config: RecoveryPageBuilder.Config(failedCandidates: ["https://one.invalid"]))
        let plural = RecoveryPageBuilder.html(config: RecoveryPageBuilder.Config(failedCandidates: [
            "https://one.invalid",
            "https://two.invalid"
        ]))

        XCTAssertTrue(singular.contains("Geprüfte Adresse</p>"))
        XCTAssertTrue(plural.contains("Geprüfte Adressen</p>"))
    }
}
