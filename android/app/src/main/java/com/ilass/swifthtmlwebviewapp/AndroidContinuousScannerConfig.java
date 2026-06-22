package com.ilass.swifthtmlwebviewapp;

import com.google.mlkit.vision.barcode.common.Barcode;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.Locale;

final class AndroidContinuousScannerConfig {
    final String action;
    final String mode;
    final String purpose;
    String camera;
    final JSONArray types;
    final long repeatDelayMs;
    final boolean showCloseButton;
    final boolean showFlipButton;
    RectPercent rect;

    private AndroidContinuousScannerConfig(
            String action,
            String mode,
            String purpose,
            String camera,
            JSONArray types,
            long repeatDelayMs,
            RectPercent rect,
            boolean showCloseButton,
            boolean showFlipButton
    ) {
        this.action = action;
        this.mode = mode;
        this.purpose = purpose;
        this.camera = camera;
        this.types = types;
        this.repeatDelayMs = repeatDelayMs;
        this.rect = rect;
        this.showCloseButton = showCloseButton;
        this.showFlipButton = showFlipButton;
    }

    static AndroidContinuousScannerConfig from(JSONObject request) {
        JSONObject source = request != null ? request : new JSONObject();
        String action = source.optString("action", "continuousScanStart");
        String purpose = scannerPurpose(source);
        String mode = nonEmpty(source.optString("mode", ""), "configPairing".equals(purpose) ? "configPairing" : ("loginScanStart".equals(action) ? "login" : "data"));
        String camera = nonEmpty(source.optString("camera", ""), "configPairing".equals(purpose) || "loginScanStart".equals(action) ? "front" : "back");
        JSONArray types = scannerTypes(source, purpose);
        double repeatDelaySeconds = source.has("repeatDelaySeconds")
                ? source.optDouble("repeatDelaySeconds", 1.5)
                : source.optDouble("repeatDelay", 1.5);
        long repeatDelayMs = Math.max(100L, Math.round(repeatDelaySeconds * 1000.0));
        RectPercent rect = RectPercent.from(source.optJSONObject("previewRect"), RectPercent.defaults());
        boolean showCloseButton = source.optBoolean("showCloseButton", source.optBoolean("closeButton", true));
        boolean showFlipButton = source.optBoolean("showFlipButton",
                source.optBoolean("flipButton", source.optBoolean("allowCameraFlip", "configPairing".equals(purpose))));
        return new AndroidContinuousScannerConfig(action, mode, purpose, camera, types, repeatDelayMs, rect, showCloseButton, showFlipButton);
    }

    JSONObject response(JSONObject request, String action, boolean success) throws JSONException {
        JSONObject response = baseResponse(request, action);
        response.put("success", success);
        response.put("mode", mode);
        response.put("purpose", purpose);
        response.put("camera", camera);
        response.put("repeatDelaySeconds", repeatDelayMs / 1000.0);
        response.put("previewRect", rect.toJson());
        response.put("showCloseButton", showCloseButton);
        response.put("showFlipButton", showFlipButton);
        response.put("provider", "android_camerax_mlkit");
        if (types != null) {
            response.put("types", types);
        }
        return response;
    }

    static JSONObject stopResponse(JSONObject request) throws JSONException {
        JSONObject source = request != null ? request : new JSONObject();
        JSONObject response = baseResponse(source, source.optString("action", "continuousScanStop"));
        response.put("success", true);
        return response;
    }

    static JSONObject errorResponse(JSONObject request, String action, String message) throws JSONException {
        JSONObject response = baseResponse(request, action);
        response.put("success", false);
        response.put("error", message != null ? message : "");
        return response;
    }

    static JSONObject closedByUserResponse(JSONObject request) throws JSONException {
        JSONObject response = baseResponse(request, "continuousScanStop");
        response.put("success", true);
        response.put("closedByUser", true);
        return response;
    }

    static JSONObject baseResponse(JSONObject request, String action) throws JSONException {
        JSONObject response = new JSONObject();
        response.put("platform", "android");
        response.put("action", action);
        if (request != null && request.has("requestId")) {
            response.put("requestId", request.optString("requestId"));
        }
        return response;
    }

