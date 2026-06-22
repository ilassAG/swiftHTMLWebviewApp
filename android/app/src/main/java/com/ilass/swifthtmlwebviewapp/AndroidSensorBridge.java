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
        JSONObject response = AndroidSensorPayload.baseResponse(request, "sensorCapabilitiesGet", true);
        JSONArray sensors = new JSONArray();
        if (sensorManager != null) {
            List<Sensor> allSensors = sensorManager.getSensorList(Sensor.TYPE_ALL);
            for (Sensor sensor : allSensors) {
                sensors.put(AndroidSensorPayload.sensorInfo(
                        sensor.getName(),
                        sensor.getVendor(),
                        sensor.getType(),
                        sensor.getVersion(),
                        sensor.getMaximumRange(),
                        sensor.getResolution(),
                        sensor.getPower()
                ));
            }
        }
        response.put("sensors", sensors);
        return response;
    }

    JSONObject start(JSONObject request) throws JSONException {
        stopInternal();
        if (sensorManager == null) {
            return AndroidSensorPayload.errorResponse(request, "sensorStreamStart", "Sensor service is not available.");
        }

        minIntervalMs = Math.max(100, request.optLong("intervalMs", 500));
        JSONArray requestedTypes = request.optJSONArray("types");
        if (requestedTypes == null || requestedTypes.length() == 0) {
            registerDefaultSensors();
        } else {
            for (int i = 0; i < requestedTypes.length(); i += 1) {
                registerSensor(AndroidSensorPayload.sensorTypeFromString(requestedTypes.optString(i, "")));
            }
        }

        running = !activeTypes.isEmpty();
        return AndroidSensorPayload.streamStartResponse(request, running, minIntervalMs, activeTypes);
    }

    JSONObject stop(JSONObject request) throws JSONException {
        stopInternal();
        return AndroidSensorPayload.baseResponse(request, "sensorStreamStop", true);
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
            listener.onSensorEvent(AndroidSensorPayload.sensorDataEvent(
                    event.sensor.getType(),
                    event.sensor.getName(),
                    event.timestamp,
                    event.values
            ));
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

}
