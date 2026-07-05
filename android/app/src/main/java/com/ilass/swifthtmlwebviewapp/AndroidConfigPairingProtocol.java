package com.ilass.swifthtmlwebviewapp;

import org.json.JSONException;
import org.json.JSONObject;

import java.net.URLDecoder;
import java.net.URLEncoder;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

final class AndroidConfigPairingProtocol {
    static final UUID SERVICE_UUID = UUID.fromString("6D8E0F22-9C2D-4E8E-A7D7-2B1D49F48A01");
    static final UUID COMMAND_UUID = UUID.fromString("6D8E0F22-9C2D-4E8E-A7D7-2B1D49F48A02");
    static final UUID RESPONSE_UUID = UUID.fromString("6D8E0F22-9C2D-4E8E-A7D7-2B1D49F48A03");
    static final int CHUNK_PAYLOAD_SIZE = 32;

    private AndroidConfigPairingProtocol() {
    }

    static String pairingPayload(String id, String secret, long expiresAtMs, JSONObject identity) {
        return "swifthtml-config://pair"
                + "?v=1"
                + "&id=" + urlEncode(id)
                + "&secret=" + urlEncode(secret)
                + "&service=" + urlEncode(SERVICE_UUID.toString())
                + "&expires=" + (expiresAtMs / 1000L)
                + "&name=" + urlEncode(identity.optString("name", ""))
                + "&appUUID=" + urlEncode(identity.optString("appUUID", ""))
                + "&deviceName=" + urlEncode(identity.optString("deviceName", ""))
                + "&deviceUUID=" + urlEncode(identity.optString("deviceUUID", ""))
                + "&deviceLocation=" + urlEncode(identity.optString("deviceLocation", ""));
    }

    static JSONObject identity(String name, String deviceName, String deviceUuid, String deviceLocation) throws JSONException {
        return identity(name, "", deviceName, deviceUuid, deviceLocation);
    }

    static JSONObject identity(String name, String appUuid, String deviceName, String deviceUuid, String deviceLocation) throws JSONException {
        JSONObject identity = new JSONObject();
        identity.put("name", nonEmpty(name, ""));
        identity.put("appUUID", nonEmpty(appUuid, ""));
        identity.put("deviceName", nonEmpty(deviceName, ""));
        identity.put("deviceUUID", nonEmpty(deviceUuid, ""));
        identity.put("deviceLocation", nonEmpty(deviceLocation, ""));
        return identity;
    }

    static JSONObject responsePayload(String command, String requestId, String sessionId) throws JSONException {
        JSONObject response = new JSONObject();
        response.put("action", "configPairingResponse");
        response.put("platform", "android");
        response.put("role", "target");
        response.put("command", command);
        response.put("requestId", nonEmpty(requestId, UUID.randomUUID().toString()));
        response.put("sessionId", nonEmpty(sessionId, ""));
        return response;
    }

    static JSONObject errorPayload(String command, String requestId, String error) {
        JSONObject response = new JSONObject();
        try {
            response.put("action", "configPairingResponse");
            response.put("platform", "android");
            response.put("role", "target");
            response.put("command", command);
            response.put("requestId", nonEmpty(requestId, UUID.randomUUID().toString()));
            response.put("success", false);
            response.put("error", error != null ? error : "Unknown config pairing error.");
        } catch (JSONException ignored) {
            // Return the partially built response.
        }
        return response;
    }

    static JSONObject eventPayload(String role, String event, boolean success, String error) throws JSONException {
        JSONObject payload = new JSONObject();
        payload.put("action", "configPairingEvent");
        payload.put("platform", "android");
        payload.put("role", role);
        payload.put("event", event);
        payload.put("success", success);
        if (error != null && !error.isEmpty()) {
            payload.put("error", error);
        }
        return payload;
    }

