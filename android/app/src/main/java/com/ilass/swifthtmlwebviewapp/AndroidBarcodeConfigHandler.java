package com.ilass.swifthtmlwebviewapp;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.UnsupportedEncodingException;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

final class AndroidBarcodeConfigHandler {
    private static final Set<String> KNOWN_SETTING_KEYS = new HashSet<>(Arrays.asList(
            "serverURL", "serverUrl", "defaultServerURL", "defaultServerUrl", "mobileURL", "mobileUrl", "url",
            "highAvailabilityEnabled", "haEnabled", "ha_enabled",
            "highAvailabilityTimeoutSeconds", "haTimeout", "ha_timeout",
            "highAvailabilityURL2", "haURL2", "ha_url2",
            "highAvailabilityURL3", "haURL3", "ha_url3",
            "highAvailabilityURL4", "haURL4", "ha_url4",
            "beaconUUID", "beaconUuid", "beacon_uuid",
            "deviceName", "device_name", "name",
            "deviceUUID", "deviceUuid", "device_uuid", "uuid",
            "deviceLocation", "device_location", "location",
            "newSecurityToken"
    ));
    private static final Set<String> RESERVED_QUERY_KEYS = new HashSet<>(Arrays.asList(
            "action", "command", "toolmode", "token", "securityToken", "link", "linkId"
    ));

    enum Kind {
        STANDARD_BARCODE,
        CONFIG_CHANGE,
        RECOVERY_SERVER_URL
    }

    static final class Result {
        final Kind kind;
        final JSONObject settings;
        final String serverUrl;
        final JSONObject wifiRequest;

        private Result(Kind kind, JSONObject settings, String serverUrl, JSONObject wifiRequest) {
            this.kind = kind;
            this.settings = settings != null ? settings : new JSONObject();
            this.serverUrl = serverUrl != null ? serverUrl : "";
            this.wifiRequest = wifiRequest != null ? wifiRequest : new JSONObject();
        }

        static Result standard() {
            return new Result(Kind.STANDARD_BARCODE, new JSONObject(), "", new JSONObject());
        }

        static Result configChange(JSONObject settings, JSONObject wifiRequest) {
            return new Result(Kind.CONFIG_CHANGE, settings, "", wifiRequest);
        }

        static Result recoveryServerUrl(String serverUrl) throws JSONException {
            JSONObject settings = new JSONObject();
            settings.put("serverURL", serverUrl != null ? serverUrl : "");
            return new Result(Kind.RECOVERY_SERVER_URL, settings, serverUrl, new JSONObject());
        }

        boolean hasWifiRequest() {
            return wifiRequest.length() > 0 && !wifiRequest.optString("ssid", "").trim().isEmpty();
        }
    }

    private AndroidBarcodeConfigHandler() {
    }

    static Result evaluate(String code, boolean recoverySource, String currentSecurityToken) throws JSONException {
        String safeCode = nonEmpty(code, "");
        if (safeCode.isEmpty()) {
            return Result.standard();
        }

        Result configChange = configChangeResult(safeCode, currentSecurityToken);
        if (configChange.kind == Kind.CONFIG_CHANGE) {
            return configChange;
        }

        if (recoverySource) {
            String serverUrl = AndroidRecoveryConfigParser.serverUrlFromCode(safeCode);
            if (!serverUrl.isEmpty()) {
                return Result.recoveryServerUrl(serverUrl);
            }
        }

        return Result.standard();
    }

    private static Result configChangeResult(String code, String currentSecurityToken) throws JSONException {
        Result queryConfig = queryConfigResult(code, currentSecurityToken);
        if (queryConfig.kind == Kind.CONFIG_CHANGE) {
            return queryConfig;
        }

        JSONObject config;
        try {
            config = new JSONObject(code);
        } catch (JSONException ignored) {
            return Result.standard();
        }

        if (!isConfigJson(config)) {
            return Result.standard();
        }

        String scannedToken = config.optString("token", config.optString("securityToken", "")).trim();
        if (scannedToken.isEmpty() || !scannedToken.equals(nonEmpty(currentSecurityToken, ""))) {
            throw new JSONException("Security token mismatch.");
        }

        JSONObject settings = config.optJSONObject("settings");
        if (settings == null) {
            settings = new JSONObject();
        }
        for (String key : KNOWN_SETTING_KEYS) {
            if (!settings.has(key) && config.has(key)) {
                settings.put(key, config.opt(key));
            }
        }
        mergeObject(settings, "appConfig", config.optJSONObject("appConfig"));
        mergeObject(settings, "appConfig", config.optJSONObject("app_config"));
        mergeObject(settings, "appConfig", config.optJSONObject("store"));

        String defaultServerUrl = config.optString("defaultServerUrl", "").trim();
        if (!defaultServerUrl.isEmpty() && !settings.has("serverURL")) {
            settings.put("serverURL", defaultServerUrl);
        }
        JSONObject wifiRequest = wifiRequest(config.optJSONObject("wifi"));
        if (settings.length() == 0 && wifiRequest.length() == 0) {
            return Result.standard();
        }
        return Result.configChange(settings, wifiRequest);
    }

