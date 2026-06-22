//
//  AppVariantTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class AppVariantTests: XCTestCase {
    func testDemoIdentityMatchesCurrentProduct() {
        let variant = AppVariant.demo

        XCTAssertEqual(variant.id, "demo-ios")
        XCTAssertEqual(variant.bundleIdentifier, "com.ilass.swiftHTMLWebviewApp")
        XCTAssertEqual(variant.productName, "swiftHTMLWebviewApp")
        XCTAssertEqual(variant.displayName, "swiftHTMLWebviewApp")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, variant.displayName)
    }

    func testDemoDefaultsMatchCurrentSettingsBundle() throws {
        let defaults = AppVariant.demo.defaults

        XCTAssertEqual(defaults.serverURL, "local")
        XCTAssertEqual(defaults.securityToken, "")
        XCTAssertEqual(defaults.highAvailabilityTimeoutSeconds, 5)
        XCTAssertEqual(defaults.beaconUUID, "00000000-0000-0000-0000-000000000000")
        XCTAssertEqual(defaults.loadingImageName, "512")
        XCTAssertEqual(defaults.appIconName, "AppIcon")
        XCTAssertEqual(defaults.recoveryShortMark, "SW")
        XCTAssertEqual(defaults.recoveryTitle, "swiftHTMLWebviewApp")
        XCTAssertEqual(defaults.recoveryBody, "Die konfigurierte Demo-Adresse antwortet nicht. Scanne einen Konfigurations-QR-Code oder setze eine gueltige URL in den App-Einstellungen.")
        XCTAssertEqual(defaults.recoveryQRCodeDetectedMessage, "QR-Code erkannt. Verbindung wird geprueft...")
        XCTAssertEqual(defaults.recoveryInvalidQRMessage, "Der QR-Code enthaelt keine gueltige Server-URL.")

        let settings = try settingsBundleDefaults()
        XCTAssertEqual(settings["server_url_preference"] as? String, defaults.serverURL)
        XCTAssertEqual(settings["security_token_preference"] as? String, defaults.securityToken)
        XCTAssertEqual(settings["ha_timeout"] as? Int, defaults.highAvailabilityTimeoutSeconds)
        XCTAssertEqual(settings["beacon_uuid"] as? String, defaults.beaconUUID)
    }

    private func settingsBundleDefaults() throws -> [String: Any] {
        let settingsBundleURL = try XCTUnwrap(Bundle.main.url(forResource: "Settings", withExtension: "bundle"))
        let rootPlistURL = settingsBundleURL.appendingPathComponent("Root.plist")
        let data = try Data(contentsOf: rootPlistURL)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let root = try XCTUnwrap(plist as? [String: Any])
        let specifiers = try XCTUnwrap(root["PreferenceSpecifiers"] as? [[String: Any]])

        return specifiers.reduce(into: [String: Any]()) { result, specifier in
            guard let key = specifier["Key"] as? String else { return }
            result[key] = specifier["DefaultValue"]
        }
    }
}
