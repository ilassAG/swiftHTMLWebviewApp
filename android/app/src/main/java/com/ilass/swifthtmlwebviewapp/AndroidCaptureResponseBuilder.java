package com.ilass.swifthtmlwebviewapp;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

final class AndroidCaptureResponseBuilder {
    private AndroidCaptureResponseBuilder() {
    }

    static JSONObject documentImages(JSONObject request, JSONArray images) throws JSONException {
        JSONArray safeImages = images != null ? images : new JSONArray();
        return documentImages(request, safeImages.length(), safeImages, "jpeg");
    }

    static JSONObject documentImages(JSONObject request, int pageCount, JSONArray images, String format) throws JSONException {
        JSONObject response = BridgeResponse.base(request, "scanDocument");
        response.put("success", true);
        response.put("ocr", false);
        response.put("format", format);
        response.put("pages", pageCount);
        response.put("images", images);
        return response;
    }

    static JSONObject documentPdf(JSONObject request, int pageCount, String pdfDataUrl) throws JSONException {
        JSONObject response = BridgeResponse.base(request, "scanDocument");
        response.put("success", true);
        response.put("ocr", false);
        response.put("format", "pdf");
        response.put("pages", pageCount);
        response.put("pdfData", pdfDataUrl);
        return response;
    }

    static String photoFormat(JSONObject request, boolean backgroundRemoved) {
        String requestedFormat = request != null ? request.optString("outputType", "jpeg") : "jpeg";
        return backgroundRemoved || "png".equalsIgnoreCase(requestedFormat) ? "png" : "jpeg";
    }

    static JSONObject photo(
            JSONObject request,
            String format,
            String imageDataUrl,
            boolean backgroundRemoved
    ) throws JSONException {
        JSONObject response = BridgeResponse.base(request, "takePhoto");
        response.put("success", true);
        response.put("format", format);
        response.put("imageData", imageDataUrl);
        response.put("backgroundRemoved", backgroundRemoved);
        String background = request != null ? request.optString("background", "transparent") : "transparent";
        String backgroundColor = request != null ? request.optString("backgroundColor", "#FFFFFF") : "#FFFFFF";
        boolean cropped = request != null && request.optBoolean("cropTransparent", false);
        String camera = request != null ? request.optString("camera", "back") : "back";
        if (backgroundRemoved) {
            response.put("background", background);
            response.put("backgroundColor", backgroundColor);
            response.put("cropped", cropped);
        }
        response.put("camera", camera);
        return response;
    }
}
