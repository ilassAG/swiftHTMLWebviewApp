package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.json.JSONException;
import org.json.JSONObject;
import org.junit.Test;

public class AndroidPortraitCaptureRequestTest {
    @Test
    public void defaultsMatchIosPortraitCaptureDefaults() {
        AndroidPortraitCaptureRequest request = AndroidPortraitCaptureRequest.from(new JSONObject());

        assertEquals("portraitCapture", request.action);
        assertEquals("jpeg", request.outputType);
        assertFalse(request.removeBackground);
        assertFalse(request.cropTransparent);
        assertEquals("transparent", request.background);
        assertEquals("#FFFFFF", request.backgroundColor);
        assertEquals("front", request.camera);
        assertEquals(1, request.requiredFaces);
        assertEquals(3000, request.countdownMs);
        assertEquals(4, request.variationCount);
        assertEquals(200, request.captureIntervalMs);
        assertEquals(200, request.preCaptureLeadMs());
        assertTrue(request.faceCenteredCrop);
        assertFalse(request.mirrorOutput);
        assertArrayEquals(new long[]{0, 200, 400, 600}, request.captureOffsetsMs());
        assertEquals(1, request.defaultSelectedIndex());
    }

    @Test
    public void parsesLegacyAliasesAndStringBooleans() throws JSONException {
        AndroidPortraitCaptureRequest request = AndroidPortraitCaptureRequest.from(new JSONObject()
                .put("amountFaces", "2")
                .put("secondsDelay", "2.5")
                .put("withVariation", "3")
                .put("variationIntervalMs", "150")
                .put("removeBackground", "yes")
                .put("cropTransparent", "on")
                .put("background", "color")
                .put("backgroundColor", "112233")
                .put("camera", "back")
                .put("mirror", "yes")
                .put("outputType", "png"));

        assertEquals(2, request.requiredFaces);
        assertEquals(2500, request.countdownMs);
        assertEquals(3, request.variationCount);
        assertEquals(150, request.captureIntervalMs);
        assertTrue(request.removeBackground);
        assertTrue(request.cropTransparent);
        assertEquals("color", request.background);
        assertEquals("112233", request.backgroundColor);
        assertEquals("back", request.camera);
        assertTrue(request.mirrorOutput);
        assertEquals("png", request.outputType);
    }

    @Test
    public void parsesMirrorOutputBoolean() throws JSONException {
        AndroidPortraitCaptureRequest request = AndroidPortraitCaptureRequest.from(new JSONObject()
                .put("mirrorOutput", true));

        assertTrue(request.mirrorOutput);
    }

    @Test
    public void clampsNumericValues() throws JSONException {
        AndroidPortraitCaptureRequest request = AndroidPortraitCaptureRequest.from(new JSONObject()
                .put("requiredFaces", 20)
                .put("countdownSeconds", -4)
                .put("variationCount", 0)
                .put("captureIntervalMs", 5000));

        assertEquals(8, request.requiredFaces);
        assertEquals(0, request.countdownMs);
        assertEquals(1, request.variationCount);
        assertEquals(2000, request.captureIntervalMs);
        assertEquals(0, request.preCaptureLeadMs());
        assertArrayEquals(new long[]{0}, request.captureOffsetsMs());
        assertEquals(0, request.defaultSelectedIndex());
    }

    @Test
    public void transparentBackgroundRemovalForcesPngResponse() throws JSONException {
        AndroidPortraitCaptureRequest request = AndroidPortraitCaptureRequest.from(new JSONObject()
                .put("removeBackground", true)
                .put("background", "transparent")
                .put("outputType", "jpeg"));

        assertEquals("png", request.responseFormat(true));
        assertEquals("jpeg", request.responseFormat(false));
    }
}
