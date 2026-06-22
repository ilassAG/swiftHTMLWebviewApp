//
//  AppSettingsTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class AppSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AppSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testRegisterDefaultsUsesVariantDefaultsAndGeneratesDeviceUUID() {
        let settings = AppSettings(userDefaults: defaults, variant: .demo)

        settings.registerDefaults()

        XCTAssertEqual(settings.serverURL, AppVariant.demo.defaults.serverURL)
        XCTAssertEqual(settings.securityToken, AppVariant.demo.defaults.securityToken)
        XCTAssertEqual(settings.highAvailabilityTimeoutSeconds, AppVariant.demo.defaults.highAvailabilityTimeoutSeconds)
        XCTAssertEqual(settings.beaconUUIDString, AppVariant.demo.defaults.beaconUUID)
        XCTAssertNotNil(UUID(uuidString: settings.deviceUUIDString))
    }

    func testResetMethodsRestoreVariantDefaults() {
        let settings = AppSettings(userDefaults: defaults, variant: .demo)
        settings.registerDefaults()

        settings.serverURL = "https://example.invalid/mobile/"
        settings.securityToken = "rotated-token"

        settings.resetToDefaultURL()
        settings.resetToDefaultSecurityToken()

        XCTAssertEqual(settings.serverURL, AppVariant.demo.defaults.serverURL)
        XCTAssertEqual(settings.securityToken, AppVariant.demo.defaults.securityToken)
    }

    func testServerURLCandidatesDeduplicatePrimaryAndFailoverURLs() {
        let settings = AppSettings(userDefaults: defaults, variant: .demo)
        settings.registerDefaults()
        settings.serverURL = "https://example.invalid/mobile/"
        settings.highAvailabilityEnabled = true
        settings.highAvailabilityURL2 = "https://example.invalid/mobile"
        settings.highAvailabilityURL3 = " local "
        settings.highAvailabilityURL4 = "about:local"

        XCTAssertEqual(
            settings.serverURLCandidates(),
            [
                "https://example.invalid/mobile/",
                "local"
            ]
        )
    }

    func testConfigurationSnapshotDoesNotLeakTokenByDefault() {
        let settings = AppSettings(userDefaults: defaults, variant: .demo)
        settings.registerDefaults()
        settings.securityToken = "secret-token"

        let publicSnapshot = settings.configurationSnapshot()
        let sensitiveSnapshot = settings.configurationSnapshot(includeSensitive: true)

        XCTAssertNil(publicSnapshot["securityToken"])
        XCTAssertEqual(publicSnapshot["securityTokenSet"] as? Bool, true)
        XCTAssertEqual(sensitiveSnapshot["securityToken"] as? String, "secret-token")
    }

    func testAppConfigPersistsAndMergesAssociativeValues() {
        let settings = AppSettings(userDefaults: defaults, variant: .demo)
        settings.registerDefaults()

        settings.applyConfiguration([
            "appConfig": [
                "siteKey": "Demo Site",
                "terminalId": "A1"
            ]
        ])
        let snapshot = settings.applyConfiguration([
            "store": [
                "terminalId": "A2",
                "mode": "counter"
            ]
        ])

        let appConfig = snapshot["appConfig"] as? [String: Any]
        XCTAssertEqual(appConfig?["siteKey"] as? String, "Demo Site")
        XCTAssertEqual(appConfig?["terminalId"] as? String, "A2")
        XCTAssertEqual(appConfig?["mode"] as? String, "counter")
    }

    func testRecoveryBrandingComesFromVariantDefaults() {
        let settings = AppSettings(userDefaults: defaults, variant: .demo)

        XCTAssertEqual(settings.loadingImageName, AppVariant.demo.defaults.loadingImageName)
        XCTAssertEqual(settings.recoveryShortMark, AppVariant.demo.defaults.recoveryShortMark)
        XCTAssertEqual(settings.recoveryTitle, AppVariant.demo.defaults.recoveryTitle)
        XCTAssertEqual(settings.recoveryBody, AppVariant.demo.defaults.recoveryBody)
        XCTAssertEqual(settings.recoveryQRCodeDetectedMessage, AppVariant.demo.defaults.recoveryQRCodeDetectedMessage)
        XCTAssertEqual(settings.recoveryInvalidQRMessage, AppVariant.demo.defaults.recoveryInvalidQRMessage)
    }
}
