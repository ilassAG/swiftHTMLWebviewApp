package com.ilass.swifthtmlwebviewapp;

import com.google.mlkit.vision.barcode.common.Barcode;

import org.json.JSONException;
import org.json.JSONObject;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

final class AndroidContinuousScannerEventBuilder {
    private AndroidContinuousScannerEventBuilder() {
    }

    static JSONObject event(AndroidContinuousScannerConfig config, String code, Barcode barcode, long timestampMs) throws JSONException {
        int format = barcode != null ? barcode.getFormat() : Barcode.FORMAT_UNKNOWN;
        return event(config, code, AndroidBarcodeResponseBuilder.formatName(format), timestampMs);
    }

    static JSONObject event(AndroidContinuousScannerConfig config, String code, String format, long timestampMs) throws JSONException {
        JSONObject event = new JSONObject();
        event.put("platform", "android");
        event.put("action", eventAction(config.mode));
        event.put("sourceAction", config.action);
        event.put("mode", config.mode);
        event.put("camera", config.camera);
        event.put("code", code != null ? code : "");
        event.put("format", format != null ? format : "unknown");
        event.put("timestamp", timestamp(timestampMs));
        return event;
    }

    static String eventAction(String mode) {
        return "login".equals(mode) ? "barcodeLogin" : "barcodeData";
    }

    static String timestamp(long timeMs) {
        return new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", Locale.US).format(new Date(timeMs));
    }
}
