package com.ilass.swifthtmlwebviewapp;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Locale;
import java.util.UUID;

final class AndroidSettingsStore {
    static final String PREFS_NAME = "swift_html_webview_app_settings";
    static final String SERVER_URL_KEY = "server_url_preference";
    static final String SECURITY_TOKEN_KEY = "security_token_preference";
    static final String HA_ENABLED_KEY = "ha_enabled";
    static final String HA_TIMEOUT_KEY = "ha_timeout";
    static final String HA_URL2_KEY = "ha_url2";
    static final String HA_URL3_KEY = "ha_url3";
    static final String HA_URL4_KEY = "ha_url4";
    static final String BEACON_UUID_KEY = "beacon_uuid";
    static final String DEVICE_NAME_KEY = "device_name";
    static final String DEVICE_UUID_KEY = "device_uuid";
    static final String DEVICE_LOCATION_KEY = "device_location";
    static final String APP_CONFIG_KEY = "app_config_json";

    interface Preferences {
        String getString(String key, String fallback);

        boolean getBoolean(String key, boolean fallback);

        int getInt(String key, int fallback);

        Editor edit();

        interface Editor {
            Editor putString(String key, String value);

            Editor putBoolean(String key, boolean value);

            Editor putInt(String key, int value);

            void apply();
        }
    }

    private final Preferences preferences;
    private final String defaultServerUrl;
    private final String defaultSecurityToken;
    private final String defaultBeaconUUID;

    AndroidSettingsStore(
            Preferences preferences,
            String defaultServerUrl,
            String defaultSecurityToken,
            String defaultBeaconUUID
    ) {
        this.preferences = preferences;
        this.defaultServerUrl = nonEmpty(defaultServerUrl, "");
        this.defaultSecurityToken = nonEmpty(defaultSecurityToken, "");
        this.defaultBeaconUUID = nonEmpty(defaultBeaconUUID, "");
    }

    String configuredStartUrl(String localFallback) {
        String value = nonEmpty(preferences.getString(SERVER_URL_KEY, defaultServerUrl), defaultServerUrl);
        return StartupUrlResolver.resolveStartUrl(value, defaultServerUrl, localFallback);
    }

    ArrayList<String> startUrlCandidates(String localFallback) {
        return StartupUrlResolver.candidates(
                configuredStartUrl(localFallback),
                highAvailabilityEnabled(),
                preferences.getString(HA_URL2_KEY, ""),
                preferences.getString(HA_URL3_KEY, ""),
                preferences.getString(HA_URL4_KEY, ""),
                localFallback
        );
    }

    boolean highAvailabilityEnabled() {
        return preferences.getBoolean(HA_ENABLED_KEY, false);
    }

    long highAvailabilityTimeoutMs() {
        return Math.max(1, preferences.getInt(HA_TIMEOUT_KEY, 5)) * 1000L;
    }

    String securityToken() {
        return nonEmpty(preferences.getString(SECURITY_TOKEN_KEY, defaultSecurityToken), defaultSecurityToken);
    }

    String deviceName() {
        return nonEmpty(preferences.getString(DEVICE_NAME_KEY, ""), "");
    }

    String deviceUUID() {
        ensureDeviceUUID();
        return nonEmpty(preferences.getString(DEVICE_UUID_KEY, ""), "");
    }

    String deviceLocation() {
        return nonEmpty(preferences.getString(DEVICE_LOCATION_KEY, ""), "");
    }

    JSONObject snapshotPayload() throws JSONException {
        AndroidSettingsBridge.SettingsSnapshot snapshot = new AndroidSettingsBridge.SettingsSnapshot();
        snapshot.serverURL = nonEmpty(preferences.getString(SERVER_URL_KEY, defaultServerUrl), defaultServerUrl);
        snapshot.securityTokenSet = !securityToken().isEmpty();
        snapshot.highAvailabilityEnabled = highAvailabilityEnabled();
        snapshot.highAvailabilityTimeoutSeconds = preferences.getInt(HA_TIMEOUT_KEY, 5);
        snapshot.highAvailabilityURL2 = nonEmpty(preferences.getString(HA_URL2_KEY, ""), "");
        snapshot.highAvailabilityURL3 = nonEmpty(preferences.getString(HA_URL3_KEY, ""), "");
        snapshot.highAvailabilityURL4 = nonEmpty(preferences.getString(HA_URL4_KEY, ""), "");
        snapshot.beaconUUID = nonEmpty(preferences.getString(BEACON_UUID_KEY, defaultBeaconUUID), defaultBeaconUUID);
        snapshot.deviceName = deviceName();
        snapshot.deviceUUID = deviceUUID();
        snapshot.deviceLocation = deviceLocation();
        snapshot.appConfig = appConfig();
        return AndroidSettingsBridge.snapshotPayload(snapshot);
    }

