package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import org.junit.Test;

public class AndroidCaptureResponseBuilderTest {
    @Test
    public void documentImageResponseUsesCurrentBridgeFields() throws JSONException {
        JSONObject response = AndroidCaptureResponseBuilder.documentImages(
                request("scanDocument"),
                2,
                new JSONArray()
                        .put("data:image/jpeg;base64,page1")
                        .put("data:image/jpeg;base64,page2"),
                "jpeg"
        );

        assertEquals("android", response.getString("platform"));
        assertEquals("scanDocument", response.getString("action"));
        assertEquals("req-1", response.getString("requestId"));
        assertTrue(response.getBoolean("success"));
        assertFalse(response.getBoolean("ocr"));
        assertEquals("jpeg", response.getString("format"));
        assertEquals(2, response.getInt("pages"));
        assertEquals(2, response.getJSONArray("images").length());
        assertFalse(response.has("pdfData"));
    }

    @Test
    public void documentImageResponseDerivesPageCountAndJpegFormat() throws JSONException {
        JSONObject response = AndroidCaptureResponseBuilder.documentImages(
                request("scanDocument"),
                new JSONArray()
                        .put("data:image/jpeg;base64,page1")
                        .put("data:image/jpeg;base64,page2")
                        .put("data:image/jpeg;base64,page3")
        );

        assertEquals("jpeg", response.getString("format"));
        assertEquals(3, response.getInt("pages"));
        assertEquals(3, response.getJSONArray("images").length());
    }

    @Test
    public void documentPdfResponseUsesPdfDataField() throws JSONException {
        JSONObject response = AndroidCaptureResponseBuilder.documentPdf(
                request("scanDocument"),
                1,
                "data:application/pdf;base64,pdf"
        );

        assertEquals("android", response.getString("platform"));
        assertEquals("scanDocument", response.getString("action"));
        assertTrue(response.getBoolean("success"));
        assertFalse(response.getBoolean("ocr"));
        assertEquals("pdf", response.getString("format"));
        assertEquals(1, response.getInt("pages"));
        assertEquals("data:application/pdf;base64,pdf", response.getString("pdfData"));
        assertFalse(response.has("images"));
    }

    @Test
    public void photoResponseIncludesCameraAndBackgroundRemovedFalse() throws JSONException {
        JSONObject response = AndroidCaptureResponseBuilder.photo(
                request("takePhoto").put("camera", "front"),
                "jpeg",
                "data:image/jpeg;base64,photo",
                false
        );

        assertEquals("android", response.getString("platform"));
        assertEquals("takePhoto", response.getString("action"));
        assertTrue(response.getBoolean("success"));
        assertEquals("front", response.getString("camera"));
        assertEquals("jpeg", response.getString("format"));
        assertEquals("data:image/jpeg;base64,photo", response.getString("imageData"));
        assertFalse(response.getBoolean("backgroundRemoved"));
        assertFalse(response.has("background"));
        assertFalse(response.has("cropped"));
    }

    @Test
    public void photoResponseIncludesBackgroundRemovalMetadata() throws JSONException {
        JSONObject response = AndroidCaptureResponseBuilder.photo(
                request("takePhoto")
                        .put("background", "color")
                        .put("backgroundColor", "#112233")
                        .put("cropTransparent", true),
                "png",
                "data:image/png;base64,photo",
                true
        );

        assertEquals("png", response.getString("format"));
        assertTrue(response.getBoolean("success"));
        assertTrue(response.getBoolean("backgroundRemoved"));
        assertEquals("color", response.getString("background"));
        assertEquals("#112233", response.getString("backgroundColor"));
        assertTrue(response.getBoolean("cropped"));
        assertEquals("back", response.getString("camera"));
    }

    @Test
    public void photoFormatPrefersPngForBackgroundRemovalOrRequestedPng() throws JSONException {
        assertEquals("png", AndroidCaptureResponseBuilder.photoFormat(request("takePhoto"), true));
        assertEquals("png", AndroidCaptureResponseBuilder.photoFormat(request("takePhoto").put("outputType", "png"), false));
        assertEquals("jpeg", AndroidCaptureResponseBuilder.photoFormat(request("takePhoto").put("outputType", "jpeg"), false));
        assertEquals("jpeg", AndroidCaptureResponseBuilder.photoFormat(null, false));
    }

    private JSONObject request(String action) throws JSONException {
        return new JSONObject()
                .put("action", action)
                .put("requestId", "req-1");
    }
}
