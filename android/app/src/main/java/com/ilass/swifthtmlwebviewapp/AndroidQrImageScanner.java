package com.ilass.swifthtmlwebviewapp;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;

import com.google.zxing.BarcodeFormat;
import com.google.zxing.BinaryBitmap;
import com.google.zxing.DecodeHintType;
import com.google.zxing.MultiFormatReader;
import com.google.zxing.RGBLuminanceSource;
import com.google.zxing.Result;
import com.google.zxing.common.HybridBinarizer;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.Collections;
import java.util.EnumMap;
import java.util.Map;
import java.util.Base64;

final class AndroidQrImageScanner {
    private AndroidQrImageScanner() {
    }

    static JSONObject response(JSONObject request) throws JSONException {
        try {
            byte[] data = imageData(request);
            Bitmap bitmap = BitmapFactory.decodeByteArray(data, 0, data.length);
            if (bitmap == null) {
                return BridgeResponse.error(request, "qrScanImage", "Image payload could not be decoded.");
            }
            String code = scan(bitmap);
            JSONObject response = BridgeResponse.base(request, "qrScanImage");
            JSONArray codes = new JSONArray();
            if (code.isEmpty()) {
                response.put("success", false);
                response.put("format", "qr");
                response.put("count", 0);
                response.put("codes", codes);
                response.put("error", "No QR code found.");
            } else {
                response.put("success", true);
                response.put("format", "qr");
                response.put("count", 1);
                response.put("code", code);
                codes.put(new JSONObject().put("code", code).put("format", "qr"));
                response.put("codes", codes);
            }
            return response;
        } catch (IllegalArgumentException error) {
            return BridgeResponse.error(request, "qrScanImage", error.getMessage());
        }
    }

    static byte[] imageData(JSONObject request) {
        String raw = firstNonEmpty(
                request.optString("imageBase64", ""),
                request.optString("imageData", ""),
                request.optString("dataUrl", ""),
                request.optString("dataURL", ""),
                request.optString("image", "")
        );
        if (raw.isEmpty()) {
            throw new IllegalArgumentException("imageBase64 or dataUrl is required.");
        }
        String base64 = stripDataUrlPrefix(raw.trim());
        try {
            return Base64.getDecoder().decode(base64.replaceAll("\\s+", ""));
        } catch (IllegalArgumentException error) {
            throw new IllegalArgumentException("Image payload is not valid base64.");
        }
    }

    private static String scan(Bitmap bitmap) {
        int width = bitmap.getWidth();
        int height = bitmap.getHeight();
        int[] pixels = new int[width * height];
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height);

        RGBLuminanceSource source = new RGBLuminanceSource(width, height, pixels);
        BinaryBitmap binaryBitmap = new BinaryBitmap(new HybridBinarizer(source));
        Map<DecodeHintType, Object> hints = new EnumMap<>(DecodeHintType.class);
        hints.put(DecodeHintType.POSSIBLE_FORMATS, Collections.singletonList(BarcodeFormat.QR_CODE));
        try {
            Result result = new MultiFormatReader().decode(binaryBitmap, hints);
            return result != null && result.getText() != null ? result.getText() : "";
        } catch (Exception ignored) {
            return "";
        }
    }

    private static String stripDataUrlPrefix(String value) {
        int comma = value.indexOf(',');
        if (comma > 0 && value.substring(0, comma).toLowerCase(java.util.Locale.US).startsWith("data:")) {
            return value.substring(comma + 1);
        }
        return value;
    }

    private static String firstNonEmpty(String... values) {
        for (String value : values) {
            if (value != null && !value.trim().isEmpty()) {
                return value.trim();
            }
        }
        return "";
    }
}
