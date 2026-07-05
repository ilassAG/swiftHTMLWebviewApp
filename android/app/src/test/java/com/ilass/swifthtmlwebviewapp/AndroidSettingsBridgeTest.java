package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.json.JSONException;
import org.json.JSONObject;
import org.junit.Test;

public class AndroidSettingsBridgeTest {
    @Test
    public void settingsGetReturnsPublicSnapshotAndRequestId() throws JSONException {
        FakeHost host = new FakeHost();
        host.securityToken = "secret-token";
        AndroidSettingsBridge bridge = new AndroidSettingsBridge(host);

        JSONObject response = bridge.getResponse(new JSONObject().put("requestId", "req-1"));
        JSONObject settings = response.getJSONObject("settings");

        assertEquals("android", response.getString("platform"));
        assertEquals("settingsGet", response.getString("action"));
        assertEquals("req-1", response.getString("requestId"));
        assertTrue(response.getBoolean("success"));
        assertNull(settings.opt("securityToken"));
        assertTrue(settings.getBoolean("securityTokenSet"));
    }

    @Test
    public void settingsSetRejectsMissingOrWrongToken() throws JSONException {
        FakeHost host = new FakeHost();
        host.securityToken = "current-token";
        AndroidSettingsBridge bridge = new AndroidSettingsBridge(host);

        JSONObject response = bridge.setResponse(new JSONObject()
                .put("requestId", "req-2")
                .put("settings", new JSONObject().put("serverURL", "https://example.invalid/mobile/")));

        assertEquals("settingsSet", response.getString("action"));
        assertEquals("req-2", response.getString("requestId"));
        assertFalse(response.getBoolean("success"));
        assertEquals("securityToken is required for settingsSet.", response.getString("error"));
        assertNull(host.appliedValues);
    }

    @Test
    public void settingsSetAppliesNestedSettingsWhenTokenMatches() throws JSONException {
        FakeHost host = new FakeHost();
        host.securityToken = "current-token";
        AndroidSettingsBridge bridge = new AndroidSettingsBridge(host);

        JSONObject response = bridge.setResponse(new JSONObject()
                .put("requestId", "req-3")
                .put("token", "current-token")
                .put("settings", new JSONObject()
                        .put("serverURL", "https://example.invalid/mobile/")
                        .put("deviceName", "Demo Tablet 03")));
        JSONObject settings = response.getJSONObject("settings");

        assertTrue(response.getBoolean("success"));
        assertEquals("https://example.invalid/mobile/", host.appliedValues.getString("serverURL"));
        assertEquals("Demo Tablet 03", host.appliedValues.getString("deviceName"));
        assertEquals("https://example.invalid/mobile/", settings.getString("serverURL"));
        assertEquals("Demo Tablet 03", settings.getString("deviceName"));
    }

    @Test
    public void settingsSnapshotUsesPublicConfigShapeWithoutTokenValue() throws JSONException {
        AndroidSettingsBridge.SettingsSnapshot snapshot = new AndroidSettingsBridge.SettingsSnapshot();
        snapshot.serverURL = "https://example.invalid/mobile/";
        snapshot.securityTokenSet = true;
        snapshot.highAvailabilityEnabled = true;
        snapshot.highAvailabilityTimeoutSeconds = 12;
        snapshot.highAvailabilityURL2 = "https://ha2.example.invalid/mobile/";
        snapshot.highAvailabilityURL3 = "https://ha3.example.invalid/mobile/";
        snapshot.highAvailabilityURL4 = "https://ha4.example.invalid/mobile/";
        snapshot.beaconUUID = "D57092AC-DFAA-446C-8EF3-C81AA22815B5";
        snapshot.appUUID = "APP-123";
        snapshot.deviceName = "Demo Entry Device";
        snapshot.deviceUUID = "DEVICE-123";
        snapshot.deviceLocation = "EG";
        snapshot.appConfig = new JSONObject().put("siteKey", "Demo Site");

        JSONObject response = AndroidSettingsBridge.snapshotPayload(snapshot);

        assertEquals("https://example.invalid/mobile/", response.getString("serverURL"));
        assertTrue(response.getBoolean("securityTokenSet"));
        assertFalse(response.has("securityToken"));
        assertTrue(response.getBoolean("highAvailabilityEnabled"));
        assertEquals(12, response.getInt("highAvailabilityTimeoutSeconds"));
        assertEquals("https://ha2.example.invalid/mobile/", response.getString("highAvailabilityURL2"));
        assertEquals("https://ha3.example.invalid/mobile/", response.getString("highAvailabilityURL3"));
        assertEquals("https://ha4.example.invalid/mobile/", response.getString("highAvailabilityURL4"));
        assertEquals("D57092AC-DFAA-446C-8EF3-C81AA22815B5", response.getString("beaconUUID"));
        assertEquals("APP-123", response.getString("appUUID"));
        assertEquals("Demo Entry Device", response.getString("deviceName"));
        assertEquals("DEVICE-123", response.getString("deviceUUID"));
        assertEquals("EG", response.getString("deviceLocation"));
        assertEquals("Demo Site", response.getJSONObject("appConfig").getString("siteKey"));

        response = AndroidSettingsBridge.snapshotPayload(new AndroidSettingsBridge.SettingsSnapshot());

        assertEquals("", response.getString("serverURL"));
        assertFalse(response.getBoolean("securityTokenSet"));
        assertEquals(1, response.getInt("highAvailabilityTimeoutSeconds"));
        assertEquals("", response.getString("appUUID"));
        assertEquals("", response.getString("deviceLocation"));
    }

    private static final class FakeHost implements AndroidSettingsBridge.Host {
        String securityToken = "";
        JSONObject appliedValues;

        @Override
        public String configSecurityToken() {
            return securityToken;
        }

        @Override
        public JSONObject configSettingsSnapshot() throws JSONException {
            return new JSONObject()
                    .put("serverURL", "local")
                    .put("securityTokenSet", !securityToken.isEmpty());
        }

        @Override
        public JSONObject applyConfigSettings(JSONObject values) throws JSONException {
            appliedValues = values;
            return new JSONObject()
                    .put("serverURL", values.optString("serverURL", "local"))
                    .put("deviceName", values.optString("deviceName", ""));
        }
    }
}
