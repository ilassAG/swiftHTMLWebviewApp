package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

public class AndroidWifiBridgeTest {
    @Test
    public void configureRequestTrimsSsidAndPrefersPassphraseAlias() throws Exception {
        AndroidWifiBridge.ConfigureRequest request = AndroidWifiBridge.configureRequest(new JSONObject()
                .put("requestId", "req-1")
                .put("ssid", "  Standort-WLAN  ")
                .put("password", " old-password ")
                .put("passphrase", " new-password "), "");

        assertEquals("Standort-WLAN", request.ssid);
        assertEquals("new-password", request.passphrase);
        assertEquals("req-1", request.request.getString("requestId"));
        assertFalse(request.request.optBoolean("serverURLPersisted", false));
    }

    @Test
    public void configureRequestFallsBackToPasswordAndMarksPersistedServerUrl() throws Exception {
        AndroidWifiBridge.ConfigureRequest request = AndroidWifiBridge.configureRequest(new JSONObject()
                .put("ssid", "Test")
                .put("password", " legacy-password "), " https://example.invalid/mobile/ ");

        assertEquals("legacy-password", request.passphrase);
        assertEquals("https://example.invalid/mobile/", request.request.getString("serverURL"));
        assertTrue(request.request.getBoolean("serverURLPersisted"));
    }

    @Test
    public void missingSSIDResponseUsesCommonErrorShape() throws Exception {
        JSONObject response = AndroidWifiBridge.missingSSIDResponse(new JSONObject().put("requestId", "req-2"));

        assertEquals("android", response.getString("platform"));
        assertEquals("wifiConfigure", response.getString("action"));
        assertEquals("req-2", response.getString("requestId"));
        assertFalse(response.getBoolean("success"));
        assertEquals("ssid is required.", response.getString("error"));
    }

    @Test
    public void configureErrorResponseUsesCommonErrorShape() throws Exception {
        JSONObject response = AndroidWifiBridge.configureErrorResponse(
                new JSONObject().put("requestId", "req-error"),
                "broken json"
        );

        assertEquals("android", response.getString("platform"));
        assertEquals("wifiConfigure", response.getString("action"));
        assertEquals("req-error", response.getString("requestId"));
        assertFalse(response.getBoolean("success"));
        assertEquals("broken json", response.getString("error"));
    }

    @Test
    public void addNetworksResultResponseIncludesUserApprovalAndPersistence() throws Exception {
        JSONObject request = new JSONObject()
                .put("serverURL", "https://example.invalid/mobile/")
                .put("serverURLPersisted", true);

        JSONObject success = AndroidWifiBridge.addNetworksResultResponse(request, true);
        assertTrue(success.getBoolean("success"));
        assertEquals("ACTION_WIFI_ADD_NETWORKS", success.getString("method"));
        assertTrue(success.getBoolean("userApproved"));
        assertEquals("https://example.invalid/mobile/", success.getString("serverURL"));
        assertTrue(success.getBoolean("serverURLPersisted"));

        JSONObject cancelled = AndroidWifiBridge.addNetworksResultResponse(request, false);
        assertFalse(cancelled.getBoolean("success"));
        assertFalse(cancelled.getBoolean("userApproved"));
        assertTrue(cancelled.getString("error").contains("cancelled or denied"));
    }

    @Test
    public void networkSuggestionAndLegacyResponsesKeepMethodSpecificFields() throws Exception {
        JSONObject failedSuggestion = AndroidWifiBridge.networkSuggestionResponse(new JSONObject(), 7, false);
        assertFalse(failedSuggestion.getBoolean("success"));
        assertEquals("WifiNetworkSuggestion", failedSuggestion.getString("method"));
        assertEquals(7, failedSuggestion.getInt("status"));
        assertTrue(failedSuggestion.getString("error").contains("status 7"));

        JSONObject legacy = AndroidWifiBridge.legacyConfigurationResponse(new JSONObject(), 42, true);
        assertTrue(legacy.getBoolean("success"));
        assertEquals("WifiConfiguration", legacy.getString("method"));
        assertEquals(42, legacy.getInt("networkId"));
    }

