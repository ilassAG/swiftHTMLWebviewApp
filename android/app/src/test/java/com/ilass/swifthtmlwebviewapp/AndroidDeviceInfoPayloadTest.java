package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

public class AndroidDeviceInfoPayloadTest {
    @Test
    public void responseUsesDiagnosticsEnvelopeAndRuntimeSnapshots() throws Exception {
        AndroidDeviceInfoPayload.Snapshot snapshot = new AndroidDeviceInfoPayload.Snapshot();
        snapshot.name = "pixel_9";
        snapshot.appUUID = "APP-123";
        snapshot.configuredDeviceName = "Demo Entry Device";
        snapshot.configuredDeviceUUID = "device-123";
        snapshot.configuredDeviceLocation = "EG";
        snapshot.osVersion = "16";
        snapshot.sdkInt = 36;
        snapshot.manufacturer = "Google";
        snapshot.brand = "google";
        snapshot.device = "tokay";
        snapshot.model = "Pixel 9";
        snapshot.product = "tokay_beta";
        snapshot.hardware = "tokay";
        snapshot.serialNumber = "unavailable";
        snapshot.androidId = "android-id";
        snapshot.appVersion = "1.2.3";
        snapshot.battery = new JSONObject().put("percent", 84.5);
        snapshot.screen = new JSONObject().put("widthPixels", 1080);
        snapshot.memory = new JSONObject().put("lowMemory", false);
        snapshot.network = new JSONObject().put("ssid", "Office");
        snapshot.cameras = new JSONArray().put(new JSONObject().put("id", "0"));
        snapshot.sensors = new JSONArray().put(new JSONObject().put("name", "Accelerometer"));
        snapshot.capabilities = new JSONObject().put("deviceInfoGet", true);
        snapshot.nats = new JSONObject().put("connected", false);

        JSONObject response = AndroidDeviceInfoPayload.response(
                new JSONObject().put("requestId", "req-device"),
                snapshot
        );

        assertEquals("android", response.getString("platform"));
        assertEquals("deviceInfoGet", response.getString("action"));
        assertEquals("req-device", response.getString("requestId"));
        assertTrue(response.getBoolean("success"));
        assertEquals("pixel_9", response.getString("name"));
        assertEquals("APP-123", response.getString("appUUID"));
        assertEquals("Demo Entry Device", response.getString("configuredDeviceName"));
        assertEquals("device-123", response.getString("configuredDeviceUUID"));
        assertEquals("EG", response.getString("configuredDeviceLocation"));
        assertEquals("Android", response.getString("os"));
        assertEquals("16", response.getString("osVersion"));
        assertEquals(36, response.getInt("sdkInt"));
        assertEquals("Google", response.getString("manufacturer"));
        assertEquals("google", response.getString("brand"));
        assertEquals("tokay", response.getString("device"));
        assertEquals("Pixel 9", response.getString("model"));
        assertEquals("tokay_beta", response.getString("product"));
        assertEquals("tokay", response.getString("hardware"));
        assertEquals("unavailable", response.getString("serialNumber"));
        assertEquals("android-id", response.getString("androidId"));
        assertEquals("1.2.3", response.getString("appVersion"));
        assertEquals(84.5, response.getJSONObject("battery").getDouble("percent"), 0.001);
        assertEquals(1080, response.getJSONObject("screen").getInt("widthPixels"));
        assertFalse(response.getJSONObject("memory").getBoolean("lowMemory"));
        assertEquals("Office", response.getJSONObject("network").getString("ssid"));
        assertEquals("0", response.getJSONArray("cameras").getJSONObject(0).getString("id"));
        assertEquals("Accelerometer", response.getJSONArray("sensors").getJSONObject(0).getString("name"));
        assertTrue(response.getJSONObject("capabilities").getBoolean("deviceInfoGet"));
        assertFalse(response.getJSONObject("nats").getBoolean("connected"));
    }

    @Test
    public void responseKeepsStableKeysWhenSnapshotValuesAreMissing() throws Exception {
        JSONObject response = AndroidDeviceInfoPayload.response(new JSONObject(), new AndroidDeviceInfoPayload.Snapshot());

        assertEquals("android", response.getString("platform"));
        assertEquals("deviceInfoGet", response.getString("action"));
        assertTrue(response.getBoolean("success"));
        assertEquals("", response.getString("name"));
        assertEquals("", response.getString("appUUID"));
        assertEquals("", response.getString("configuredDeviceName"));
        assertEquals("", response.getString("configuredDeviceUUID"));
        assertEquals("", response.getString("configuredDeviceLocation"));
        assertEquals("Android", response.getString("os"));
        assertEquals("", response.getString("osVersion"));
        assertEquals(0, response.getInt("sdkInt"));
        assertEquals("", response.getString("manufacturer"));
        assertEquals("", response.getString("brand"));
        assertEquals("", response.getString("device"));
        assertEquals("", response.getString("model"));
        assertEquals("", response.getString("product"));
        assertEquals("", response.getString("hardware"));
        assertEquals("", response.getString("serialNumber"));
        assertEquals("", response.getString("androidId"));
        assertEquals("", response.getString("appVersion"));
        assertEquals(0, response.getJSONObject("battery").length());
        assertEquals(0, response.getJSONObject("screen").length());
        assertEquals(0, response.getJSONObject("memory").length());
        assertEquals(0, response.getJSONObject("network").length());
        assertEquals(0, response.getJSONArray("cameras").length());
        assertEquals(0, response.getJSONArray("sensors").length());
        assertEquals(0, response.getJSONObject("capabilities").length());
    }