    static JSONObject showResponse(JSONObject request, String payload, long expiresAtMs, JSONObject identity) throws JSONException {
        JSONObject response = BridgeResponse.base(request, "configPairingShow");
        response.put("success", true);
        response.put("payload", payload);
        response.put("expiresAt", expiresAtMs / 1000L);
        response.put("transport", "ble-gatt");
        response.put("serviceUUID", SERVICE_UUID.toString());
        response.put("targetIdentity", identity);
        response.put("appUUID", identity.optString("appUUID", ""));
        response.put("deviceName", identity.optString("deviceName", ""));
        response.put("deviceUUID", identity.optString("deviceUUID", ""));
        response.put("deviceLocation", identity.optString("deviceLocation", ""));
        return response;
    }

    static JSONObject acknowledgementResponse(JSONObject request, String action) throws JSONException {
        JSONObject response = BridgeResponse.base(request, action);
        response.put("success", true);
        return response;
    }

    static JSONObject connectResponse(JSONObject request, PairingTarget target) throws JSONException {
        JSONObject response = BridgeResponse.base(request, "configPairingConnect");
        response.put("success", true);
        response.put("state", "scanning");
        response.put("serviceUUID", target.serviceUuid.toString());
        response.put("targetName", target.name);
        response.put("targetIdentity", target.identityPayload());
        response.put("appUUID", target.appUuid);
        response.put("deviceName", target.deviceName);
        response.put("deviceUUID", target.deviceUuid);
        response.put("deviceLocation", target.deviceLocation);
        return response;
    }

    static JSONObject sendResponse(JSONObject request, boolean started, int bytes, int chunks, String command, String error) throws JSONException {
        JSONObject response = BridgeResponse.base(request, "configPairingSend");
        response.put("success", started);
        response.put("state", started ? (chunks > 1 ? "sentInChunks" : "sent") : "writeFailed");
        response.put("bytes", bytes);
        response.put("chunks", chunks);
        response.put("command", command);
        if (!started && error != null && !error.isEmpty()) {
            response.put("error", error);
        }
        return response;
    }

    static JSONObject errorResponse(JSONObject request, String action, String error) throws JSONException {
        return BridgeResponse.error(request, action, error);
    }

    static JSONObject unknownActionResponse(JSONObject request) throws JSONException {
        String action = request.optString("action", "");
        return errorResponse(request, action, "Unknown config pairing action: " + action);
    }

    static JSONObject commandFromRequest(PairingTarget target, JSONObject request) throws JSONException {
        JSONObject command = new JSONObject();
        command.put("sessionId", target.sessionId);
        command.put("secret", target.secret);
        command.put("requestId", nonEmpty(request.optString("requestId", ""), UUID.randomUUID().toString()));
        command.put("command", nonEmpty(request.optString("command", request.optString("configCommand", "")), "statusGet"));
        String token = request.optString("token", request.optString("securityToken", "")).trim();
        if (!token.isEmpty()) {
            command.put("token", token);
        }
        if (request.has("settings")) {
            command.put("settings", request.getJSONObject("settings"));
        }
        String ssid = request.optString("ssid", "").trim();
        if (!ssid.isEmpty()) {
            command.put("ssid", ssid);
        }
        String passphrase = request.optString("passphrase", request.optString("password", "")).trim();
        if (!passphrase.isEmpty()) {
            command.put("passphrase", passphrase);
        }
        if (request.has("joinOnce")) {
            command.put("joinOnce", request.optBoolean("joinOnce"));
        }
        return command;
    }

    static JSONObject internalRequest(String action, String source) throws JSONException {
        JSONObject request = new JSONObject();
        request.put("action", nonEmpty(action, ""));
        String safeSource = nonEmpty(source, "");
        if (!safeSource.isEmpty()) {
            request.put("source", safeSource);
        }
        return request;
    }

    static boolean isValidChunkEnvelope(JSONObject object) {
        String chunkId = object.optString("id", "");
        int index = object.optInt("i", -1);
        int count = object.optInt("n", 0);
        String encoded = object.optString("d", "");
        return !chunkId.isEmpty() && index >= 0 && count > 0 && index < count && !encoded.isEmpty();
    }

