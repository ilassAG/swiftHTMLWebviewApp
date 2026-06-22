package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import com.google.mlkit.vision.barcode.common.Barcode;

import org.json.JSONException;
import org.json.JSONObject;
import org.junit.Test;

public class AndroidBarcodeResponseBuilderTest {
    @Test
    public void successResponseUsesCurrentScannerFields() throws JSONException {
        JSONObject response = AndroidBarcodeResponseBuilder.success(
                request(),
                "ABC-123",
                Barcode.FORMAT_QR_CODE
        );

        assertEquals("android", response.getString("platform"));
        assertEquals("scanBarcode", response.getString("action"));
        assertEquals("req-1", response.getString("requestId"));
        assertEquals("ABC-123", response.getString("code"));
        assertEquals("qr", response.getString("format"));
        assertTrue(response.getBoolean("success"));
    }

    @Test
    public void configChangedResponseIncludesSettingsSnapshot() throws JSONException {
        JSONObject settings = new JSONObject().put("serverURL", "https://example.invalid/mobile/");
        JSONObject response = AndroidBarcodeResponseBuilder.configChanged(request(), settings);

        assertEquals("configChanged", response.getString("code"));
        assertEquals("JSONConfig", response.getString("format"));
        assertTrue(response.getBoolean("success"));
        assertEquals("https://example.invalid/mobile/", response.getJSONObject("settings").getString("serverURL"));
    }

    @Test
    public void recoveryAppliedResponseMarksPersistedServerUrl() throws JSONException {
        JSONObject response = AndroidBarcodeResponseBuilder.recoveryApplied(
                request(),
                "{\"serverURL\":\"https://example.invalid/mobile/\"}",
                Barcode.FORMAT_QR_CODE,
                "https://example.invalid/mobile/"
        );

        assertEquals("qr", response.getString("format"));
        assertTrue(response.getBoolean("success"));
        assertEquals("https://example.invalid/mobile/", response.getString("serverURL"));
        assertTrue(response.getBoolean("serverURLPersisted"));
    }

    @Test
    public void formatNameCoversConfiguredScannerFormats() {
        assertEquals("ean13", AndroidBarcodeResponseBuilder.formatName(Barcode.FORMAT_EAN_13));
        assertEquals("ean8", AndroidBarcodeResponseBuilder.formatName(Barcode.FORMAT_EAN_8));
        assertEquals("code128", AndroidBarcodeResponseBuilder.formatName(Barcode.FORMAT_CODE_128));
        assertEquals("datamatrix", AndroidBarcodeResponseBuilder.formatName(Barcode.FORMAT_DATA_MATRIX));
        assertEquals("aztec", AndroidBarcodeResponseBuilder.formatName(Barcode.FORMAT_AZTEC));
        assertEquals("pdf417", AndroidBarcodeResponseBuilder.formatName(Barcode.FORMAT_PDF417));
        assertEquals("upca", AndroidBarcodeResponseBuilder.formatName(Barcode.FORMAT_UPC_A));
        assertEquals("upce", AndroidBarcodeResponseBuilder.formatName(Barcode.FORMAT_UPC_E));
        assertEquals("unknown", AndroidBarcodeResponseBuilder.formatName(-1));
    }

    private JSONObject request() throws JSONException {
        return new JSONObject()
                .put("action", "scanBarcode")
                .put("requestId", "req-1");
    }
}
