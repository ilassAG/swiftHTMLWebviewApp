package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.json.JSONObject;
import org.junit.Test;

public class AndroidDeviceCapabilitiesTest {
    @Test
    public void buildKeepsCommonWrapperCapabilitiesEnabled() throws Exception {
        JSONObject capabilities = AndroidDeviceCapabilities.build(false, false, false, false);

        assertTrue(capabilities.getBoolean("deviceInfoGet"));
        assertTrue(capabilities.getBoolean("settingsGet"));
        assertTrue(capabilities.getBoolean("settingsSet"));
        assertTrue(capabilities.getBoolean("storageGet"));
        assertTrue(capabilities.getBoolean("filesystemWrite"));
        assertTrue(capabilities.getBoolean("sqliteExecute"));
        assertTrue(capabilities.getBoolean("kioskReloadControlSet"));
        assertTrue(capabilities.getBoolean("wifiConfigure"));
        assertTrue(capabilities.getBoolean("screenStreamStart"));
        assertEquals("jpeg", capabilities.getJSONArray("screenStreamFormats").getString(0));
        assertTrue(capabilities.getBoolean("notificationShow"));
        assertTrue(capabilities.getBoolean("sensorStreamStart"));
        assertTrue(capabilities.getBoolean("configPairingShow"));
    }

    @Test
    public void buildKeepsUnsupportedAppleOnlyCapabilitiesUnavailableOnAndroid() throws Exception {
        JSONObject capabilities = AndroidDeviceCapabilities.build(false, false, false, false);

        assertFalse(capabilities.getBoolean("arPositionStart"));
        assertFalse(capabilities.getBoolean("arPositionStop"));
        assertFalse(capabilities.getBoolean("arPositionSupported"));
        assertFalse(capabilities.getBoolean("roomPlanScanStart"));
        assertFalse(capabilities.getBoolean("roomPlanSupported"));
        assertFalse(capabilities.getBoolean("arGuidedMeasurementStart"));
        assertFalse(capabilities.getBoolean("arOverlayOpen"));
        assertFalse(capabilities.getBoolean("arReplayOpen"));
    }

    @Test
    public void buildReflectsRuntimeOptionalModules() throws Exception {
        JSONObject capabilities = AndroidDeviceCapabilities.build(true, true, true, true);

        assertTrue(capabilities.getBoolean("nfcTagRead"));
        assertTrue(capabilities.getBoolean("nfcEnabled"));
        assertTrue(capabilities.getBoolean("tapToPayAvailability"));
        assertTrue(capabilities.getBoolean("tapToPayCollect"));
        assertTrue(capabilities.getBoolean("tapToPayNative"));
        assertTrue(capabilities.getBoolean("beaconAdvertiseStart"));
        assertTrue(capabilities.getBoolean("beaconAdvertiseStop"));
        assertTrue(capabilities.getBoolean("beaconAdvertiseSupported"));
    }

    @Test
    public void buildDisablesRuntimeOptionalModulesWhenUnavailable() throws Exception {
        JSONObject capabilities = AndroidDeviceCapabilities.build(false, false, false, false);

        assertFalse(capabilities.getBoolean("nfcTagRead"));
        assertFalse(capabilities.getBoolean("nfcEnabled"));
        assertTrue(capabilities.getBoolean("tapToPayAvailability"));
        assertFalse(capabilities.getBoolean("tapToPayCollect"));
        assertFalse(capabilities.getBoolean("tapToPayNative"));
        assertFalse(capabilities.getBoolean("beaconAdvertiseStart"));
        assertTrue(capabilities.getBoolean("beaconAdvertiseStop"));
        assertFalse(capabilities.getBoolean("beaconAdvertiseSupported"));
    }
}
