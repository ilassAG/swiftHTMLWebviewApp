package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.json.JSONObject;
import org.junit.Test;

public class AndroidIdleTimerPayloadTest {
    @Test
    public void startResponseClampsAndUsesCommonEnvelope() throws Exception {
        JSONObject request = new JSONObject()
                .put("requestId", "idle-1")
                .put("timeoutSeconds", 0.1)
                .put("intervalSeconds", 0.01);

        long timeoutMs = AndroidIdleTimerPayload.timeoutMillis(request);
        long intervalMs = AndroidIdleTimerPayload.intervalMillis(request);
        JSONObject response = AndroidIdleTimerPayload.startResponse(request, timeoutMs, intervalMs);

        assertEquals(1000L, timeoutMs);
        assertEquals(250L, intervalMs);
        assertEquals("android", response.getString("platform"));
        assertEquals("idleTimerStart", response.getString("action"));
        assertEquals("idle-1", response.getString("requestId"));
        assertTrue(response.getBoolean("success"));
        assertEquals(1.0, response.getDouble("timeoutSeconds"), 0.001);
        assertEquals(0.25, response.getDouble("intervalSeconds"), 0.001);
    }

    @Test
    public void stopAndResetResponsesUseCommonEnvelope() throws Exception {
        JSONObject request = new JSONObject().put("requestId", "idle-2");

        JSONObject stop = AndroidIdleTimerPayload.stopResponse(request);
        JSONObject reset = AndroidIdleTimerPayload.resetResponse(request);

        assertEquals("idleTimerStop", stop.getString("action"));
        assertEquals("idle-2", stop.getString("requestId"));
        assertTrue(stop.getBoolean("success"));
        assertEquals("idleTimerReset", reset.getString("action"));
        assertEquals("idle-2", reset.getString("requestId"));
        assertTrue(reset.getBoolean("success"));
    }

    @Test
    public void eventsUseCatalogedPayloadShape() throws Exception {
        JSONObject tick = AndroidIdleTimerPayload.event("idleTick", 3500L, 30000L);
        JSONObject timeout = AndroidIdleTimerPayload.event("idleTimeout", 31000L, 30000L);

        assertEquals("android", tick.getString("platform"));
        assertEquals("idleTick", tick.getString("action"));
        assertTrue(tick.getBoolean("success"));
        assertEquals(3.5, tick.getDouble("idleSeconds"), 0.001);
        assertEquals(30.0, tick.getDouble("timeoutSeconds"), 0.001);
        assertEquals("idleTimeout", timeout.getString("action"));
        assertTrue(timeout.getBoolean("success"));
        assertEquals(31.0, timeout.getDouble("idleSeconds"), 0.001);
        assertEquals(30.0, timeout.getDouble("timeoutSeconds"), 0.001);
    }
}
