//
//  NATSSettingsTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class NATSSettingsTests: XCTestCase {
    func testProvisionPayloadKeepsURLsEmptyUntilProvisionedAndNormalizesClientName() throws {
        let settings = try NATSSettings.fromPayload([
            "enabled": true,
            "auth": ["method": "creds"]
        ])

        XCTAssertTrue(settings.enabled)
        XCTAssertEqual(settings.urls, [])
        XCTAssertEqual(settings.authMethod, .creds)
        XCTAssertEqual(settings.clientName(appUUID: "APP-123"), "swift-wrapper-APP-123")
        XCTAssertEqual(settings.devicePrefix(appUUID: "APP-123"), "swift.wrapper.APP-123")
        XCTAssertEqual(settings.commandSubject(appUUID: "APP-123"), "swift.wrapper.APP-123.commands.*")
        XCTAssertEqual(settings.responseSubject(appUUID: "APP-123"), "swift.wrapper.APP-123.events.responses")
        XCTAssertEqual(settings.statusSubject(appUUID: "APP-123"), "swift.wrapper.APP-123.status")
        XCTAssertEqual(settings.telemetrySubject(appUUID: "APP-123"), "swift.wrapper.APP-123.telemetry.status")
        XCTAssertTrue(settings.telemetryEnabled)
        XCTAssertEqual(settings.telemetryIntervalSeconds, 30)
    }

    func testRejectsInvalidURLSchemes() {
        XCTAssertThrowsError(try NATSSettings.fromPayload([
            "enabled": true,
            "urls": ["http://example.invalid:4222"],
            "auth": ["method": "creds"]
        ])) { error in
            XCTAssertEqual(error as? NATSSettingsError, .invalidURL("http://example.invalid:4222"))
        }
    }

    func testAuthMethodParsingCoversSupportedValues() {
        XCTAssertEqual(NATSAuthMethod.parse("none"), NATSAuthMethod.none)
        XCTAssertEqual(NATSAuthMethod.parse("token"), NATSAuthMethod.token)
        XCTAssertEqual(NATSAuthMethod.parse("userPassword"), NATSAuthMethod.userPassword)
        XCTAssertEqual(NATSAuthMethod.parse("nkey"), NATSAuthMethod.nkey)
        XCTAssertEqual(NATSAuthMethod.parse("creds"), NATSAuthMethod.creds)
        XCTAssertEqual(NATSAuthMethod.parse("tlsCertificate"), NATSAuthMethod.tlsCertificate)
        XCTAssertNil(NATSAuthMethod.parse("jwt"))
        XCTAssertEqual(NATSAuthMethod.supportedTransportMethods, ["none", "token", "nkey", "creds"])
        XCTAssertEqual(NATSAuthMethod.unsupportedTransportMethods, ["userPassword", "tlsCertificate"])
    }

    func testPersistedJSONDoesNotContainSecrets() throws {
        let settings = try NATSSettings.fromPayload([
            "enabled": true,
            "urls": ["tls://nats.example.invalid:4222"],
            "auth": [
                "method": "creds",
                "creds": "SECRET"
            ]
        ])

        let raw = settings.persistedJSONString()

        XCTAssertTrue(raw.contains("\"method\":\"creds\""))
        XCTAssertFalse(raw.contains("SECRET"))
        XCTAssertFalse(raw.contains("credentialRef"))
    }

    func testRedactedSnapshotContainsCredentialFlagOnly() {
        var settings = NATSSettings()
        settings.enabled = true
        settings.urls = ["tls://nats.example.invalid:4222"]

        let snapshot = settings.redactedSnapshot(
            appUUID: "APP-123",
            credentialSet: true,
            connected: false,
            lastError: "offline"
        )
        let auth = snapshot["auth"] as? [String: Any]

        XCTAssertEqual(snapshot["clientName"] as? String, "swift-wrapper-APP-123")
        XCTAssertEqual(auth?["method"] as? String, "creds")
        XCTAssertEqual(auth?["credentialSet"] as? Bool, true)
        XCTAssertEqual(auth?["supportedMethods"] as? [String], ["none", "token", "nkey", "creds"])
        XCTAssertNil(auth?["creds"])
        XCTAssertEqual(snapshot["lastError"] as? String, "offline")
        XCTAssertEqual((snapshot["subjects"] as? [String: Any])?["commandSubject"] as? String, "swift.wrapper.APP-123.commands.*")
        XCTAssertEqual((snapshot["subjects"] as? [String: Any])?["telemetrySubject"] as? String, "swift.wrapper.APP-123.telemetry.status")
        XCTAssertEqual((snapshot["telemetry"] as? [String: Any])?["intervalSeconds"] as? Int, 30)
    }
}
