package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.json.JSONObject;
import org.junit.Test;

public class AndroidSoundPayloadTest {
    @Test
    public void requestClampsFrequencyDurationAndVolume() throws Exception {
        AndroidSoundPayload.Request sound = AndroidSoundPayload.request(new JSONObject()
                .put("frequencyHz", 10)
                .put("durationMs", 9000)
                .put("volume", 2.5));

        assertEquals(80, sound.frequencyHz);
        assertEquals(5000, sound.durationMs);
        assertEquals(1.0, sound.volume, 0.0001);
    }

    @Test
    public void responseUsesNativeCommandEnvelopeAndEchoesNormalizedValues() throws Exception {
        JSONObject source = new JSONObject()
                .put("requestId", "req-sound")
                .put("frequencyHz", 5000)
                .put("durationMs", 20)
                .put("volume", -2.0);

        AndroidSoundPayload.Request sound = AndroidSoundPayload.request(source);
        JSONObject response = AndroidSoundPayload.response(source, sound);

        assertEquals("android", response.getString("platform"));
        assertEquals("soundPlay", response.getString("action"));
        assertEquals("req-sound", response.getString("requestId"));
        assertTrue(response.getBoolean("success"));
        assertEquals(4000, response.getInt("frequencyHz"));
        assertEquals(40, response.getInt("durationMs"));
        assertEquals(0.0, response.getDouble("volume"), 0.0001);
    }
}
