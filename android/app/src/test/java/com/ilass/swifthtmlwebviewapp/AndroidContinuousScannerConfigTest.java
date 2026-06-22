package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import com.google.mlkit.vision.barcode.common.Barcode;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import org.junit.Test;

public class AndroidContinuousScannerConfigTest {
    @Test
    public void loginScanDefaultsToLoginModeAndFrontCamera() throws JSONException {
        AndroidContinuousScannerConfig config = AndroidContinuousScannerConfig.from(
                new JSONObject().put("action", "loginScanStart")
        );

        assertEquals("loginScanStart", config.action);
        assertEquals("login", config.mode);
        assertEquals("front", config.camera);
        assertEquals(1500L, config.repeatDelayMs);
        assertTrue(config.showCloseButton);
    }

    @Test
    public void requestOverridesRepeatDelayCloseButtonAndPreviewRect() throws JSONException {
        AndroidContinuousScannerConfig config = AndroidContinuousScannerConfig.from(
                new JSONObject()
                        .put("action", "dataScanStart")
                        .put("mode", "inventory")
                        .put("camera", "front")
                        .put("repeatDelay", "2.25")
                        .put("closeButton", false)
                        .put("previewRect", new JSONObject()
                                .put("x", 80)
                                .put("y", -10)
                                .put("width", 35)
                                .put("height", 200))
        );

        assertEquals("inventory", config.mode);
        assertEquals("front", config.camera);
        assertEquals(2250L, config.repeatDelayMs);
        assertFalse(config.showCloseButton);
        assertEquals(0.65, config.rect.left, 0.0001);
        assertEquals(0.0, config.rect.top, 0.0001);
        assertEquals(0.35, config.rect.width, 0.0001);
        assertEquals(1.0, config.rect.height, 0.0001);
    }

    @Test
    public void responseUsesNormalizedConfigAndEchoesRequestId() throws JSONException {
        JSONObject request = new JSONObject()
                .put("action", "continuousScanStart")
                .put("requestId", "req-stream")
                .put("types", new JSONArray().put("qr").put("code128"));
        AndroidContinuousScannerConfig config = AndroidContinuousScannerConfig.from(request);
        JSONObject response = config.response(request, "continuousScanStart", true);

        assertEquals("android", response.getString("platform"));
        assertEquals("continuousScanStart", response.getString("action"));
        assertEquals("req-stream", response.getString("requestId"));
        assertTrue(response.getBoolean("success"));
        assertEquals("android_camerax_mlkit", response.getString("provider"));
        assertEquals(2, response.getJSONArray("types").length());
        assertEquals(1.5, response.getDouble("repeatDelaySeconds"), 0.0001);
        assertTrue(response.getBoolean("showCloseButton"));
        assertEquals(0.80, response.getJSONObject("previewRect").getDouble("width"), 0.0001);
    }

    @Test
    public void stopResponseUsesRequestedActionAndCommonEnvelope() throws JSONException {
        JSONObject response = AndroidContinuousScannerConfig.stopResponse(
                new JSONObject()
                        .put("action", "loginScanEnd")
                        .put("requestId", "req-stop")
        );

        assertEquals("android", response.getString("platform"));
        assertEquals("loginScanEnd", response.getString("action"));
        assertEquals("req-stop", response.getString("requestId"));
        assertTrue(response.getBoolean("success"));

        response = AndroidContinuousScannerConfig.stopResponse(new JSONObject());

        assertEquals("continuousScanStop", response.getString("action"));
        assertTrue(response.getBoolean("success"));
    }

    @Test
    public void errorAndClosedByUserResponsesUseStreamControlShape() throws JSONException {
        JSONObject error = AndroidContinuousScannerConfig.errorResponse(
                new JSONObject().put("requestId", "req-error"),
                "continuousScanStart",
                "Camera permission was denied."
        );

        assertEquals("android", error.getString("platform"));
        assertEquals("continuousScanStart", error.getString("action"));
        assertEquals("req-error", error.getString("requestId"));
        assertFalse(error.getBoolean("success"));
        assertEquals("Camera permission was denied.", error.getString("error"));

        JSONObject closed = AndroidContinuousScannerConfig.closedByUserResponse(null);

        assertEquals("android", closed.getString("platform"));
        assertEquals("continuousScanStop", closed.getString("action"));
        assertTrue(closed.getBoolean("success"));
        assertTrue(closed.getBoolean("closedByUser"));
    }

    @Test
    public void barcodeFormatsDeduplicateAndSkipUnknownValues() {
        int[] formats = AndroidContinuousScannerConfig.barcodeFormats(
                new JSONArray()
                        .put("qr")
                        .put("qr")
                        .put("code39")
                        .put("unknown")
                        .put("interleaved2of5")
        );

        assertArrayEquals(new int[]{
                Barcode.FORMAT_QR_CODE,
                Barcode.FORMAT_CODE_39,
                Barcode.FORMAT_ITF
        }, formats);
    }

    @Test
    public void barcodeFormatsFallbackToCoreScannerFormats() {
        int[] formats = AndroidContinuousScannerConfig.barcodeFormats(null);

        assertArrayEquals(new int[]{
                Barcode.FORMAT_QR_CODE,
                Barcode.FORMAT_EAN_13,
                Barcode.FORMAT_EAN_8,
                Barcode.FORMAT_CODE_128,
                Barcode.FORMAT_DATA_MATRIX
        }, formats);
    }
}
