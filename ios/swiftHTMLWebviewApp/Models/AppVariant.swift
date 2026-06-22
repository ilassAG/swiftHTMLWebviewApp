//
//  AppVariant.swift
//  swiftHTMLWebviewApp
//
//  Product-specific defaults are isolated here so the wrapper core can stay
//  shared across app variants.
//

import Foundation

struct AppVariant: Equatable {
    let id: String
    let bundleIdentifier: String
    let productName: String
    let displayName: String
    let defaults: AppVariantDefaults

    static let demo = AppVariant(
        id: "demo-ios",
        bundleIdentifier: "com.ilass.swiftHTMLWebviewApp",
        productName: "swiftHTMLWebviewApp",
        displayName: "swiftHTMLWebviewApp",
        defaults: AppVariantDefaults(
            serverURL: "local",
            securityToken: "",
            highAvailabilityTimeoutSeconds: 5,
            beaconUUID: "00000000-0000-0000-0000-000000000000",
            loadingImageName: "512",
            appIconName: "AppIcon",
            recoveryShortMark: "SW",
            recoveryTitle: "swiftHTMLWebviewApp",
            recoveryBody: "Die konfigurierte Demo-Adresse antwortet nicht. Scanne einen Konfigurations-QR-Code oder setze eine gueltige URL in den App-Einstellungen.",
            recoveryQRCodeDetectedMessage: "QR-Code erkannt. Verbindung wird geprueft...",
            recoveryInvalidQRMessage: "Der QR-Code enthaelt keine gueltige Server-URL."
        )
    )
}

struct AppVariantDefaults: Equatable {
    let serverURL: String
    let securityToken: String
    let highAvailabilityTimeoutSeconds: Int
    let beaconUUID: String
    let loadingImageName: String
    let appIconName: String
    let recoveryShortMark: String
    let recoveryTitle: String
    let recoveryBody: String
    let recoveryQRCodeDetectedMessage: String
    let recoveryInvalidQRMessage: String
}