    static String nonEmpty(String value, String fallback) {
        String trimmed = value != null ? value.trim() : "";
        return trimmed.isEmpty() ? fallback : trimmed;
    }

    private static String urlEncode(String value) {
        try {
            return URLEncoder.encode(value != null ? value : "", "UTF-8").replace("+", "%20");
        } catch (Exception ignored) {
            return "";
        }
    }

    private static String urlDecode(String value) {
        try {
            return URLDecoder.decode(value != null ? value : "", "UTF-8");
        } catch (Exception ignored) {
            return "";
        }
    }

    static final class PairingTarget {
        final String sessionId;
        final String secret;
        final UUID serviceUuid;
        final String name;
        final String appUuid;
        final String deviceName;
        final String deviceUuid;
        final String deviceLocation;

        private PairingTarget(String sessionId, String secret, UUID serviceUuid, String name, String appUuid, String deviceName, String deviceUuid, String deviceLocation) {
            this.sessionId = sessionId;
            this.secret = secret;
            this.serviceUuid = serviceUuid;
            this.name = name;
            this.appUuid = appUuid;
            this.deviceName = deviceName;
            this.deviceUuid = deviceUuid;
            this.deviceLocation = deviceLocation;
        }

        JSONObject identityPayload() throws JSONException {
            return identity(name, appUuid, deviceName, deviceUuid, deviceLocation);
        }

        static PairingTarget parse(String payload) {
            if (payload == null || !payload.startsWith("swifthtml-config://pair")) {
                return null;
            }
            String query = "";
            int index = payload.indexOf('?');
            if (index >= 0 && index + 1 < payload.length()) {
                query = payload.substring(index + 1);
            }
            JSONObject values = new JSONObject();
            for (String part : query.split("&")) {
                int separator = part.indexOf('=');
                if (separator <= 0) {
                    continue;
                }
                try {
                    values.put(urlDecode(part.substring(0, separator)), urlDecode(part.substring(separator + 1)));
                } catch (JSONException ignored) {
                    // Skip malformed query parts.
                }
            }
            String id = values.optString("id", "");
            String secret = values.optString("secret", "");
            if (id.isEmpty() || secret.isEmpty()) {
                return null;
            }
            UUID serviceUuid = SERVICE_UUID;
            try {
                serviceUuid = UUID.fromString(values.optString("service", SERVICE_UUID.toString()).toUpperCase(Locale.US));
            } catch (Exception ignored) {
                // Use default service UUID.
            }
            String appUuid = values.optString("appUUID", values.optString("appUuid", values.optString("app_uuid", "")));
            String deviceName = values.optString("deviceName", values.optString("device_name", ""));
            String deviceUuid = values.optString("deviceUUID", values.optString("deviceUuid", values.optString("device_uuid", "")));
            String deviceLocation = values.optString("deviceLocation", values.optString("device_location", ""));
            String name = deviceName.isEmpty() ? values.optString("name", "") : deviceName;
            return new PairingTarget(id, secret, serviceUuid, name, appUuid, deviceName, deviceUuid, deviceLocation);
        }
    }

    static final class ChunkAccumulator {
        final int count;
        final Map<Integer, byte[]> chunks = new HashMap<>();

        ChunkAccumulator(int count) {
            this.count = count;
        }

        boolean isComplete() {
            return chunks.size() == count;
        }

        byte[] assembled() {
            int total = 0;
            for (int index = 0; index < count; index += 1) {
                byte[] chunk = chunks.get(index);
                if (chunk != null) {
                    total += chunk.length;
                }
            }
            byte[] data = new byte[total];
            int offset = 0;
            for (int index = 0; index < count; index += 1) {
                byte[] chunk = chunks.get(index);
                if (chunk == null) {
                    continue;
                }
                System.arraycopy(chunk, 0, data, offset, chunk.length);
                offset += chunk.length;
            }
            return data;
        }
    }
}
