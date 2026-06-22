//
//  SettingsBridgeTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class SettingsBridgeTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var settings: AppSettings!
    private var bridge: SettingsBridge!

    override func setUp() {
        super.setUp()
        suiteName = "SettingsBridgeTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        settings = AppSettings(userDefaults: defaults, variant: .demo)
        settings.registerDefaults()
        bridge = SettingsBridge(settings: settings)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        bridge = nil
        settings = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSettingsGetReturnsPublicSnapshotAndRequestId() {
        settings.securityToken = "secret-token"

        let response = bridge.getResponse(request: ["requestId": "req-1"])
        let snapshot = response["settings"] as? [String: Any]

        XCTAssertEqual(response["platform"] as? String, "ios")
        XCTAssertEqual(response["action"] as? String, "settingsGet")
        XCTAssertEqual(response["requestId"] as? String, "req-1")
        XCTAssertEqual(response["success"] as? Bool, true)
        XCTAssertNil(snapshot?["securityToken"])
        XCTAssertEqual(snapshot?["securityTokenSet"] as? Bool, true)
    }

    func testSettingsSetRejectsMissingOrWrongToken() {
        settings.securityToken = "current-token"

        let response = bridge.setResponse(request: [
            "requestId": "req-2",
            "settings": ["serverURL": "https://example.invalid/mobile/"]
        ])

        XCTAssertEqual(response["action"] as? String, "settingsSet")
        XCTAssertEqual(response["requestId"] as? String, "req-2")
        XCTAssertEqual(response["success"] as? Bool, false)
        XCTAssertEqual(response["error"] as? String, "securityToken is required for settingsSet.")
        XCTAssertEqual(settings.serverURL, AppVariant.demo.defaults.serverURL)
    }

    func testSettingsSetAppliesNestedSettingsWhenTokenMatches() {
        settings.securityToken = "current-token"

        let response = bridge.setResponse(request: [
            "requestId": "req-3",
            "token": "current-token",
            "settings": [
                "serverURL": "https://example.invalid/mobile/",
                "deviceName": "Demo Tablet 03",
                "appConfig": [
                    "siteKey": "Demo Site"
                ]
            ]
        ])
        let snapshot = response["settings"] as? [String: Any]
        let appConfig = snapshot?["appConfig"] as? [String: Any]

        XCTAssertEqual(response["success"] as? Bool, true)
        XCTAssertEqual(settings.serverURL, "https://example.invalid/mobile/")
        XCTAssertEqual(settings.deviceName, "Demo Tablet 03")
        XCTAssertEqual(snapshot?["serverURL"] as? String, "https://example.invalid/mobile/")
        XCTAssertEqual(snapshot?["deviceName"] as? String, "Demo Tablet 03")
        XCTAssertEqual(appConfig?["siteKey"] as? String, "Demo Site")
    }
}
