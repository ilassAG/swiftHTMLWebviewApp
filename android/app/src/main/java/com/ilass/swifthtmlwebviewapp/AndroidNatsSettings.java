package com.ilass.swifthtmlwebviewapp;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.net.URI;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

final class AndroidNatsSettings {
    static final List<String> DEFAULT_URLS = Collections.emptyList();

    boolean enabled = false;
    ArrayList<String> urls = new ArrayList<>();
    boolean tlsFirst = true;
    String clientNameTemplate = "swift-wrapper-${appUUID}";
    String identitySource = "appUUID";
    String authMethod = "creds";
    int maxReconnects = -1;
    int reconnectWaitMs = 500;
    int pingIntervalSeconds = 10;
    String namespace = "swift.wrapper";
    String devicePrefixTemplate = "swift.wrapper.${appUUID}";
    String commandSubjectTemplate = "swift.wrapper.${appUUID}.commands.*";
    String responseSubjectTemplate = "swift.wrapper.${appUUID}.events.responses";
    String statusSubjectTemplate = "swift.wrapper.${appUUID}.status";

    static AndroidNatsSettings fromStoredJson(String rawValue) {
        if (rawValue == null || rawValue.trim().isEmpty()) {
            return new AndroidNatsSettings();
        }
        try {
            return fromPayload(new JSONObject(rawValue), new AndroidNatsSettings());
        } catch (JSONException ignored) {
            return new AndroidNatsSettings();
        }
    }

    static AndroidNatsSettings fromPayload(JSONObject payload, AndroidNatsSettings fallback) throws JSONException {
        JSONObject source = payload != null && payload.has("nats") && payload.optJSONObject("nats") != null
                ? payload.optJSONObject("nats")
                : payload;
        AndroidNatsSettings settings = copyOf(fallback != null ? fallback : new AndroidNatsSettings());

        if (source == null) {
            return settings;
        }
        if (source.has("enabled")) {
            settings.enabled = boolValue(source.opt("enabled"), settings.enabled);
        }
        if (source.has("urls")) {
            settings.urls = normalizeUrls(source.opt("urls"), settings.enabled);
        } else if (settings.enabled && settings.urls.isEmpty()) {
            settings.urls = new ArrayList<>(DEFAULT_URLS);
        }
        if (source.has("tlsFirst") || source.has("tls_first")) {
            settings.tlsFirst = boolValue(source.opt("tlsFirst"), boolValue(source.opt("tls_first"), settings.tlsFirst));
        }
        settings.clientNameTemplate = nonEmpty(source.optString("clientNameTemplate", source.optString("client_name_template", settings.clientNameTemplate)), settings.clientNameTemplate);
        settings.identitySource = nonEmpty(source.optString("identitySource", source.optString("identity_source", settings.identitySource)), settings.identitySource);

        JSONObject auth = source.optJSONObject("auth");
        if (auth != null && auth.has("method")) {
            settings.authMethod = normalizeAuthMethod(auth.optString("method"));
        } else if (source.has("authMethod") || source.has("auth_method")) {
            settings.authMethod = normalizeAuthMethod(source.optString("authMethod", source.optString("auth_method", settings.authMethod)));
        }

        JSONObject reconnect = source.optJSONObject("reconnect");
        if (reconnect != null) {
            settings.maxReconnects = Math.max(-1, intValue(reconnect.opt("maxReconnects"), intValue(reconnect.opt("max_reconnects"), settings.maxReconnects)));
            settings.reconnectWaitMs = Math.max(100, Math.min(60000, intValue(reconnect.opt("reconnectWaitMs"), intValue(reconnect.opt("reconnect_wait_ms"), settings.reconnectWaitMs))));
            settings.pingIntervalSeconds = Math.max(1, Math.min(300, intValue(reconnect.opt("pingIntervalSeconds"), intValue(reconnect.opt("ping_interval_seconds"), settings.pingIntervalSeconds))));
        }

        JSONObject subjects = source.optJSONObject("subjects");
        if (subjects != null) {
            settings.namespace = nonEmpty(subjects.optString("namespace", settings.namespace), settings.namespace);
            settings.devicePrefixTemplate = nonEmpty(subjects.optString("devicePrefixTemplate", subjects.optString("device_prefix_template", settings.devicePrefixTemplate)), settings.devicePrefixTemplate);
            settings.commandSubjectTemplate = nonEmpty(subjects.optString("commandSubjectTemplate", subjects.optString("command_subject_template", settings.commandSubjectTemplate)), settings.commandSubjectTemplate);
            settings.responseSubjectTemplate = nonEmpty(subjects.optString("responseSubjectTemplate", subjects.optString("response_subject_template", settings.responseSubjectTemplate)), settings.responseSubjectTemplate);
            settings.statusSubjectTemplate = nonEmpty(subjects.optString("statusSubjectTemplate", subjects.optString("status_subject_template", settings.statusSubjectTemplate)), settings.statusSubjectTemplate);
        }
        return settings;
    }

    JSONObject toStoredJson() throws JSONException {
        JSONObject object = new JSONObject();
        object.put("enabled", enabled);
        object.put("urls", new JSONArray(urls));
        object.put("tlsFirst", tlsFirst);
        object.put("clientNameTemplate", clientNameTemplate);
        object.put("identitySource", identitySource);
        object.put("auth", new JSONObject().put("method", authMethod));
        object.put("reconnect", new JSONObject()
                .put("maxReconnects", maxReconnects)
                .put("reconnectWaitMs", reconnectWaitMs)
                .put("pingIntervalSeconds", pingIntervalSeconds));
        object.put("subjects", new JSONObject()
                .put("namespace", namespace)
                .put("devicePrefixTemplate", devicePrefixTemplate)
                .put("commandSubjectTemplate", commandSubjectTemplate)
                .put("responseSubjectTemplate", responseSubjectTemplate)
                .put("statusSubjectTemplate", statusSubjectTemplate));
        return object;
    }

