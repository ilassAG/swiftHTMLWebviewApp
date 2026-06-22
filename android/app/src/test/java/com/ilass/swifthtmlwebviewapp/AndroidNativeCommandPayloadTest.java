package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.json.JSONException;
import org.json.JSONObject;
import org.junit.Test;

public class AndroidNativeCommandPayloadTest {
    @Test
    public void launchConfettiResponseUsesNativeCommandEnvelopeAndMetadata() throws JSONException {
        JSONObject response = AndroidNativeCommandPayload.launchConfettiResponse(
                new JSONObject()
                        .put("action", "launchConfetti")
                        .put("requestId", "req-confetti-1"),
                4,
                "android_overlay"
        );

        assertEquals("android", response.getString("platform"));
        assertEquals("launchConfetti", response.getString("action"));
        assertEquals("req-confetti-1", response.getString("requestId"));
        assertTrue(response.getBoolean("success"));
        assertTrue(response.getBoolean("launched"));
        assertEquals(4, response.getInt("burstCount"));
        assertEquals("android_overlay", response.getString("nativeStatus"));
    }

    @Test
    public void reloadResponseUsesNativeCommandEnvelope() throws JSONException {
        JSONObject response = AndroidNativeCommandPayload.reloadResponse(
                new JSONObject()
                        .put("action", "reload")
                        .put("requestId", "req-reload-1")
        );

        assertEquals("android", response.getString("platform"));
        assertEquals("reload", response.getString("action"));
        assertEquals("req-reload-1", response.getString("requestId"));
        assertTrue(response.getBoolean("success"));
    }
}
