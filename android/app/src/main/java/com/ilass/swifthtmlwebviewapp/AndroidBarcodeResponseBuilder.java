package com.ilass.swifthtmlwebviewapp;

import com.google.mlkit.vision.barcode.common.Barcode;

import org.json.JSONException;
import org.json.JSONObject;

final class AndroidBarcodeResponseBuilder {
    private AndroidBarcodeResponseBuilder() {
    }

    static JSONObject success(JSONObject request, String code, int barcodeFormat) throws JSONException {
        return success(request, code, formatName(barcodeFormat));
    }

    static JSONObject success(JSONObject request, String code, String format) throws JSONException {
        JSONObject response = BridgeResponse.base(request, "scanBarcode");
        response.put("success", true);
        response.put("code", code != null ? code : "");
        response.put("format", format != null ? format : "unknown");
        return response;
    }

    static JSONObject configChanged(JSONObject request, JSONObject settings) throws JSONException {
        JSONObject response = success(request, "configChanged", "JSONConfig");
        response.put("success", true);
        response.put("settings", settings != null ? settings : new JSONObject());
        return response;
    }

    static JSONObject recoveryApplied(JSONObject request, String code, int barcodeFormat, String serverUrl) throws JSONException {
        JSONObject response = success(request, code, barcodeFormat);
        response.put("success", true);
        response.put("serverURL", serverUrl);
        response.put("serverURLPersisted", true);
        return response;
    }

    static String formatName(int format) {
        switch (format) {
            case Barcode.FORMAT_QR_CODE: return "qr";
            case Barcode.FORMAT_EAN_13: return "ean13";
            case Barcode.FORMAT_EAN_8: return "ean8";
            case Barcode.FORMAT_CODE_128: return "code128";
            case Barcode.FORMAT_CODE_39: return "code39";
            case Barcode.FORMAT_CODE_93: return "code93";
            case Barcode.FORMAT_DATA_MATRIX: return "datamatrix";
            case Barcode.FORMAT_PDF417: return "pdf417";
            case Barcode.FORMAT_AZTEC: return "aztec";
            case Barcode.FORMAT_UPC_A: return "upca";
            case Barcode.FORMAT_UPC_E: return "upce";
            case Barcode.FORMAT_ITF: return "itf";
            default: return "unknown";
        }
    }
}
