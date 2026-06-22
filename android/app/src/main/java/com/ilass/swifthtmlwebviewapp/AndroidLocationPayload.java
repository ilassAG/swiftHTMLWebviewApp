package com.ilass.swifthtmlwebviewapp;

import org.json.JSONException;
import org.json.JSONObject;

final class AndroidLocationPayload {
    private AndroidLocationPayload() {
    }

    static JSONObject response(JSONObject request, String action, JSONObject location) throws JSONException {
        JSONObject response = BridgeResponse.base(request, action);
        response.put("success", true);
        response.put("location", location);
        return response;
    }

    static JSONObject startResponse(
            JSONObject request,
            long intervalMs,
            float minDistanceMeters,
            JSONObject lastLocation
    ) throws JSONException {
        JSONObject response = BridgeResponse.base(request, "geoLocationStart");
        response.put("success", true);
        response.put("intervalMs", intervalMs);
        response.put("minDistanceMeters", minDistanceMeters);
        if (lastLocation != null) {
            response.put("lastLocation", lastLocation);
        }
        return response;
    }

    static JSONObject stopResponse(JSONObject request) throws JSONException {
        JSONObject response = BridgeResponse.base(request, "geoLocationStop");
        response.put("success", true);
        return response;
    }

    static JSONObject errorResponse(JSONObject request, String action, String message) throws JSONException {
        return BridgeResponse.error(request, action, message);
    }

    static JSONObject locationObject(
            double latitude,
            double longitude,
            Number accuracyMeters,
            Number altitudeMeters,
            Number speedMetersPerSecond,
            Number bearingDegrees,
            String provider,
            long timestampMs
    ) throws JSONException {
        JSONObject payload = new JSONObject();
        payload.put("latitude", latitude);
        payload.put("longitude", longitude);
        putNullableNumber(payload, "accuracyMeters", accuracyMeters);
        putNullableNumber(payload, "altitudeMeters", altitudeMeters);
        putNullableNumber(payload, "speedMetersPerSecond", speedMetersPerSecond);
        putNullableNumber(payload, "bearingDegrees", bearingDegrees);
        payload.put("provider", provider != null ? provider : "");
        payload.put("timestampMs", timestampMs);
        return payload;
    }

    private static void putNullableNumber(JSONObject payload, String key, Number value) throws JSONException {
        payload.put(key, value != null ? value : JSONObject.NULL);
    }
}