    private static Result queryConfigResult(String code, String currentSecurityToken) throws JSONException {
        String query = queryString(code);
        if (query.isEmpty()) {
            return Result.standard();
        }

        JSONObject settings = new JSONObject();
        JSONObject appConfig = new JSONObject();
        JSONObject looseAppConfig = new JSONObject();
        JSONObject wifi = new JSONObject();
        String scannedToken = "";
        boolean sawConfigMarker = false;

        for (String pair : query.split("&")) {
            if (pair.trim().isEmpty()) {
                continue;
            }
            String[] parts = pair.split("=", 2);
            String name = decode(parts[0]).trim();
            String value = parts.length > 1 ? decode(parts[1]).trim() : "";
            if (name.isEmpty()) {
                continue;
            }

            if ("toolmode".equals(name) && "changeConfig".equals(value)) {
                sawConfigMarker = true;
            } else if ("token".equals(name) || "securityToken".equals(name)) {
                scannedToken = value;
                sawConfigMarker = true;
            } else if (bracketKey(name, "wifi") != null) {
                wifi.put(normalizedWifiKey(bracketKey(name, "wifi")), value);
                sawConfigMarker = true;
            } else if (bracketKey(name, "store") != null) {
                appConfig.put(bracketKey(name, "store"), value);
                sawConfigMarker = true;
            } else if (bracketKey(name, "appConfig") != null) {
                appConfig.put(bracketKey(name, "appConfig"), value);
                sawConfigMarker = true;
            } else if (KNOWN_SETTING_KEYS.contains(name)) {
                settings.put(name, value);
                sawConfigMarker = true;
            } else if (!RESERVED_QUERY_KEYS.contains(name)) {
                looseAppConfig.put(name, value);
            }
        }

        if (sawConfigMarker || !scannedToken.isEmpty()) {
            for (java.util.Iterator<String> it = looseAppConfig.keys(); it.hasNext(); ) {
                String key = it.next();
                appConfig.put(key, looseAppConfig.opt(key));
            }
        }

        if (appConfig.length() > 0) {
            settings.put("appConfig", appConfig);
        }
        JSONObject wifiRequest = wifiRequest(wifi);
        if (!sawConfigMarker && settings.length() == 0 && wifiRequest.length() == 0) {
            return Result.standard();
        }
        if (settings.length() == 0 && wifiRequest.length() == 0) {
            return Result.standard();
        }
        if (scannedToken.isEmpty() || !scannedToken.equals(nonEmpty(currentSecurityToken, ""))) {
            throw new JSONException("Security token mismatch.");
        }
        return Result.configChange(settings, wifiRequest);
    }

    private static boolean isConfigJson(JSONObject config) {
        if ("changeConfig".equals(config.optString("toolmode", ""))) {
            return true;
        }
        if (config.optJSONObject("settings") != null || config.optJSONObject("appConfig") != null || config.optJSONObject("app_config") != null || config.optJSONObject("store") != null || config.optJSONObject("wifi") != null) {
            return true;
        }
        if (!config.optString("token", config.optString("securityToken", "")).trim().isEmpty()) {
            for (String key : KNOWN_SETTING_KEYS) {
                if (config.has(key)) {
                    return true;
                }
            }
        }
        return false;
    }

    private static void mergeObject(JSONObject target, String key, JSONObject incoming) throws JSONException {
        if (incoming == null || incoming.length() == 0) {
            return;
        }
        JSONObject merged = target.optJSONObject(key);
        if (merged == null) {
            merged = new JSONObject();
        }
        for (java.util.Iterator<String> it = incoming.keys(); it.hasNext(); ) {
            String itemKey = it.next();
            merged.put(itemKey, incoming.opt(itemKey));
        }
        target.put(key, merged);
    }

    private static JSONObject wifiRequest(JSONObject wifi) throws JSONException {
        JSONObject request = new JSONObject();
        if (wifi == null || wifi.length() == 0) {
            return request;
        }
        String ssid = wifi.optString("ssid", wifi.optString("SSID", "")).trim();
        if (ssid.isEmpty()) {
            return request;
        }
        request.put("action", "wifiConfigure");
        request.put("source", "qr");
        request.put("ssid", ssid);
        String password = wifi.optString("passphrase", wifi.optString("password", wifi.optString("pw", wifi.optString("pass", "")))).trim();
        if (!password.isEmpty()) {
            request.put("password", password);
        }
        if (wifi.has("joinOnce")) {
            request.put("joinOnce", wifi.opt("joinOnce"));
        }
        return request;
    }

    private static String queryString(String code) {
        String trimmed = nonEmpty(code, "");
        int questionIndex = trimmed.indexOf('?');
        if (questionIndex >= 0) {
            return trimmed.substring(questionIndex + 1);
        }
        return trimmed.contains("=") ? trimmed.replaceFirst("^[?&]+", "") : "";
    }

    private static String bracketKey(String name, String prefix) {
        String marker = prefix + "[";
        if (!name.startsWith(marker) || !name.endsWith("]")) {
            return null;
        }
        String key = name.substring(marker.length(), name.length() - 1).trim();
        return key.isEmpty() ? null : key;
    }

    private static String normalizedWifiKey(String key) {
        if ("pw".equals(key) || "pass".equals(key) || "password".equals(key)) {
            return "password";
        }
        return key;
    }

    private static String decode(String value) {
        try {
            return URLDecoder.decode(value, StandardCharsets.UTF_8.name());
        } catch (UnsupportedEncodingException ignored) {
            return value;
        }
    }

    private static String nonEmpty(String value, String fallback) {
        if (value == null) {
            return fallback;
        }
        String trimmed = value.trim();
        return trimmed.isEmpty() ? fallback : trimmed;
    }
}
