package com.ilass.swifthtmlwebviewapp;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.Arrays;

final class AndroidDeviceCapabilities {
    private AndroidDeviceCapabilities() {
    }

    static JSONObject build(
            boolean nfcAvailable,
            boolean nfcEnabled,
            boolean tapToPayIncluded,
            boolean beaconAdvertiseSupported
    ) throws JSONException {
        JSONObject capabilities = new JSONObject();
        capabilities.put("deviceInfoGet", true);
        capabilities.put("settingsGet", true);
        capabilities.put("settingsSet", true);
        capabilities.put("storageGet", true);
        capabilities.put("storageSet", true);
        capabilities.put("storageRemove", true);
        capabilities.put("storageClear", true);
        capabilities.put("filesystemWrite", true);
        capabilities.put("filesystemRead", true);
        capabilities.put("filesystemList", true);
        capabilities.put("filesystemDelete", true);
        capabilities.put("sqliteExecute", true);
        capabilities.put("sqliteDeleteDatabase", true);
        capabilities.put("kioskReloadControlSet", true);
        capabilities.put("screenOrientationSet", true);
        capabilities.put("wifiConfigure", true);
        capabilities.put("screenshotGet", true);
        capabilities.put("geoLocationGet", true);
        capabilities.put("screenStreamStart", true);
        capabilities.put("screenStreamFormats", new JSONArray(Arrays.asList("jpeg")));
        capabilities.put("natsProvision", true);
        capabilities.put("natsStatus", true);
        capabilities.put("natsConnect", true);
        capabilities.put("natsDisconnect", true);
        capabilities.put("natsPublish", true);
        capabilities.put("soundPlay", true);
        capabilities.put("notificationPermissionGet", true);
        capabilities.put("notificationPermissionRequest", true);
        capabilities.put("notificationShow", true);
        capabilities.put("notificationSchedule", true);
        capabilities.put("notificationCancel", true);
        capabilities.put("notificationCancelAll", true);
        capabilities.put("notificationList", true);
        capabilities.put("idleTimerStart", true);
        capabilities.put("sensorStreamStart", true);
        capabilities.put("arPositionStart", false);
        capabilities.put("arPositionStop", false);
        capabilities.put("arPositionSupported", false);
        capabilities.put("roomPlanScanStart", false);
        capabilities.put("roomPlanScanStop", false);
        capabilities.put("roomPlanScanExport", false);
        capabilities.put("roomPlanSupported", false);
        capabilities.put("arGuidedMeasurementStart", false);
        capabilities.put("arGuidedMeasurementSetAnchors", false);
        capabilities.put("arGuidedMeasurementUpdateStats", false);
        capabilities.put("arGuidedMeasurementStop", false);
        capabilities.put("arGuidedMeasurementSupported", false);
        capabilities.put("arOverlayOpen", false);
        capabilities.put("arOverlayClose", false);
        capabilities.put("arOverlaySupported", false);
        capabilities.put("arOverlayWGS84", false);
        capabilities.put("arReplayOpen", false);
        capabilities.put("arReplayClose", false);
        capabilities.put("configPairingShow", true);
        capabilities.put("configPairingConnect", true);
        capabilities.put("nfcTagRead", nfcAvailable);
        capabilities.put("nfcEnabled", nfcEnabled);
        capabilities.put("tapToPayAvailability", true);
        capabilities.put("tapToPayCollect", tapToPayIncluded);
        capabilities.put("tapToPayNative", tapToPayIncluded);
        capabilities.put("beaconAdvertiseStart", beaconAdvertiseSupported);
        capabilities.put("beaconAdvertiseStop", true);
        capabilities.put("beaconAdvertiseSupported", beaconAdvertiseSupported);
        return capabilities;
    }
}
