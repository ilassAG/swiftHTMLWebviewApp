package com.ilass.swifthtmlwebviewapp;

import org.json.JSONException;
import org.json.JSONArray;
import org.json.JSONObject;

final class AndroidWifiBridge {
    static final class StatusSnapshot {
        JSONArray cidrs = new JSONArray();
        JSONArray ipAddresses = new JSONArray();
        boolean wifiServiceAvailable = true;
        boolean wifiEnabled = false;
        JSONArray wifiIpAddresses = new JSONArray();
        boolean connectionInfoAvailable = false;
        boolean hasWifiDetailsPermission = false;
        String ssid = "";
        String bssid = "";
        int rssi = 0;
        int linkSpeedMbps = 0;
        String ipAddress = "";
        int securityTypeRawValue = -1;
        String securityType = "unknown";
        String unavailableReason = "";
    }

    static final class ConfigureRequest {
        final JSONObject request;
        final String ssid;
        final String passphrase;

        private ConfigureRequest(JSONObject request, String ssid, String passphrase) {
            this.request = request;
            this.ssid = ssid;
            this.passphrase = passphrase;
        }
    }

    private AndroidWifiBridge() {
    }

    static ConfigureRequest configureRequest(JSONObject message, String persistedServerUrl) throws JSONException {
        JSONObject request = copyRequest(message);
        String ssid = request.optString("ssid", "").trim();
        String passphrase = request.optString("passphrase", request.optString("password", "")).trim();
        if (persistedServerUrl != null && !persistedServerUrl.trim().isEmpty()) {
            request.put("serverURL", persistedServerUrl.trim());
            request.put("serverURLPersisted", true);
        }
        return new ConfigureRequest(request, ssid, passphrase);
    }

    static JSONObject statusResponse(JSONObject request, JSONObject wifiPayload) throws JSONException {
        JSONObject response = BridgeResponse.base(request, "wifiStatusGet");
        response.put("success", true);
        response.put("wifi", wifiPayload);
        return response;
    }

    static JSONObject statusPayload(StatusSnapshot snapshot) throws JSONException {
        StatusSnapshot data = snapshot != null ? snapshot : new StatusSnapshot();
        JSONObject network = new JSONObject();
        network.put("cidrs", arrayOrEmpty(data.cidrs));
        network.put("ipAddresses", arrayOrEmpty(data.ipAddresses));
        network.put("ssidAvailable", false);
        network.put("ssid", "unavailable");
        network.put("securityType", "unknown");
        network.put("securityTypeRawValue", JSONObject.NULL);

        if (!data.wifiServiceAvailable) {
            network.put("wifiEnabled", false);
            network.put("wifiIpAddresses", new JSONArray());
            network.put("unavailableReason", reasonOrDefault(data.unavailableReason, "Wi-Fi service is not available."));
            return network;
        }

        network.put("wifiEnabled", data.wifiEnabled);
        network.put("wifiIpAddresses", arrayOrEmpty(data.wifiIpAddresses));
        if (!data.connectionInfoAvailable) {
            network.put("unavailableReason", reasonOrDefault(data.unavailableReason, "Android returned no Wi-Fi connection details."));
            return network;
        }

        String ssid = sanitizeWifiSsid(data.ssid);
        boolean ssidAvailable = data.hasWifiDetailsPermission && isRealWifiSsid(ssid);
        network.put("ssidAvailable", ssidAvailable);
        network.put("ssid", ssidAvailable ? ssid : "unavailable");
        network.put("bssid", data.bssid != null ? data.bssid : "");
        network.put("rssi", data.rssi);
        network.put("linkSpeedMbps", data.linkSpeedMbps);
        network.put("ipAddress", stringOrEmpty(data.ipAddress));

        if (data.securityTypeRawValue >= 0) {
            network.put("securityTypeRawValue", data.securityTypeRawValue);
            network.put("securityType", stringOrDefault(data.securityType, "unknown"));
        }

        if (!ssidAvailable) {
            String reason = data.hasWifiDetailsPermission
                    ? "Android did not expose the current SSID. The device may not be connected to Wi-Fi, location services may be disabled, or the OS returned a redacted SSID."
                    : "Location permission is required before Android exposes SSID/BSSID details to apps.";
            network.put("unavailableReason", reasonOrDefault(data.unavailableReason, reason));
        }
        return network;
    }

