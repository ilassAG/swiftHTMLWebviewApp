package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.json.JSONObject;
import org.junit.Test;

public class AndroidScreenshotPayloadTest {
    @Test
    public void requestClampsMaxWidthAndQuality() throws Exception {
        AndroidScreenshotPayload.Request request = AndroidScreenshotPayload.request(new JSONObject()
                .put("maxWidth", 99)
                .put("quality", 200));

        assertEquals(240, request.maxWidth);
        assertEquals(95, request.quality);

        request = AndroidScreenshotPayload.request(new JSONObject()
                .put("maxWidth", 3000)
                .put("quality", 1));

        assertEquals(2160, request.maxWidth);
        assertEquals(25, request.quality);
    }

    @Test
    public void responseUsesDiagnosticsEnvelopeAndImageMetadata() throws Exception {
        JSONObject response = AndroidScreenshotPayload.response(
                new JSONObject().put("requestId", "req-shot"),
                720,
                1280,
                "data:image/jpeg;base64,shot"
        );

        assertEquals("android", response.getString("platform"));
        assertEquals("screenshotGet", response.getString("action"));
        assertEquals("req-shot", response.getString("requestId"));
        assertTrue(response.getBoolean("success"));
        assertEquals("jpeg", response.getString("format"));
        assertEquals(720, response.getInt("width"));
        assertEquals(1280, response.getInt("height"));
        assertEquals("data:image/jpeg;base64,shot", response.getString("imageData"));
    }
}
