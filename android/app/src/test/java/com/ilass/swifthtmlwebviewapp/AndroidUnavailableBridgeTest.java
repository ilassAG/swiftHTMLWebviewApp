package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;

import org.json.JSONException;
import org.json.JSONObject;
import org.junit.Test;

public class AndroidUnavailableBridgeTest {
    @Test
    public void arPositionUnavailableUsesRequestActionAndCommonShape() throws JSONException {
        JSONObject response = AndroidUnavailableBridge.arPosition(new JSONObject()
                .put("action", "arPositionStop")
                .put("requestId", "req-position"));

        assertEquals("android", response.getString("platform"));
        assertEquals("arPositionStop", response.getString("action"));
        assertEquals("req-position", response.getString("requestId"));
        assertFalse(response.getBoolean("success"));
        assertFalse(response.getBoolean("supported"));
        assertEquals("arkit-position", response.getString("source"));
        assertEquals("ARKit local position tracking is iOS-only and not available on Android.", response.getString("error"));
    }

    @Test
    public void arPositionUnavailableFallsBackToStartAction() throws JSONException {
        JSONObject response = AndroidUnavailableBridge.arPosition(new JSONObject());

        assertEquals("arPositionStart", response.getString("action"));
    }

    @Test
    public void roomPlanUnavailableUsesRoomPlanSource() throws JSONException {
        JSONObject response = AndroidUnavailableBridge.roomPlan(new JSONObject()
                .put("action", "roomPlanScanExport")
                .put("requestId", "req-room"));

        assertEquals("roomPlanScanExport", response.getString("action"));
        assertEquals("req-room", response.getString("requestId"));
        assertFalse(response.getBoolean("success"));
        assertFalse(response.getBoolean("supported"));
        assertEquals("roomplan", response.getString("source"));
        assertEquals("RoomPlan/LiDAR scanning is iOS-only and not available on Android.", response.getString("error"));
    }

    @Test
    public void arGuidedUnavailableUsesGuidedSource() throws JSONException {
        JSONObject response = AndroidUnavailableBridge.arGuided(new JSONObject()
                .put("action", "arGuidedMeasurementStop"));

        assertEquals("arGuidedMeasurementStop", response.getString("action"));
        assertFalse(response.getBoolean("success"));
        assertFalse(response.getBoolean("supported"));
        assertEquals("arkit-guided", response.getString("source"));
        assertEquals("ARKit guided measurement is iOS-only and not available on Android.", response.getString("error"));
    }

    @Test
    public void arOverlayUnavailableUsesOverlaySourceAndDefaultAction() throws JSONException {
        JSONObject response = AndroidUnavailableBridge.arOverlay(new JSONObject());

        assertEquals("arOverlayOpen", response.getString("action"));
        assertFalse(response.getBoolean("success"));
        assertFalse(response.getBoolean("supported"));
        assertEquals("arkit-overlay", response.getString("source"));
        assertEquals("ARKit overlays are iOS-only and not available on Android.", response.getString("error"));
    }
}
