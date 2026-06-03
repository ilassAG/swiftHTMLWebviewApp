package com.ilass.swifthtmlwebviewapp;

import android.content.Context;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

final class AndroidSensorBridge implements SensorEventListener {
    interface Listener {
        void onSensorEvent(JSONObject event);
    }

    private final SensorManager sensorManager;
    private final Listener listener;
    private final Set<Integer> activeTypes = new HashSet<>();
    private long minIntervalMs = 500;
    private long lastEventMs = 0;
    private boolean running = false;

    AndroidSensorBridge(Context context, Listener listener) {
        this.sensorManager = (SensorManager) context.getSystemService(Context.SENSOR_SERVICE);
        this.listener = listener;
    }

    JSONObject capabilities(JSONObject request) throws JSONException {
        JSONObject response = baseResponse(request, "sensorCapabilitiesGet", true);
        JSONArray sensors = new JSONArray();
        if (sensorManager != null) {
            List<Sensor> allSensors = sensorManager.getSensorList(Sensor.TYPE_ALL);
            for (Sensor sensor : allSensors) {
                JSONObject item = new JSONObject();
                item.put("name", sensor.getName());
                item.put("vendor", sensor.getVendor());
                item.put("type", sensor.getType());
                item.put("typeName", sensorTypeName(sensor.getType()));
                item.put("version", sensor.getVersion());
                item.put("maximumRange", sensor.getMaximumRange());
                item.put("resolution", sensor.getResolution());
                item.put("powerMilliAmp", sensor.getPower());
                sensors.put(item);
            }
        }
        response.put("sensors", sensors);
        return response;
    }

    JSONObject start(JSONObject request) throws JSONException {
        stopInternal();
        if (sensorManager == null) {
            return errorResponse(request, "sensorStreamStart", "Sensor service is not available.");
        }

        minIntervalMs = Math.max(100, request.optLong("intervalMs", 500));
        JSONArray requestedTypes = request.optJSONArray("types");
        if (requestedTypes == null || requestedTypes.length() == 0) {
            registerDefaultSensors();
        } else {
            for (int i = 0; i < requestedTypes.length(); i += 1) {
                registerSensor(sensorTypeFromString(requestedTypes.optString(i, "")));
            }
        }

        running = !activeTypes.isEmpty();
        JSONObject response = baseResponse(request, "sensorStreamStart", running);
        response.put("intervalMs", minIntervalMs);
        response.put("activeTypes", new JSONArray(activeTypes));
        if (!running) {
            response.put("error", "No requested sensors are available.");
        }
        return response;
    }

    JSONObject stop(JSONObject request) throws JSONException {
        stopInternal();
        return baseResponse(request, "sensorStreamStop", true);
    }

    void shutdown() {
        stopInternal();
    }

    @Override
    public void onSensorChanged(SensorEvent event) {
        if (!running || event == null || event.sensor == null) {
            return;
        }
        long now = System.currentTimeMillis();
        if (now - lastEventMs < minIntervalMs) {
            return;
        }
        lastEventMs = now;
        try {
            JSONObject payload = new JSONObject();
            payload.put("platform", "android");
            payload.put("action", "sensorData");
            payload.put("success", true);
            payload.put("type", event.sensor.getType());
            payload.put("typeName", sensorTypeName(event.sensor.getType()));
            payload.put("name", event.sensor.getName());
            payload.put("timestampNanos", event.timestamp);
            JSONArray values = new JSONArray();
            for (float value : event.values) {
                values.put(value);
            }
            payload.put("values", values);
            listener.onSensorEvent(payload);
        } catch (JSONException ignored) {
            // Ignore secondary JSON failure.
        }
    }

    @Override
    public void onAccuracyChanged(Sensor sensor, int accuracy) {
        // Accuracy is included only when the next sensor event arrives.
    }

    private void registerDefaultSensors() {
        registerSensor(Sensor.TYPE_ACCELEROMETER);
        registerSensor(Sensor.TYPE_GYROSCOPE);
        registerSensor(Sensor.TYPE_MAGNETIC_FIELD);
        registerSensor(Sensor.TYPE_LIGHT);
        registerSensor(Sensor.TYPE_PRESSURE);
        registerSensor(Sensor.TYPE_PROXIMITY);
    }

    private void registerSensor(int type) {
        if (type == 0 || sensorManager == null) {
            return;
        }
        Sensor sensor = sensorManager.getDefaultSensor(type);
        if (sensor == null) {
            return;
        }
        if (sensorManager.registerListener(this, sensor, SensorManager.SENSOR_DELAY_UI)) {
            activeTypes.add(type);
        }
    }

    private void stopInternal() {
        if (sensorManager != null) {
            sensorManager.unregisterListener(this);
        }
        activeTypes.clear();
        running = false;
        lastEventMs = 0;
    }

    private int sensorTypeFromString(String raw) {
        String value = raw == null ? "" : raw.trim().toLowerCase(Locale.US);
        switch (value) {
            case "accelerometer":
            case "accel":
                return Sensor.TYPE_ACCELEROMETER;
            case "gyroscope":
            case "gyro":
                return Sensor.TYPE_GYROSCOPE;
            case "magnetometer":
            case "magnetic":
            case "compass":
                return Sensor.TYPE_MAGNETIC_FIELD;
            case "light":
                return Sensor.TYPE_LIGHT;
            case "pressure":
            case "barometer":
                return Sensor.TYPE_PRESSURE;
            case "proximity":
                return Sensor.TYPE_PROXIMITY;
            case "gravity":
                return Sensor.TYPE_GRAVITY;
            case "rotation":
            case "rotationvector":
                return Sensor.TYPE_ROTATION_VECTOR;
            default:
                return 0;
        }
    }

    private String sensorTypeName(int type) {
        switch (type) {
            case Sensor.TYPE_ACCELEROMETER: return "accelerometer";
            case Sensor.TYPE_GYROSCOPE: return "gyroscope";
            case Sensor.TYPE_MAGNETIC_FIELD: return "magnetometer";
            case Sensor.TYPE_LIGHT: return "light";
            case Sensor.TYPE_PRESSURE: return "pressure";
            case Sensor.TYPE_PROXIMITY: return "proximity";
            case Sensor.TYPE_GRAVITY: return "gravity";
            case Sensor.TYPE_ROTATION_VECTOR: return "rotationVector";
            default: return "type_" + type;
        }
    }

    private JSONObject baseResponse(JSONObject request, String action, boolean success) throws JSONException {
        JSONObject response = new JSONObject();
        response.put("platform", "android");
        response.put("action", action);
        response.put("success", success);
        if (request != null && request.has("requestId")) {
            response.put("requestId", request.optString("requestId"));
        }
        return response;
    }

    private JSONObject errorResponse(JSONObject request, String action, String error) throws JSONException {
        JSONObject response = baseResponse(request, action, false);
        response.put("error", error);
        return response;
    }
}
