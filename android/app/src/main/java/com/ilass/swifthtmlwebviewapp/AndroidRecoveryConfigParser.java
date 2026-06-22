package com.ilass.swifthtmlwebviewapp;

import org.json.JSONException;
import org.json.JSONObject;

import java.net.URI;
import java.net.URISyntaxException;
import java.util.Locale;

final class AndroidRecoveryConfigParser {
    private AndroidRecoveryConfigParser() {
    }

    static String serverUrlFromCode(String code) {
        String trimmed = nonEmpty(code, "");
        if (trimmed.isEmpty()) {
            return "";
        }

        String directUrl = normalizedMobileUrl(trimmed, "");
        if (!directUrl.isEmpty()) {
            return directUrl;
        }

        try {
            return serverUrlFromPayload(new JSONObject(trimmed));
        } catch (JSONException ignored) {
            return "";
        }
    }

    static String serverUrlFromPayload(JSONObject payload) {
        String serverUrl = nonEmpty(stringFromAliases(
                payload,
                "serverURL",
                "serverUrl",
                "defaultServerURL",
                "defaultServerUrl",
                "mobileURL",
                "mobileUrl",
                "url"
        ), "");
        String linkId = payload != null ? payload.optString("linkId", "") : "";
        serverUrl = normalizedMobileUrl(serverUrl, linkId);
        if (!serverUrl.isEmpty()) {
            return serverUrl;
        }

        String backendUrl = nonEmpty(stringFromAliases(payload, "backendURL", "backendUrl"), "");
        return mobileUrlFromBackend(backendUrl, linkId);
    }

    static String mobileUrlFromBackend(String backendUrl, String linkId) {
        return normalizedMobileUrl(backendUrl, linkId);
    }

    private static String normalizedMobileUrl(String value, String linkId) {
        String trimmed = nonEmpty(value, "");
        if (trimmed.isEmpty()) {
            return "";
        }
        try {
            URI uri = new URI(trimmed);
            String scheme = uri.getScheme() != null ? uri.getScheme().toLowerCase(Locale.US) : "";
            if (!"http".equals(scheme) && !"https".equals(scheme)) {
                return "";
            }
            if (uri.getHost() == null || uri.getHost().trim().isEmpty()) {
                return "";
            }

            String path = uri.getPath() != null ? uri.getPath() : "";
            if (path.isEmpty() || "/".equals(path)) {
                path = "/mobile/";
            }

            String query = uri.getQuery();
            if (!hasQueryParameter(query, "link")) {
                String trimmedLinkId = nonEmpty(linkId, "");
                if (!trimmedLinkId.isEmpty()) {
                    query = appendQueryParameter(query, "link", trimmedLinkId);
                }
            }

            return new URI(
                    uri.getScheme(),
                    uri.getUserInfo(),
                    uri.getHost(),
                    uri.getPort(),
                    path,
                    query,
                    null
            ).toString();
        } catch (URISyntaxException | IllegalArgumentException ignored) {
            return "";
        }
    }

    private static boolean hasQueryParameter(String query, String name) {
        if (query == null || query.isEmpty()) {
            return false;
        }
        String prefix = name + "=";
        for (String item : query.split("&")) {
            if (item.equals(name) || item.startsWith(prefix)) {
                return true;
            }
        }
        return false;
    }

    private static String appendQueryParameter(String query, String name, String value) {
        String item = name + "=" + value;
        if (query == null || query.isEmpty()) {
            return item;
        }
        return query + "&" + item;
    }

    private static String stringFromAliases(JSONObject values, String... aliases) {
        if (values == null) {
            return null;
        }
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
