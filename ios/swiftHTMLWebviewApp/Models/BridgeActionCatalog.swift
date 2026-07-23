//
//  BridgeActionCatalog.swift
//  swiftHTMLWebviewApp
//

import Foundation

enum BridgeActionCatalog {
    static let continuousScannerStartActions = [
        "continuousScanStart",
        "dataScanStart",
        "loginScanStart"
    ]

    static let continuousScannerStopActions = [
        "continuousScanStop",
        "dataScanEnd",
        "loginScanEnd"
    ]

    static let arOverlayOpenActions = [
        "arOverlayOpen",
        "arReplayOpen"
    ]

    static let arOverlayCloseActions = [
        "arOverlayClose",
        "arReplayClose"
    ]

    static let publicActions: Set<String> = [
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
        "storageGet",
        "storageSet",
        "storageRemove",
        "storageClear",
        "filesystemWrite",
        "filesystemRead",
        "filesystemList",
        "filesystemDelete",
        "sqliteExecute",
        "sqliteDeleteDatabase",
        "kioskReloadControlSet",
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
        "natsProvision",
        "natsStatus",
        "natsConnect",
        "natsDisconnect",
        "natsPublish",
        "configPairingShow",
        "configPairingStop",
        "configPairingConnect",
        "configPairingDisconnect",
        "configPairingSend",
        "configDeviceScanStart",
        "configDeviceScanStop",
        "configDeviceConnect",
        "configDeviceDisconnect",
        "configDeviceSend",
        "reload",
        "launchConfetti",
        "tapToPayAvailability",
        "tapToPayCollect",
        "printerDiscover",
        "printerHelloWorld",
        "printerPrint",
        "printerEpsonHelloWorld"
    ]

    static let internalActions: Set<String> = [
        "idleActivity"
    ]

    static var registeredActions: Set<String> {
        publicActions.union(internalActions)
    }

    static func assertRegisteredActions(_ actions: Set<String>, file: StaticString = #file, line: UInt = #line) {
        let missing = registeredActions.subtracting(actions).sorted().joined(separator: ", ")
        let extra = actions.subtracting(registeredActions).sorted().joined(separator: ", ")
        assert(
            actions == registeredActions,
            "Bridge router actions drifted. Missing: \(missing.isEmpty ? "-" : missing). Extra: \(extra.isEmpty ? "-" : extra).",
            file: file,
            line: line
        )
    }
}
