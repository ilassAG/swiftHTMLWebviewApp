package com.ilass.swifthtmlwebviewapp;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.Locale;
import java.util.Set;

final class AndroidSensorPayload {
    static final int TYPE_ACCELEROMETER = 1;
    static final int TYPE_MAGNETIC_FIELD = 2;
    static final int TYPE_GYROSCOPE = 4;
    static final int TYPE_LIGHT = 5;
    static final int TYPE_PRESSURE = 6;
    static final int TYPE_PROXIMITY = 8;
    static final int TYPE_GRAVITY = 9;
    static final int TYPE_ROTATION_VECTOR = 11;

    private AndroidSensorPayload() {
    }

    static JSONObject baseResponse(JSONObject request, String action, boolean success) throws JSONException {
        JSONObject response = BridgeResponse.base(request, action);
        response.put("success", success);
        return response;
    }

    static JSONObject errorResponse(JSONObject request, String action, String error) throws JSONException {
        JSONObject response = baseResponse(request, action, false);
        response.put("error", error);
        return response;
    }

    static JSONObject streamStartResponse(JSONObject request, boolean running, long intervalMs, Set<Integer> activeTypes) throws JSONException {
        JSONObject response = baseResponse(request, "sensorStreamStart", running);
        response.put("intervalMs", intervalMs);
        response.put("activeTypes", new JSONArray(activeTypes));
        if (!running) {
            response.put("error", "No requested sensors are available.");
        }
        return response;
    }

    static JSONObject sensorInfo(
            String name,
            String vendor,
            int type,
            int version,
            float maximumRange,
            float resolution,
            float powerMilliAmp
    ) throws JSONException {
        JSONObject item = new JSONObject();
        item.put("name", name);
        item.put("vendor", vendor);
        item.put("type", type);
        item.put("typeName", sensorTypeName(type));
        item.put("version", version);
        item.put("maximumRange", maximumRange);
        item.put("resolution", resolution);
        item.put("powerMilliAmp", powerMilliAmp);
        return item;
    }

    static JSONObject sensorDataEvent(
            int type,
            String name,
            long timestampNanos,
            float[] rawValues
    ) throws JSONException {
        JSONObject payload = new JSONObject();
        payload.put("platform", "android");
        payload.put("action", "sensorData");
        payload.put("success", true);
        payload.put("type", type);
        payload.put("typeName", sensorTypeName(type));
        payload.put("name", name);
        payload.put("timestampNanos", timestampNanos);
        JSONArray values = new JSONArray();
        if (rawValues != null) {
            for (float value : rawValues) {
                values.put(value);
            }
        }
        payload.put("values", values);
        return payload;
    }

    static int sensorTypeFromString(String raw) {
        String value = raw == null ? "" : raw.trim().toLowerCase(Locale.US);
        switch (value) {
            case "accelerometer":
            case "accel":
                return TYPE_ACCELEROMETER;
            case "gyroscope":
            case "gyro":
                return TYPE_GYROSCOPE;
            case "magnetometer":
            case "magnetic":
            case "compass":
                return TYPE_MAGNETIC_FIELD;
            case "light":
                return TYPE_LIGHT;
            case "pressure":
            case "barometer":
                return TYPE_PRESSURE;
            case "proximity":
                return TYPE_PROXIMITY;
            case "gravity":
                return TYPE_GRAVITY;
            case "rotation":
            case "rotationvector":
                return TYPE_ROTATION_VECTOR;
            default:
                return 0;
        }
    }

    static String sensorTypeName(int type) {
        switch (type) {
            case TYPE_ACCELEROMETER: return "accelerometer";
            case TYPE_GYROSCOPE: return "gyroscope";
            case TYPE_MAGNETIC_FIELD: return "magnetometer";
            case TYPE_LIGHT: return "light";
            case TYPE_PRESSURE: return "pressure";
            case TYPE_PROXIMITY: return "proximity";
            case TYPE_GRAVITY: return "gravity";
            case TYPE_ROTATION_VECTOR: return "rotationVector";
            default: return "type_" + type;
        }
    }
}