    @Test
    public void statusResponseWrapsWifiPayloadAndQuoteEscapesLegacyValues() throws Exception {
        JSONObject wifi = new JSONObject().put("ssidAvailable", false);
        JSONObject response = AndroidWifiBridge.statusResponse(new JSONObject().put("requestId", "req-3"), wifi);

        assertTrue(response.getBoolean("success"));
        assertEquals("wifiStatusGet", response.getString("action"));
        assertEquals("req-3", response.getString("requestId"));
        assertEquals(wifi, response.getJSONObject("wifi"));
        assertEquals("\"Standort\\\"WLAN\"", AndroidWifiBridge.quoteWifiValue("Standort\"WLAN"));
    }

    @Test
    public void statusPayloadReportsMissingWifiServiceWithStableDefaults() throws Exception {
        AndroidWifiBridge.StatusSnapshot snapshot = new AndroidWifiBridge.StatusSnapshot();
        snapshot.cidrs = new JSONArray().put("192.168.1.20/24");
        snapshot.ipAddresses = new JSONArray().put("192.168.1.20");
        snapshot.wifiServiceAvailable = false;

        JSONObject response = AndroidWifiBridge.statusPayload(snapshot);

        assertEquals("192.168.1.20/24", response.getJSONArray("cidrs").getString(0));
        assertEquals("192.168.1.20", response.getJSONArray("ipAddresses").getString(0));
        assertFalse(response.getBoolean("ssidAvailable"));
        assertEquals("unavailable", response.getString("ssid"));
        assertEquals("unknown", response.getString("securityType"));
        assertTrue(response.isNull("securityTypeRawValue"));
        assertFalse(response.getBoolean("wifiEnabled"));
        assertEquals(0, response.getJSONArray("wifiIpAddresses").length());
        assertEquals("Wi-Fi service is not available.", response.getString("unavailableReason"));
    }

    @Test
    public void statusPayloadRedactsSsidWhenPermissionIsMissing() throws Exception {
        AndroidWifiBridge.StatusSnapshot snapshot = new AndroidWifiBridge.StatusSnapshot();
        snapshot.wifiEnabled = true;
        snapshot.connectionInfoAvailable = true;
        snapshot.wifiIpAddresses = new JSONArray().put("10.0.0.5");
        snapshot.ssid = "\"Office\"";
        snapshot.bssid = "00:11:22:33:44:55";
        snapshot.rssi = -61;
        snapshot.linkSpeedMbps = 144;
        snapshot.ipAddress = "10.0.0.5";
        snapshot.hasWifiDetailsPermission = false;

        JSONObject response = AndroidWifiBridge.statusPayload(snapshot);

        assertTrue(response.getBoolean("wifiEnabled"));
        assertFalse(response.getBoolean("ssidAvailable"));
        assertEquals("unavailable", response.getString("ssid"));
        assertEquals("00:11:22:33:44:55", response.getString("bssid"));
        assertEquals(-61, response.getInt("rssi"));
        assertEquals(144, response.getInt("linkSpeedMbps"));
        assertEquals("10.0.0.5", response.getString("ipAddress"));
        assertEquals("Location permission is required before Android exposes SSID/BSSID details to apps.", response.getString("unavailableReason"));
    }

    @Test
    public void statusPayloadExposesConnectedWifiDetailsAndSecurity() throws Exception {
        AndroidWifiBridge.StatusSnapshot snapshot = new AndroidWifiBridge.StatusSnapshot();
        snapshot.wifiEnabled = true;
        snapshot.connectionInfoAvailable = true;
        snapshot.hasWifiDetailsPermission = true;
        snapshot.wifiIpAddresses = new JSONArray().put("10.0.0.5");
        snapshot.ssid = "\"Office\"";
        snapshot.bssid = null;
        snapshot.rssi = -51;
        snapshot.linkSpeedMbps = 286;
        snapshot.ipAddress = "10.0.0.5";
        snapshot.securityTypeRawValue = 2;
        snapshot.securityType = "personal";

        JSONObject response = AndroidWifiBridge.statusPayload(snapshot);

        assertTrue(response.getBoolean("ssidAvailable"));
        assertEquals("Office", response.getString("ssid"));
        assertEquals("", response.getString("bssid"));
        assertEquals(2, response.getInt("securityTypeRawValue"));
        assertEquals("personal", response.getString("securityType"));
        assertFalse(response.has("unavailableReason"));
    }
}
