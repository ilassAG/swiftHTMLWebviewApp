package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

import java.util.LinkedHashSet;
import java.util.Set;

public class AndroidSensorPayloadTest {
    @Test
    public void sensorTypeMappingAcceptsAliasesAndUnknowns() {
        assertEquals(AndroidSensorPayload.TYPE_ACCELEROMETER, AndroidSensorPayload.sensorTypeFromString(" accel "));
        assertEquals(AndroidSensorPayload.TYPE_GYROSCOPE, AndroidSensorPayload.sensorTypeFromString("GYRO"));
        assertEquals(AndroidSensorPayload.TYPE_MAGNETIC_FIELD, AndroidSensorPayload.sensorTypeFromString("compass"));
        assertEquals(AndroidSensorPayload.TYPE_PRESSURE, AndroidSensorPayload.sensorTypeFromString("barometer"));
        assertEquals(AndroidSensorPayload.TYPE_ROTATION_VECTOR, AndroidSensorPayload.sensorTypeFromString("rotationVector"));
        assertEquals(0, AndroidSensorPayload.sensorTypeFromString("unsupported"));
        assertEquals(0, AndroidSensorPayload.sensorTypeFromString(null));
    }

    @Test
    public void sensorInfoUsesStableTypeNames() throws Exception {
        JSONObject item = AndroidSensorPayload.sensorInfo(
                "LSM6DSO",
                "STMicro",
                AndroidSensorPayload.TYPE_GYROSCOPE,
                3,
                34.5f,
                0.01f,
                0.42f
        );

        assertEquals("LSM6DSO", item.getString("name"));
        assertEquals("STMicro", item.getString("vendor"));
        assertEquals(AndroidSensorPayload.TYPE_GYROSCOPE, item.getInt("type"));
        assertEquals("gyroscope", item.getString("typeName"));
        assertEquals(3, item.getInt("version"));
        assertEquals(34.5, item.getDouble("maximumRange"), 0.001);
        assertEquals(0.01, item.getDouble("resolution"), 0.001);
        assertEquals(0.42, item.getDouble("powerMilliAmp"), 0.001);

        assertEquals("type_1234", AndroidSensorPayload.sensorTypeName(1234));
    }

    @Test
    public void streamStartResponseIncludesActiveTypesAndErrorWhenNoSensors() throws Exception {
        JSONObject request = new JSONObject().put("requestId", "req-sensors");
        Set<Integer> activeTypes = new LinkedHashSet<>();
        activeTypes.add(AndroidSensorPayload.TYPE_ACCELEROMETER);
        activeTypes.add(AndroidSensorPayload.TYPE_LIGHT);

        JSONObject response = AndroidSensorPayload.streamStartResponse(request, true, 250L, activeTypes);

        assertEquals("android", response.getString("platform"));
        assertEquals("sensorStreamStart", response.getString("action"));
        assertEquals("req-sensors", response.getString("requestId"));
        assertTrue(response.getBoolean("success"));
        assertEquals(250L, response.getLong("intervalMs"));
        JSONArray active = response.getJSONArray("activeTypes");
        assertEquals(AndroidSensorPayload.TYPE_ACCELEROMETER, active.getInt(0));
        assertEquals(AndroidSensorPayload.TYPE_LIGHT, active.getInt(1));
        assertFalse(response.has("error"));

        JSONObject unavailable = AndroidSensorPayload.streamStartResponse(request, false, 500L, new LinkedHashSet<>());
        assertFalse(unavailable.getBoolean("success"));
        assertEquals("No requested sensors are available.", unavailable.getString("error"));
        assertEquals(0, unavailable.getJSONArray("activeTypes").length());
    }

    @Test
    public void sensorDataEventUsesCatalogedPayloadShape() throws Exception {
        JSONObject event = AndroidSensorPayload.sensorDataEvent(
                AndroidSensorPayload.TYPE_ACCELEROMETER,
                "BMI270",
                1710000000123456L,
                new float[] {1.25f, -2.5f, 0.0f}
        );

        assertEquals("android", event.getString("platform"));
        assertEquals("sensorData", event.getString("action"));
        assertTrue(event.getBoolean("success"));
        assertEquals(AndroidSensorPayload.TYPE_ACCELEROMETER, event.getInt("type"));
        assertEquals("accelerometer", event.getString("typeName"));
        assertEquals("BMI270", event.getString("name"));
        assertEquals(1710000000123456L, event.getLong("timestampNanos"));
        assertEquals(1.25, event.getJSONArray("values").getDouble(0), 0.001);
        assertEquals(-2.5, event.getJSONArray("values").getDouble(1), 0.001);
        assertEquals(0.0, event.getJSONArray("values").getDouble(2), 0.001);
    }
}
