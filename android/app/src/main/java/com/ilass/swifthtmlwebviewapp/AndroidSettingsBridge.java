package com.ilass.swifthtmlwebviewapp;

import org.json.JSONException;
import org.json.JSONObject;

final class AndroidSettingsBridge {
    static final class SettingsSnapshot {
        String serverURL = "";
        boolean securityTokenSet = false;
        boolean highAvailabilityEnabled = false;
        int highAvailabilityTimeoutSeconds = 1;
        String highAvailabilityURL2 = "";
        String highAvailabilityURL3 = "";
        String highAvailabilityURL4 = "";
        String beaconUUID = "";
        String appUUID = "";
        String deviceName = "";
        String deviceUUID = "";
        String deviceLocation = "";
        JSONObject appConfig = new JSONObject();
    }

    interface Host {
        String configSecurityToken();

        JSONObject configSettingsSnapshot() throws JSONException;

        JSONObject applyConfigSettings(JSONObject values) throws JSONException;
    }

    private final Host host;

    AndroidSettingsBridge(Host host) {
        this.host = host;
    }

    JSONObject getResponse(JSONObject message) throws JSONException {
        JSONObject response = BridgeResponse.base(message, "settingsGet");
        response.put("success", true);
        response.put("settings", host.configSettingsSnapshot());
        return response;
    }

    JSONObject setResponse(JSONObject message) throws JSONException {
        String token = nonEmpty(message.optString("token", message.optString("securityToken", "")), "");
        if (token.isEmpty() || !token.equals(host.configSecurityToken())) {
            return BridgeResponse.error(message, "settingsSet", "securityToken is required for settingsSet.");
        }

        JSONObject values = message.optJSONObject("settings");
        JSONObject snapshot = host.applyConfigSettings(values != null ? values : message);
        JSONObject response = BridgeResponse.base(message, "settingsSet");
        response.put("success", true);
        response.put("settings", snapshot);
        return response;
    }

    static JSONObject snapshotPayload(SettingsSnapshot snapshot) throws JSONException {
        SettingsSnapshot data = snapshot != null ? snapshot : new SettingsSnapshot();
        JSONObject settings = new JSONObject();
        settings.put("serverURL", stringOrEmpty(data.serverURL));
        settings.put("securityTokenSet", data.securityTokenSet);
        settings.put("highAvailabilityEnabled", data.highAvailabilityEnabled);
        settings.put("highAvailabilityTimeoutSeconds", Math.max(1, data.highAvailabilityTimeoutSeconds));
        settings.put("highAvailabilityURL2", stringOrEmpty(data.highAvailabilityURL2));
        settings.put("highAvailabilityURL3", stringOrEmpty(data.highAvailabilityURL3));
        settings.put("highAvailabilityURL4", stringOrEmpty(data.highAvailabilityURL4));
        settings.put("beaconUUID", stringOrEmpty(data.beaconUUID));
        settings.put("appUUID", stringOrEmpty(data.appUUID));
        settings.put("deviceName", stringOrEmpty(data.deviceName));
        settings.put("deviceUUID", stringOrEmpty(data.deviceUUID));
        settings.put("deviceLocation", stringOrEmpty(data.deviceLocation));
        settings.put("appConfig", data.appConfig != null ? data.appConfig : new JSONObject());
        return settings;
    }

    private static String nonEmpty(String value, String fallback) {
        if (value == null) {
            return fallback;
        }
        String trimmed = value.trim();
        return trimmed.isEmpty() ? fallback : trimmed;
    }

    private static String stringOrEmpty(String value) {
        return value != null ? value : "";
    }
}