    JSONObject redactedSnapshot(String appUUID, boolean credentialSet, boolean connected, String lastError) throws JSONException {
        JSONObject snapshot = new JSONObject();
        snapshot.put("enabled", enabled);
        snapshot.put("urls", new JSONArray(urls));
        snapshot.put("tlsFirst", tlsFirst);
        snapshot.put("clientName", clientName(appUUID));
        snapshot.put("identitySource", identitySource);
        snapshot.put("auth", new JSONObject()
                .put("method", authMethod)
                .put("credentialSet", credentialSet));
        snapshot.put("connected", connected);
        snapshot.put("lastError", lastError != null ? lastError : "");
        snapshot.put("subjects", new JSONObject()
                .put("namespace", namespace)
                .put("devicePrefix", devicePrefix(appUUID))
                .put("commandSubject", commandSubject(appUUID))
                .put("responseSubject", responseSubject(appUUID))
                .put("statusSubject", statusSubject(appUUID)));
        return snapshot;
    }

    boolean authRequiresSecret() {
        return !"none".equals(authMethod);
    }

    String clientName(String appUUID) {
        return replaceAppUUID(clientNameTemplate, appUUID);
    }

    String devicePrefix(String appUUID) {
        return replaceAppUUID(devicePrefixTemplate, appUUID);
    }

    String commandSubject(String appUUID) {
        return replaceAppUUID(commandSubjectTemplate, appUUID);
    }

    String responseSubject(String appUUID) {
        return replaceAppUUID(responseSubjectTemplate, appUUID);
    }

    String statusSubject(String appUUID) {
        return replaceAppUUID(statusSubjectTemplate, appUUID);
    }

    private static AndroidNatsSettings copyOf(AndroidNatsSettings source) {
        AndroidNatsSettings settings = new AndroidNatsSettings();
        settings.enabled = source.enabled;
        settings.urls = new ArrayList<>(source.urls);
        settings.tlsFirst = source.tlsFirst;
        settings.clientNameTemplate = source.clientNameTemplate;
        settings.identitySource = source.identitySource;
        settings.authMethod = source.authMethod;
        settings.maxReconnects = source.maxReconnects;
        settings.reconnectWaitMs = source.reconnectWaitMs;
        settings.pingIntervalSeconds = source.pingIntervalSeconds;
        settings.namespace = source.namespace;
        settings.devicePrefixTemplate = source.devicePrefixTemplate;
        settings.commandSubjectTemplate = source.commandSubjectTemplate;
        settings.responseSubjectTemplate = source.responseSubjectTemplate;
        settings.statusSubjectTemplate = source.statusSubjectTemplate;
        return settings;
    }

    private static ArrayList<String> normalizeUrls(Object value, boolean useDefaultsWhenEmpty) throws JSONException {
        ArrayList<String> urls = new ArrayList<>();
        if (value instanceof JSONArray) {
            JSONArray array = (JSONArray) value;
            for (int i = 0; i < array.length(); i++) {
                String item = nonEmpty(array.optString(i), "");
                if (!item.isEmpty()) {
                    urls.add(item);
                }
            }
        } else if (value != null && value != JSONObject.NULL) {
            for (String item : String.valueOf(value).split(",")) {
                String trimmed = item.trim();
                if (!trimmed.isEmpty()) {
                    urls.add(trimmed);
                }
            }
        }
        if (urls.isEmpty()) {
            return new ArrayList<>(useDefaultsWhenEmpty ? DEFAULT_URLS : new ArrayList<String>());
        }
        for (String url : urls) {
            try {
                URI uri = URI.create(url);
                String scheme = uri.getScheme() != null ? uri.getScheme().toLowerCase(Locale.US) : "";
                if (!Arrays.asList("nats", "tls", "ws", "wss").contains(scheme) || uri.getHost() == null) {
                    throw new IllegalArgumentException();
                }
            } catch (Exception error) {
                throw new JSONException("Invalid NATS URL: " + url);
            }
        }
        return urls;
    }

    private static String normalizeAuthMethod(String rawValue) throws JSONException {
        String value = nonEmpty(rawValue, "").toLowerCase(Locale.US);
        if ("userpassword".equals(value)) {
            return "userPassword";
        }
        if ("tlscertificate".equals(value)) {
            return "tlsCertificate";
        }
        if (Arrays.asList("none", "token", "nkey", "creds").contains(value)) {
            return value;
        }
        throw new JSONException("Invalid NATS auth method.");
    }

    private static String replaceAppUUID(String value, String appUUID) {
        String safeUUID = appUUID != null ? appUUID : "";
        return (value != null ? value : "")
                .replace("${appUUID}", safeUUID)
                .replace("{appUUID}", safeUUID);
    }

    private static boolean boolValue(Object value, boolean fallback) {
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        if (value instanceof Number) {
            return ((Number) value).intValue() != 0;
        }
        if (value == null || value == JSONObject.NULL) {
            return fallback;
        }
        String raw = String.valueOf(value).trim().toLowerCase(Locale.US);
        if (Arrays.asList("1", "true", "yes", "ja", "on").contains(raw)) {
            return true;
        }
        if (Arrays.asList("0", "false", "no", "nein", "off").contains(raw)) {
            return false;
        }
        return fallback;
    }

    private static int intValue(Object value, int fallback) {
        if (value instanceof Number) {
            return ((Number) value).intValue();
        }
        try {
            return Integer.parseInt(String.valueOf(value).trim());
        } catch (Exception ignored) {
            return fallback;
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