    static JSONObject missingSSIDResponse(JSONObject request) throws JSONException {
        return BridgeResponse.error(request, "wifiConfigure", "ssid is required.");
    }

    static JSONObject serviceUnavailableResponse(JSONObject request) throws JSONException {
        return BridgeResponse.error(request, "wifiConfigure", "Wi-Fi service is not available.");
    }

    static JSONObject configureErrorResponse(JSONObject request, String error) throws JSONException {
        return BridgeResponse.error(
                request,
                "wifiConfigure",
                error != null && !error.isEmpty() ? error : "Wi-Fi configuration failed."
        );
    }

    static JSONObject addNetworksResultResponse(JSONObject request, boolean userApproved) throws JSONException {
        JSONObject response = BridgeResponse.base(request, "wifiConfigure");
        response.put("success", userApproved);
        response.put("method", "ACTION_WIFI_ADD_NETWORKS");
        response.put("userApproved", userApproved);
        putServerUrlPersistence(response, request);
        if (!userApproved) {
            response.put("error", "The Wi-Fi add-network request was cancelled or denied.");
        }
        return response;
    }

    static JSONObject networkSuggestionResponse(JSONObject request, int status, boolean success) throws JSONException {
        JSONObject response = BridgeResponse.base(request, "wifiConfigure");
        response.put("success", success);
        response.put("method", "WifiNetworkSuggestion");
        response.put("status", status);
        putServerUrlPersistence(response, request);
        if (!success) {
            response.put("error", "Android rejected the Wi-Fi suggestion with status " + status + ".");
        }
        return response;
    }

    static JSONObject legacyConfigurationResponse(JSONObject request, int networkId, boolean enabled) throws JSONException {
        JSONObject response = BridgeResponse.base(request, "wifiConfigure");
        response.put("success", enabled);
        response.put("method", "WifiConfiguration");
        response.put("networkId", networkId);
        putServerUrlPersistence(response, request);
        if (!enabled) {
            response.put("error", "Could not add or enable the requested Wi-Fi network.");
        }
        return response;
    }

    static void putServerUrlPersistence(JSONObject response, JSONObject request) throws JSONException {
        if (request == null || !request.optBoolean("serverURLPersisted", false)) {
            return;
        }
        response.put("serverURL", request.optString("serverURL", ""));
        response.put("serverURLPersisted", true);
    }

    static String quoteWifiValue(String value) {
        String safeValue = value != null ? value : "";
        return "\"" + safeValue.replace("\"", "\\\"") + "\"";
    }

    static String sanitizeWifiSsid(String ssid) {
        if (ssid == null) {
            return "";
        }
        String trimmed = ssid.trim();
        if (trimmed.startsWith("\"") && trimmed.endsWith("\"") && trimmed.length() >= 2) {
            return trimmed.substring(1, trimmed.length() - 1);
        }
        return trimmed;
    }

    static boolean isRealWifiSsid(String ssid) {
        return ssid != null
                && !ssid.trim().isEmpty()
                && !"<unknown ssid>".equalsIgnoreCase(ssid.trim());
    }

    private static JSONObject copyRequest(JSONObject message) {
        try {
            return new JSONObject(message != null ? message.toString() : "{}");
        } catch (JSONException ignored) {
            return new JSONObject();
        }
    }

    private static JSONArray arrayOrEmpty(JSONArray value) {
        return value != null ? value : new JSONArray();
    }

    private static String stringOrEmpty(String value) {
        return value != null ? value : "";
    }

    private static String stringOrDefault(String value, String fallback) {
        return value != null && !value.trim().isEmpty() ? value : fallback;
    }

    private static String reasonOrDefault(String value, String fallback) {
        return value != null && !value.trim().isEmpty() ? value : fallback;
    }
}