    JSONObject apply(JSONObject values) throws JSONException {
        Preferences.Editor editor = preferences.edit();
        JSONObject source = values != null ? values : new JSONObject();
        putStringSetting(editor, source, SERVER_URL_KEY, "serverURL", "serverUrl", "defaultServerURL", "defaultServerUrl", "mobileURL", "mobileUrl", "url");
        putStringSetting(editor, source, HA_URL2_KEY, "highAvailabilityURL2", "haURL2", "ha_url2");
        putStringSetting(editor, source, HA_URL3_KEY, "highAvailabilityURL3", "haURL3", "ha_url3");
        putStringSetting(editor, source, HA_URL4_KEY, "highAvailabilityURL4", "haURL4", "ha_url4");
        putStringSetting(editor, source, BEACON_UUID_KEY, "beaconUUID", "beaconUuid", "beacon_uuid");
        putStringSetting(editor, source, DEVICE_NAME_KEY, "deviceName", "device_name", "name");
        putDeviceUUIDSetting(editor, source, "deviceUUID", "deviceUuid", "device_uuid", "uuid");
        putStringSetting(editor, source, DEVICE_LOCATION_KEY, "deviceLocation", "device_location", "location");
        putStringSetting(editor, source, SECURITY_TOKEN_KEY, "newSecurityToken", "securityToken");
        putBooleanSetting(editor, source, HA_ENABLED_KEY, "highAvailabilityEnabled", "haEnabled", "ha_enabled");
        putIntSetting(editor, source, HA_TIMEOUT_KEY, "highAvailabilityTimeoutSeconds", "haTimeout", "ha_timeout");
        putAppConfig(editor, source);
        editor.apply();
        ensureDeviceUUID();
        return snapshotPayload();
    }

    private JSONObject appConfig() {
        String raw = nonEmpty(preferences.getString(APP_CONFIG_KEY, "{}"), "{}");
        try {
            return new JSONObject(raw);
        } catch (JSONException ignored) {
            return new JSONObject();
        }
    }

    private void putAppConfig(Preferences.Editor editor, JSONObject source) throws JSONException {
        JSONObject incoming = source.optJSONObject("appConfig");
        if (incoming == null) {
            incoming = source.optJSONObject("app_config");
        }
        if (incoming == null) {
            incoming = source.optJSONObject("store");
        }
        if (incoming == null) {
            return;
        }

        JSONObject merged = appConfig();
        for (java.util.Iterator<String> it = incoming.keys(); it.hasNext(); ) {
            String key = it.next();
            Object value = incoming.opt(key);
            if (value != null && value != JSONObject.NULL) {
                merged.put(key, value);
            }
        }
        editor.putString(APP_CONFIG_KEY, merged.toString());
    }

    private void ensureDeviceUUID() {
        String value = nonEmpty(preferences.getString(DEVICE_UUID_KEY, ""), "");
        try {
            if (!value.isEmpty()) {
                UUID.fromString(value);
                return;
            }
        } catch (Exception ignored) {
            // Replace invalid persisted values with a usable UUID below.
        }
        preferences.edit().putString(DEVICE_UUID_KEY, randomDeviceUUID()).apply();
    }

    private String randomDeviceUUID() {
        return UUID.randomUUID().toString().toUpperCase(Locale.US);
    }

    private void putStringSetting(Preferences.Editor editor, JSONObject values, String prefKey, String... aliases) {
        String value = stringFromAliases(values, aliases);
        if (value != null) {
            editor.putString(prefKey, value.trim());
        }
    }

    private void putDeviceUUIDSetting(Preferences.Editor editor, JSONObject values, String... aliases) {
        String value = stringFromAliases(values, aliases);
        if (value == null) {
            return;
        }
        try {
            editor.putString(DEVICE_UUID_KEY, UUID.fromString(value.trim()).toString().toUpperCase(Locale.US));
        } catch (Exception ignored) {
            editor.putString(DEVICE_UUID_KEY, randomDeviceUUID());
        }
    }

    private void putBooleanSetting(Preferences.Editor editor, JSONObject values, String prefKey, String... aliases) {
        for (String alias : aliases) {
            if (!values.has(alias)) {
                continue;
            }
            Object value = values.opt(alias);
            if (value instanceof Boolean) {
                editor.putBoolean(prefKey, (Boolean) value);
                return;
            }
            String raw = String.valueOf(value).trim().toLowerCase(Locale.US);
            editor.putBoolean(prefKey, "1".equals(raw) || "true".equals(raw) || "yes".equals(raw) || "ja".equals(raw) || "on".equals(raw));
            return;
        }
    }

    private void putIntSetting(Preferences.Editor editor, JSONObject values, String prefKey, String... aliases) {
        String value = stringFromAliases(values, aliases);
        if (value == null) {
            return;
        }
        try {
            editor.putInt(prefKey, Math.max(1, Integer.parseInt(value.trim())));
        } catch (NumberFormatException ignored) {
            // Ignore invalid integer settings.
        }
    }

    private String stringFromAliases(JSONObject values, String... aliases) {
        for (String alias : aliases) {
            if (!values.has(alias)) {
                continue;
            }
            Object value = values.opt(alias);
            if (value == null || value == JSONObject.NULL) {
                return "";
            }
            return String.valueOf(value);
        }
        return null;
    }

    private static String nonEmpty(String value, String fallback) {
        if (value == null) {
            return fallback;
        }
        String trimmed = value.trim();
        return trimmed.isEmpty() ? fallback : trimmed;
    }
}
