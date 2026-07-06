package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;

import org.json.JSONObject;
import org.junit.Test;

public class AndroidQrImageScannerTest {
    @Test
    public void rejectsMissingImagePayload() throws Exception {
        JSONObject response = AndroidQrImageScanner.response(new JSONObject().put("requestId", "qr-missing"));

        assertEquals("android", response.getString("platform"));
        assertEquals("qrScanImage", response.getString("action"));
        assertEquals("qr-missing", response.getString("requestId"));
        assertFalse(response.getBoolean("success"));
        assertEquals("imageBase64 or dataUrl is required.", response.getString("error"));
    }

    @Test
    public void rejectsInvalidBase64Payload() throws Exception {
        JSONObject response = AndroidQrImageScanner.response(new JSONObject()
                .put("requestId", "qr-invalid")
                .put("dataURL", "data:image/png;base64,%%%"));

        assertEquals("qrScanImage", response.getString("action"));
        assertFalse(response.getBoolean("success"));
        assertEquals("Image payload is not valid base64.", response.getString("error"));
    }
}