    @Test
    public void configPairingDeviceSummaryUsesStableRuntimeShape() throws Exception {
        AndroidDeviceInfoPayload.DeviceSummary summary = new AndroidDeviceInfoPayload.DeviceSummary();
        summary.manufacturer = "Google";
        summary.model = "Pixel 9";
        summary.device = "tokay";
        summary.osVersion = "16";
        summary.sdkInt = 36;
        summary.appVersion = "1.2.3";
        summary.wifi = new JSONObject()
                .put("ssidAvailable", true)
                .put("ssid", "Office");

        JSONObject response = AndroidDeviceInfoPayload.configPairingDeviceSummary(summary);

        assertEquals("Google", response.getString("manufacturer"));
        assertEquals("Pixel 9", response.getString("model"));
        assertEquals("tokay", response.getString("device"));
        assertEquals("Android", response.getString("os"));
        assertEquals("16", response.getString("osVersion"));
        assertEquals(36, response.getInt("sdkInt"));
        assertEquals("1.2.3", response.getString("appVersion"));
        assertTrue(response.getJSONObject("wifi").getBoolean("ssidAvailable"));

        response = AndroidDeviceInfoPayload.configPairingDeviceSummary(new AndroidDeviceInfoPayload.DeviceSummary());

        assertEquals("", response.getString("manufacturer"));
        assertEquals("", response.getString("model"));
        assertEquals("", response.getString("device"));
        assertEquals("Android", response.getString("os"));
        assertEquals("", response.getString("osVersion"));
        assertEquals(0, response.getInt("sdkInt"));
        assertEquals("", response.getString("appVersion"));
        assertEquals(0, response.getJSONObject("wifi").length());
    }

    @Test
    public void batteryPayloadCalculatesPercentChargingAndPowerSource() throws Exception {
        JSONObject response = AndroidDeviceInfoPayload.battery(42, 50, 2, 2);

        assertEquals(42, response.getInt("level"));
        assertEquals(50, response.getInt("scale"));
        assertEquals(84.0, response.getDouble("percent"), 0.001);
        assertTrue(response.getBoolean("charging"));
        assertEquals(2, response.getInt("plugged"));
        assertEquals("usb", response.getString("powerSource"));

        response = AndroidDeviceInfoPayload.battery(-1, 0, 0, 3);

        assertTrue(response.isNull("percent"));
        assertFalse(response.getBoolean("charging"));
        assertEquals("battery", response.getString("powerSource"));
    }

    @Test
    public void screenPayloadUsesDisplayMetricsShape() throws Exception {
        JSONObject response = AndroidDeviceInfoPayload.screen(1080, 2400, 2.75f, 440, 2.8f);

        assertEquals(1080, response.getInt("widthPixels"));
        assertEquals(2400, response.getInt("heightPixels"));
        assertEquals(2.75, response.getDouble("density"), 0.001);
        assertEquals(440, response.getInt("densityDpi"));
        assertEquals(2.8, response.getDouble("scaledDensity"), 0.001);
    }

    @Test
    public void memoryPayloadUsesRuntimeMemoryShape() throws Exception {
        JSONObject response = AndroidDeviceInfoPayload.memory(8_000L, 3_000L, true, 1_000L);

        assertEquals(8_000L, response.getLong("totalBytes"));
        assertEquals(3_000L, response.getLong("availableBytes"));
        assertTrue(response.getBoolean("lowMemory"));
        assertEquals(1_000L, response.getLong("thresholdBytes"));
    }

    @Test
    public void cameraPayloadNormalizesLensFacingValues() throws Exception {
        JSONObject front = AndroidDeviceInfoPayload.camera("0", 0);
        JSONObject back = AndroidDeviceInfoPayload.camera("1", 1);
        JSONObject external = AndroidDeviceInfoPayload.camera("2", 2);
        JSONObject unknown = AndroidDeviceInfoPayload.camera(null, null);

        assertEquals("0", front.getString("id"));
        assertEquals("front", front.getString("lensFacing"));
        assertEquals("back", back.getString("lensFacing"));
        assertEquals("external", external.getString("lensFacing"));
        assertEquals("", unknown.getString("id"));
        assertEquals("unknown", unknown.getString("lensFacing"));
    }

    @Test
    public void sensorPayloadUsesStableDiagnosticsShape() throws Exception {
        JSONObject response = AndroidDeviceInfoPayload.sensor(
                "Accelerometer",
                "Google",
                1,
                3,
                19.6f,
                0.01f,
                0.2f
        );

        assertEquals("Accelerometer", response.getString("name"));
        assertEquals("Google", response.getString("vendor"));
        assertEquals(1, response.getInt("type"));
        assertEquals(3, response.getInt("version"));
        assertEquals(19.6, response.getDouble("maximumRange"), 0.001);
        assertEquals(0.01, response.getDouble("resolution"), 0.001);
        assertEquals(0.2, response.getDouble("powerMilliAmp"), 0.001);

        response = AndroidDeviceInfoPayload.sensor(null, null, 0, 0, 0f, 0f, 0f);

        assertEquals("", response.getString("name"));
        assertEquals("", response.getString("vendor"));
    }
}
