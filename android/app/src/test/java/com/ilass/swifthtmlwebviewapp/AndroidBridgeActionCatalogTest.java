package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;

import org.junit.Test;

import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.Set;

public class AndroidBridgeActionCatalogTest {
    @Test
    public void registeredActionsMatchCurrentAndroidBridgeSurface() {
        Set<String> expectedPublicActions = new LinkedHashSet<>(Arrays.asList(
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
        ));
        Set<String> expectedInternalActions = new LinkedHashSet<>(Arrays.asList("idleActivity"));
        Set<String> expectedRegisteredActions = new LinkedHashSet<>(expectedPublicActions);
        expectedRegisteredActions.addAll(expectedInternalActions);

        assertEquals(expectedPublicActions, AndroidBridgeActionCatalog.PUBLIC_ACTIONS);
        assertEquals(expectedInternalActions, AndroidBridgeActionCatalog.INTERNAL_ACTIONS);
        assertEquals(expectedRegisteredActions, AndroidBridgeActionCatalog.REGISTERED_ACTIONS);
    }

    @Test
    public void actionGroupsMatchRouterAliases() {
        assertArrayEquals(
                new String[]{"continuousScanStart", "dataScanStart", "loginScanStart"},
                AndroidBridgeActionCatalog.CONTINUOUS_SCANNER_START_ACTIONS
        );
        assertArrayEquals(
                new String[]{"continuousScanStop", "dataScanEnd", "loginScanEnd"},
                AndroidBridgeActionCatalog.CONTINUOUS_SCANNER_STOP_ACTIONS
        );
        assertArrayEquals(
                new String[]{"arPositionStart", "arPositionStop"},
                AndroidBridgeActionCatalog.AR_POSITION_ACTIONS
        );
        assertArrayEquals(
                new String[]{"roomPlanScanStart", "roomPlanScanStop", "roomPlanScanExport"},
                AndroidBridgeActionCatalog.ROOM_PLAN_ACTIONS
        );
        assertArrayEquals(
                new String[]{
                        "arGuidedMeasurementStart",
                        "arGuidedMeasurementSetAnchors",
                        "arGuidedMeasurementUpdateStats",
                        "arGuidedMeasurementStop"
                },
                AndroidBridgeActionCatalog.AR_GUIDED_MEASUREMENT_ACTIONS
        );
        assertArrayEquals(
                new String[]{"arOverlayOpen", "arOverlayClose", "arReplayOpen", "arReplayClose"},
                AndroidBridgeActionCatalog.AR_OVERLAY_ACTIONS
        );
        assertArrayEquals(
                new String[]{
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
                },
                AndroidBridgeActionCatalog.CONFIG_PAIRING_ACTIONS
        );
    }
}
