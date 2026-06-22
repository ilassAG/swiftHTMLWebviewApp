package com.ilass.swifthtmlwebviewapp;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.UUID;

final class AndroidBeaconPayload {
    static final String DEFAULT_BEACON_UUID = "7763A937-B779-4D31-A20C-49E83047048F";
    static final int DEFAULT_MAJOR = 1;
    static final int DEFAULT_MINOR = 1;
    static final int DEFAULT_TX_POWER = -59;
    static final String RANGING_PROVIDER = "android_altbeacon";
    static final String ADVERTISER_PROVIDER = "android_altbeacon_transmitter";

    private AndroidBeaconPayload() {
    }

    static JSONObject rangingStartResponse(JSONObject request, String uuid) throws JSONException {
        JSONObject response = BridgeResponse.base(request, "beaconsStart");
        response.put("success", true);
        response.put("uuid", normalizedUUID(uuid));
        response.put("provider", RANGING_PROVIDER);
        return response;
    }

    static JSONObject rangingStopResponse(JSONObject request) throws JSONException {
        JSONObject response = BridgeResponse.base(request, "beaconsStop");
        response.put("success", true);
        return response;
    }

    static JSONObject beaconsEvent(String uuid, JSONArray beacons, JSONObject legacyBeacons, long timestampMs) throws JSONException {
        JSONArray safeBeacons = beacons != null ? beacons : new JSONArray();
        JSONObject event = new JSONObject();
        event.put("platform", "android");
        event.put("action", "beacons");
        event.put("success", true);
        event.put("uuid", normalizedUUID(uuid));
        event.put("count", safeBeacons.length());
        event.put("beacons", safeBeacons);
        event.put("legacyBeacons", legacyBeacons != null ? legacyBeacons : new JSONObject());
        event.put("timestamp", timestamp(timestampMs));
        return event;
    }

    static JSONObject beaconObject(
            String uuid,
            int major,
            int minor,
            String proximity,
            double accuracy,
            int rssi,
            long ageMs
    ) throws JSONException {
        JSONObject json = new JSONObject();
        json.put("proximityUUID", normalizedUUID(uuid));
        json.put("major", major);
        json.put("minor", minor);
        json.put("proximity", proximity != null && !proximity.isEmpty() ? proximity : "unknown");
        json.put("accuracy", accuracy);
        json.put("rssi", rssi);
        json.put("age", Math.max(0L, ageMs) / 1000.0);
        return json;
    }

    static JSONObject advertiseStartResponse(JSONObject request, BeaconAdvertiseConfig config, String state) throws JSONException {
        JSONObject response = config.decorate(BridgeResponse.base(request, "beaconAdvertiseStart"));
        response.put("success", true);
        response.put("provider", ADVERTISER_PROVIDER);
        response.put("state", state);
        response.put("advertising", false);
        return response;
    }

    static JSONObject advertiseStopResponse(JSONObject request) throws JSONException {
        JSONObject response = BridgeResponse.base(request, "beaconAdvertiseStop");
        response.put("success", true);
        response.put("provider", ADVERTISER_PROVIDER);
        response.put("state", "stopped");
        return response;
    }

    static JSONObject advertiseStateEvent(
            JSONObject request,
            BeaconAdvertiseConfig config,
            boolean success,
            String state,
            boolean advertising,
            String error
    ) throws JSONException {
        JSONObject event = config.decorate(BridgeResponse.base(request, "beaconAdvertiseStart"));
        event.put("success", success);
        event.put("provider", ADVERTISER_PROVIDER);
        event.put("state", state);
        event.put("advertising", advertising);
        if (error != null && !error.isEmpty()) {
            event.put("error", error);
        }
        return event;
    }

    static JSONObject errorResponse(JSONObject request, String action, String error) throws JSONException {
        return BridgeResponse.error(request, action, error);
    }

    static BeaconAdvertiseConfig advertiseConfigFrom(JSONObject request) {
        String uuid = firstNonEmpty(request, "uuid", "beaconUUID", "beaconUuid", "proximityUUID");
        if (uuid.isEmpty()) {
            uuid = DEFAULT_BEACON_UUID;
        }
        if (!validUUID(uuid)) {
            return null;
        }

        int major = request != null && request.has("major") ? request.optInt("major", -1) : DEFAULT_MAJOR;
        int minor = request != null && request.has("minor") ? request.optInt("minor", -1) : DEFAULT_MINOR;
        if (major < 0 || major > 65535 || minor < 0 || minor > 65535) {
            return null;
        }

        int measuredPower = DEFAULT_TX_POWER;
        if (request != null) {
            if (request.has("measuredPower")) {
                measuredPower = request.optInt("measuredPower", DEFAULT_TX_POWER);
            } else if (request.has("measuredPowerDbm")) {
                measuredPower = request.optInt("measuredPowerDbm", DEFAULT_TX_POWER);
            } else if (request.has("txPower")) {
                measuredPower = request.optInt("txPower", DEFAULT_TX_POWER);
            }
        }
        if (measuredPower < -127 || measuredPower > 20) {
            return null;
        }

        return new BeaconAdvertiseConfig(normalizedUUID(uuid), major, minor, measuredPower);
    }

    static String rangingUUID(JSONObject request) {
        String uuid = request != null ? request.optString("uuid", "") : "";
        return validUUID(uuid) ? normalizedUUID(uuid) : DEFAULT_BEACON_UUID;
    }

    static boolean validUUID(String value) {
        try {
            UUID.fromString(value);
            return true;
        } catch (Exception ignored) {
            return false;
        }
    }

    static String proximityLabel(double distance) {
        if (distance < 0) {
            return "unknown";
        }
        if (distance <= 0.5) {
            return "immediate";
        }
        if (distance <= 3.0) {
            return "near";
        }
        return "far";
    }

    static String timestamp(long timeMs) {
        return new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", Locale.US).format(new Date(timeMs));
    }

    static JSONObject copyRequest(JSONObject source) {
        try {
            return new JSONObject(source != null ? source.toString() : "{}");
        } catch (JSONException ignored) {
            return new JSONObject();
        }
    }

    private static String normalizedUUID(String uuid) {
        if (!validUUID(uuid)) {
            return DEFAULT_BEACON_UUID;
        }
        return UUID.fromString(uuid).toString().toUpperCase(Locale.US);
    }

    private static String firstNonEmpty(JSONObject request, String... keys) {
        if (request == null) {
            return "";
        }
        for (String key : keys) {
            String value = request.optString(key, "").trim();
            if (!value.isEmpty()) {
                return value;
            }
        }
        return "";
    }

    static final class BeaconAdvertiseConfig {
        final String uuid;
        final int major;
        final int minor;
        final int measuredPower;

        private BeaconAdvertiseConfig(String uuid, int major, int minor, int measuredPower) {
            this.uuid = uuid;
            this.major = major;
            this.minor = minor;
            this.measuredPower = measuredPower;
        }

        JSONObject decorate(JSONObject response) throws JSONException {
            response.put("uuid", uuid);
            response.put("major", major);
            response.put("minor", minor);
            response.put("measuredPower", measuredPower);
            return response;
        }
    }
}
