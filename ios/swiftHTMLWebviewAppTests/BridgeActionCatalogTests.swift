//
//  BridgeActionCatalogTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class BridgeActionCatalogTests: XCTestCase {
    func testRegisteredActionsMatchCurrentIOSBridgeSurface() {
        let expectedPublicActions: Set<String> = [
            "scanDocument",
            "takePhoto",
            "portraitCapture",
            "scanBarcode",
            "nfcTagRead",
            "continuousScanStart",
            "continuousScanStop",
            "dataScanStart",
            "dataScanEnd",
            "loginScanStart",
            "loginScanEnd",
            "previewBoxLocationUpdate",
            "beaconsStart",
            "beaconsStop",
            "beaconAdvertiseStart",
            "beaconAdvertiseStop",
            "deviceInfoGet",
            "settingsGet",
            "settingsSet",
            "screenOrientationGet",
            "screenOrientationSet",
            "wifiStatusGet",
            "wifiConfigure",
            "screenshotGet",
            "geoLocationGet",
            "geoLocationStart",
            "geoLocationStop",
            "arPositionStart",
            "arPositionStop",
            "arGuidedMeasurementStart",
            "arGuidedMeasurementSetAnchors",
            "arGuidedMeasurementUpdateStats",
            "arGuidedMeasurementStop",
            "arOverlayOpen",
            "arOverlayClose",
            "arReplayOpen",
            "arReplayClose",
            "roomPlanScanStart",
            "roomPlanScanStop",
            "roomPlanScanExport",
            "soundPlay",
            "notificationPermissionGet",
            "notificationPermissionRequest",
            "notificationShow",
            "notificationSchedule",
            "notificationCancel",
            "notificationCancelAll",
            "notificationList",
            "idleTimerStart",
            "idleTimerReset",
            "idleTimerStop",
            "sensorCapabilitiesGet",
            "sensorStreamStart",
            "sensorStreamStop",
            "screenStreamStart",
            "screenStreamStop",
            "configPairingShow",
            "configPairingStop",
            "configPairingConnect",
            "configPairingDisconnect",
            "configPairingSend",
            "reload",
            "launchConfetti",
            "tapToPayAvailability",
            "tapToPayCollect",
            "printerDiscover",
            "printerHelloWorld",
            "printerPrint",
            "printerEpsonHelloWorld"
        ]

        XCTAssertEqual(BridgeActionCatalog.publicActions, expectedPublicActions)
        XCTAssertEqual(BridgeActionCatalog.internalActions, ["idleActivity"])
        XCTAssertEqual(BridgeActionCatalog.registeredActions, expectedPublicActions.union(["idleActivity"]))
    }

    func testActionGroupsMatchRouterAliases() {
        XCTAssertEqual(BridgeActionCatalog.continuousScannerStartActions, [
            "continuousScanStart",
            "dataScanStart",
            "loginScanStart"
        ])
        XCTAssertEqual(BridgeActionCatalog.continuousScannerStopActions, [
            "continuousScanStop",
            "dataScanEnd",
            "loginScanEnd"
        ])
        XCTAssertEqual(BridgeActionCatalog.arOverlayOpenActions, [
            "arOverlayOpen",
            "arReplayOpen"
        ])
        XCTAssertEqual(BridgeActionCatalog.arOverlayCloseActions, [
            "arOverlayClose",
            "arReplayClose"
        ])
    }
}
