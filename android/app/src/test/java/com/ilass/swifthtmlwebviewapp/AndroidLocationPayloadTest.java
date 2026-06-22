package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.json.JSONObject;
import org.junit.Test;

public class AndroidLocationPayloadTest {
    @Test
    public void locationObjectIncludesProviderTimestampAndAvailableSignals() throws Exception {
        JSONObject location = AndroidLocationPayload.locationObject(
                52.520008,
                13.404954,
                4.5f,
                37.25,
                1.2f,
                88.0f,
                "gps",
                1710000000123L
        );

        assertEquals(52.520008, location.getDouble("latitude"), 0.000001);
        assertEquals(13.404954, location.getDouble("longitude"), 0.000001);
        assertEquals(4.5, location.getDouble("accuracyMeters"), 0.001);
        assertEquals(37.25, location.getDouble("altitudeMeters"), 0.001);
        assertEquals(1.2, location.getDouble("speedMetersPerSecond"), 0.001);
        assertEquals(88.0, location.getDouble("bearingDegrees"), 0.001);
        assertEquals("gps", location.getString("provider"));
        assertEquals(1710000000123L, location.getLong("timestampMs"));
    }

    @Test
    public void locationObjectUsesJsonNullForMissingOptionalSignals() throws Exception {
        JSONObject location = AndroidLocationPayload.locationObject(
                47.3769,
                8.5417,
                null,
                null,
                null,
                null,
                null,
                1710000000456L
        );

        assertTrue(location.isNull("accuracyMeters"));
        assertTrue(location.isNull("altitudeMeters"));
        assertTrue(location.isNull("speedMetersPerSecond"));
        assertTrue(location.isNull("bearingDegrees"));
        assertEquals("", location.getString("provider"));
        assertEquals(1710000000456L, location.getLong("timestampMs"));
    }

    @Test
    public void responseWrapsLocationInCommonBridgeEnvelope() throws Exception {
        JSONObject request = new JSONObject().put("requestId", "req-location");
        JSONObject location = AndroidLocationPayload.locationObject(
                48.137154,
                11.576124,
                3.0f,
                null,
                null,
                null,
                "network",
                1710000000789L
        );

        JSONObject response = AndroidLocationPayload.response(request, "geoLocationGet", location);

        assertEquals("android", response.getString("platform"));
        assertEquals("geoLocationGet", response.getString("action"));
        assertEquals("req-location", response.getString("requestId"));
        assertTrue(response.getBoolean("success"));
        assertEquals(48.137154, response.getJSONObject("location").getDouble("latitude"), 0.000001);
        assertEquals("network", response.getJSONObject("location").getString("provider"));
    }

    @Test
    public void startResponseUsesStreamControlEnvelopeAndOptionalLastLocation() throws Exception {
        JSONObject request = new JSONObject().put("requestId", "req-start");
        JSONObject lastLocation = AndroidLocationPayload.locationObject(
                53.551086,
                9.993682,
                6.0f,
                null,
                null,
                null,
                "gps",
                1710000000999L
        );

        JSONObject response = AndroidLocationPayload.startResponse(
                request,
                2500L,
                1.5f,
                lastLocation
        );

        assertEquals("android", response.getString("platform"));
        assertEquals("geoLocationStart", response.getString("action"));
        assertEquals("req-start", response.getString("requestId"));
        assertTrue(response.getBoolean("success"));
        assertEquals(2500L, response.getLong("intervalMs"));
        assertEquals(1.5, response.getDouble("minDistanceMeters"), 0.001);
        assertEquals(53.551086, response.getJSONObject("lastLocation").getDouble("latitude"), 0.000001);

        response = AndroidLocationPayload.startResponse(request, 3000L, 0f, null);

        assertEquals("geoLocationStart", response.getString("action"));
        assertTrue(response.getBoolean("success"));
        assertEquals(3000L, response.getLong("intervalMs"));
        assertEquals(0.0, response.getDouble("minDistanceMeters"), 0.001);
        assertFalse(response.has("lastLocation"));
    }

    @Test
    public void stopResponseUsesStreamControlEnvelope() throws Exception {
        JSONObject response = AndroidLocationPayload.stopResponse(new JSONObject().put("requestId", "req-stop"));

        assertEquals("android", response.getString("platform"));
        assertEquals("geoLocationStop", response.getString("action"));
        assertEquals("req-stop", response.getString("requestId"));
        assertTrue(response.getBoolean("success"));
    }

    @Test
    public void errorResponseUsesCommonBridgeEnvelope() throws Exception {
        JSONObject response = AndroidLocationPayload.errorResponse(
                new JSONObject().put("requestId", "req-location-error"),
                "geoLocationStart",
                "Location service is not available."
        );

        assertEquals("android", response.getString("platform"));
        assertEquals("geoLocationStart", response.getString("action"));
        assertEquals("req-location-error", response.getString("requestId"));
        assertFalse(response.getBoolean("success"));
        assertEquals("Location service is not available.", response.getString("error"));
    }
}
