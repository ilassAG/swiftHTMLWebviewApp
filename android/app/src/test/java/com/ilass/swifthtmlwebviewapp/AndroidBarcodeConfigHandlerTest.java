package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.json.JSONException;
import org.json.JSONObject;
import org.junit.Test;

public class AndroidBarcodeConfigHandlerTest {
    @Test
    public void changeConfigRequiresSecurityTokenAndMapsDefaultServerUrl() throws Exception {
        AndroidBarcodeConfigHandler.Result result = AndroidBarcodeConfigHandler.evaluate(
                new JSONObject()
                        .put("toolmode", "changeConfig")
                        .put("securityToken", "token-1")
                        .put("defaultServerUrl", "https://demo.example.invalid")
                        .put("deviceName", "Demo Entry Device")
                        .put("store", new JSONObject().put("siteKey", "Demo Site"))
                        .put("wifi", new JSONObject().put("ssid", "Demo WLAN").put("pw", "secret"))
                        .toString(),
                false,
                "token-1"
        );

        assertEquals(AndroidBarcodeConfigHandler.Kind.CONFIG_CHANGE, result.kind);
        assertEquals("https://demo.example.invalid", result.settings.getString("serverURL"));
        assertEquals("Demo Entry Device", result.settings.getString("deviceName"));
        assertEquals("Demo Site", result.settings.getJSONObject("appConfig").getString("siteKey"));
        assertEquals("Demo WLAN", result.wifiRequest.getString("ssid"));
        assertEquals("secret", result.wifiRequest.getString("password"));
        assertEquals("", result.serverUrl);
    }

    @Test
    public void queryConfigStoresAssociativeValuesAndWifi() throws Exception {
        AndroidBarcodeConfigHandler.Result result = AndroidBarcodeConfigHandler.evaluate(
                "swifthtml-config://set?token=token-1&serverURL=https%3A%2F%2Fdemo.example.invalid%2Fmobile%2F&terminal=A1&store%5BsiteKey%5D=Demo%20Site&wifi%5Bssid%5D=Demo%20WLAN&wifi%5Bpw%5D=secret",
                false,
                "token-1"
        );

        assertEquals(AndroidBarcodeConfigHandler.Kind.CONFIG_CHANGE, result.kind);
        assertEquals("https://demo.example.invalid/mobile/", result.settings.getString("serverURL"));
        assertEquals("Demo Site", result.settings.getJSONObject("appConfig").getString("siteKey"));
        assertEquals("A1", result.settings.getJSONObject("appConfig").getString("terminal"));
        assertTrue(result.hasWifiRequest());
        assertEquals("Demo WLAN", result.wifiRequest.getString("ssid"));
        assertEquals("secret", result.wifiRequest.getString("password"));
    }

    @Test
    public void changeConfigRejectsMissingOrWrongSecurityToken() throws Exception {
        try {
            AndroidBarcodeConfigHandler.evaluate(
                    new JSONObject()
                            .put("toolmode", "changeConfig")
                            .put("securityToken", "wrong")
                            .toString(),
                    false,
                    "expected"
            );
        } catch (JSONException error) {
            assertEquals("Security token mismatch.", error.getMessage());
            return;
        }
        throw new AssertionError("Expected token mismatch.");
    }

    @Test
    public void recoverySourcePersistsServerUrlFromCode() throws Exception {
        AndroidBarcodeConfigHandler.Result result = AndroidBarcodeConfigHandler.evaluate(
                "{\"serverURL\":\"https://recovery.example.invalid\",\"linkId\":\"install-7\"}",
                true,
                ""
        );

        assertEquals(AndroidBarcodeConfigHandler.Kind.RECOVERY_SERVER_URL, result.kind);
        assertEquals("https://recovery.example.invalid/mobile/?link=install-7", result.serverUrl);
        assertEquals(result.serverUrl, result.settings.getString("serverURL"));
    }

    @Test
    public void nonConfigAndNonRecoveryCodesStayStandard() throws Exception {
        AndroidBarcodeConfigHandler.Result result = AndroidBarcodeConfigHandler.evaluate(
                "{\"serverURL\":\"https://recovery.example.invalid\"}",
                false,
                ""
        );

        assertEquals(AndroidBarcodeConfigHandler.Kind.STANDARD_BARCODE, result.kind);
        assertEquals("", result.serverUrl);
        assertFalse(result.settings.has("serverURL"));

        result = AndroidBarcodeConfigHandler.evaluate("ABC-123", true, "");

        assertEquals(AndroidBarcodeConfigHandler.Kind.STANDARD_BARCODE, result.kind);
        assertTrue(result.settings.length() == 0);

        result = AndroidBarcodeConfigHandler.evaluate("https://example.invalid/item?id=123", false, "");

        assertEquals(AndroidBarcodeConfigHandler.Kind.STANDARD_BARCODE, result.kind);
    }
}
