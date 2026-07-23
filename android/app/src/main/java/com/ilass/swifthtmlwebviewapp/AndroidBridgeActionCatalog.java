package com.ilass.swifthtmlwebviewapp;

import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.Set;

final class AndroidBridgeActionCatalog {
    static final String[] CONTINUOUS_SCANNER_START_ACTIONS = {
            "continuousScanStart",
            "dataScanStart",
            "loginScanStart"
    };

    static final String[] CONTINUOUS_SCANNER_STOP_ACTIONS = {
            "continuousScanStop",
            "dataScanEnd",
            "loginScanEnd"
    };

    static final String[] AR_POSITION_ACTIONS = {
            "arPositionStart",
            "arPositionStop"
    };

    static final String[] ROOM_PLAN_ACTIONS = {
            "roomPlanScanStart",
            "roomPlanScanStop",
            "roomPlanScanExport"
    };

    static final String[] AR_GUIDED_MEASUREMENT_ACTIONS = {
            "arGuidedMeasurementStart",
            "arGuidedMeasurementSetAnchors",
            "arGuidedMeasurementUpdateStats",
            "arGuidedMeasurementStop"
    };

    static final String[] AR_OVERLAY_ACTIONS = {
            "arOverlayOpen",
            "arOverlayClose",
            "arReplayOpen",
            "arReplayClose"
    };

    static final String[] CONFIG_PAIRING_ACTIONS = {
            "configPairingShow",
            "configPairingStop",
            "configPairingConnect",
            "configPairingDisconnect",
            "configPairingSend",
            "configDeviceScanStart",
            "configDeviceScanStop",
            "configDeviceConnect",
            "configDeviceDisconnect",
            "configDeviceSend"
    };

    static final Set<String> PUBLIC_ACTIONS = stringSet(
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
    );

    static final Set<String> INTERNAL_ACTIONS = stringSet("idleActivity");

    static final Set<String> REGISTERED_ACTIONS;

    static {
        LinkedHashSet<String> actions = new LinkedHashSet<>(PUBLIC_ACTIONS);
        actions.addAll(INTERNAL_ACTIONS);
        REGISTERED_ACTIONS = Collections.unmodifiableSet(actions);
    }

    private AndroidBridgeActionCatalog() {
    }

    static void assertRegisteredActions(Set<String> actions) {
        if (REGISTERED_ACTIONS.equals(actions)) {
            return;
        }
        LinkedHashSet<String> missing = new LinkedHashSet<>(REGISTERED_ACTIONS);
        missing.removeAll(actions);
        LinkedHashSet<String> extra = new LinkedHashSet<>(actions);
        extra.removeAll(REGISTERED_ACTIONS);
        throw new IllegalStateException(
                "Android bridge router actions drifted. Missing: " + missing + ". Extra: " + extra + "."
        );
    }

    private static Set<String> stringSet(String... values) {
        return Collections.unmodifiableSet(new LinkedHashSet<>(Arrays.asList(values)));
    }
}