    static int[] barcodeFormats(JSONArray types) {
        if (types == null || types.length() == 0) {
            return new int[]{
                    Barcode.FORMAT_QR_CODE,
                    Barcode.FORMAT_EAN_13,
                    Barcode.FORMAT_EAN_8,
                    Barcode.FORMAT_CODE_128,
                    Barcode.FORMAT_DATA_MATRIX
            };
        }

        java.util.ArrayList<Integer> formats = new java.util.ArrayList<>();
        for (int i = 0; i < types.length(); i += 1) {
            int format = barcodeFormat(types.optString(i, ""));
            if (format != 0 && !formats.contains(format)) {
                formats.add(format);
            }
        }

        int[] result = new int[formats.size()];
        for (int i = 0; i < formats.size(); i += 1) {
            result[i] = formats.get(i);
        }
        return result;
    }

    static int barcodeFormat(String value) {
        switch (value.toLowerCase(Locale.US)) {
            case "qr": return Barcode.FORMAT_QR_CODE;
            case "ean13": return Barcode.FORMAT_EAN_13;
            case "ean8": return Barcode.FORMAT_EAN_8;
            case "code128": return Barcode.FORMAT_CODE_128;
            case "code39": return Barcode.FORMAT_CODE_39;
            case "code93": return Barcode.FORMAT_CODE_93;
            case "datamatrix": return Barcode.FORMAT_DATA_MATRIX;
            case "aztec": return Barcode.FORMAT_AZTEC;
            case "pdf417": return Barcode.FORMAT_PDF417;
            case "upca": return Barcode.FORMAT_UPC_A;
            case "upce": return Barcode.FORMAT_UPC_E;
            case "itf":
            case "itf14":
            case "interleaved2of5": return Barcode.FORMAT_ITF;
            default: return 0;
        }
    }

    private static String nonEmpty(String value, String fallback) {
        String trimmed = value == null ? "" : value.trim();
        return trimmed.isEmpty() ? fallback : trimmed;
    }

    private static String scannerPurpose(JSONObject source) {
        String purpose = nonEmpty(source.optString("purpose", ""), "");
        if ("configPairing".equals(purpose)) {
            return purpose;
        }
        String sourceValue = nonEmpty(source.optString("source", ""), "");
        return "configPairing".equals(sourceValue) ? sourceValue : "";
    }

    private static JSONArray scannerTypes(JSONObject source, String purpose) {
        JSONArray requested = source.optJSONArray("types");
        if (requested != null && requested.length() > 0) {
            return requested;
        }
        if ("configPairing".equals(purpose)) {
            return new JSONArray().put("qr");
        }
        return requested;
    }

    static final class RectPercent {
        final double top;
        final double left;
        final double width;
        final double height;

        private RectPercent(double top, double left, double width, double height) {
            this.top = top;
            this.left = left;
            this.width = width;
            this.height = height;
        }

        static RectPercent defaults() {
            return new RectPercent(0.18, 0.10, 0.80, 0.36);
        }

        static RectPercent from(JSONObject json, RectPercent fallback) {
            if (json == null) {
                return fallback;
            }
            double width = clamp(sizeValue(json, "width", fallback.width), 0.1, 1.0);
            double height = clamp(sizeValue(json, "height", fallback.height), 0.1, 1.0);
            double left = clamp(positionValue(json, "left", "x", fallback.left), 0.0, 1.0 - width);
            double top = clamp(positionValue(json, "top", "y", fallback.top), 0.0, 1.0 - height);
            return new RectPercent(top, left, width, height);
        }

        JSONObject toJson() throws JSONException {
            JSONObject json = new JSONObject();
            json.put("top", top);
            json.put("left", left);
            json.put("width", width);
            json.put("height", height);
            return json;
        }

        private static double positionValue(JSONObject json, String key, String alias, double fallback) {
            if (json.has(key)) {
                return normalize(json.optDouble(key, fallback));
            }
            return normalize(json.optDouble(alias, fallback));
        }

        private static double sizeValue(JSONObject json, String key, double fallback) {
            return normalize(json.optDouble(key, fallback));
        }

        private static double normalize(double value) {
            return value > 1.0 ? value / 100.0 : value;
        }

        private static double clamp(double value, double min, double max) {
            return Math.max(min, Math.min(max, value));
        }
    }
}
