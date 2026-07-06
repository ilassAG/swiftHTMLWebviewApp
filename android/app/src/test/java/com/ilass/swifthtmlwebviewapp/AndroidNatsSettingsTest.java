package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.json.JSONException;
import org.json.JSONObject;
import org.junit.Test;

public class AndroidNatsSettingsTest {
    @Test
    public void provisionPayloadKeepsUrlsEmptyUntilProvisionedAndNormalizesClientName() throws Exception {
        AndroidNatsSettings settings = AndroidNatsSettings.fromPayload(new JSONObject()
                .put("enabled", true)
                .put("auth", new JSONObject().put("method", "creds")), new AndroidNatsSettings());

        assertTrue(settings.enabled);
        assertEquals(AndroidNatsSettings.DEFAULT_URLS, settings.urls);
        assertEquals("creds", settings.authMethod);
        assertEquals("swift-wrapper-APP-123", settings.clientName("APP-123"));
        assertEquals("swift.wrapper.APP-123", settings.devicePrefix("APP-123"));
        assertEquals("swift.wrapper.APP-123.commands.*", settings.commandSubject("APP-123"));
        assertEquals("swift.wrapper.APP-123.events.responses", settings.responseSubject("APP-123"));
        assertEquals("swift.wrapper.APP-123.status", settings.statusSubject("APP-123"));
    }

    @Test
    public void rejectsInvalidUrlSchemes() throws Exception {
        try {
            AndroidNatsSettings.fromPayload(new JSONObject()
                    .put("enabled", true)
                    .put("urls", new org.json.JSONArray().put("http://example.invalid:4222"))
                    .put("auth", new JSONObject().put("method", "creds")), new AndroidNatsSettings());
        } catch (JSONException error) {
            assertEquals("Invalid NATS URL: http://example.invalid:4222", error.getMessage());
            return;
        }
        throw new AssertionError("Expected invalid URL error.");
    }

    @Test
    public void storedJsonDoesNotContainSecretFields() throws Exception {
        AndroidNatsSettings settings = AndroidNatsSettings.fromPayload(new JSONObject()
                .put("enabled", true)
                .put("urls", new org.json.JSONArray().put("tls://nats.example.invalid:4222"))
                .put("auth", new JSONObject()
                        .put("method", "creds")
                        .put("creds", "SECRET")), new AndroidNatsSettings());

        String raw = settings.toStoredJson().toString();

        assertTrue(raw.contains("\"method\":\"creds\""));
        assertFalse(raw.contains("SECRET"));
        assertFalse(raw.contains("credentialRef"));
    }

    @Test
    public void redactedSnapshotContainsCredentialFlagOnly() throws Exception {
        AndroidNatsSettings settings = new AndroidNatsSettings();
        settings.enabled = true;
        settings.urls.add("tls://nats.example.invalid:4222");

        JSONObject snapshot = settings.redactedSnapshot("APP-123", true, false, "offline");
        JSONObject auth = snapshot.getJSONObject("auth");

        assertEquals("swift-wrapper-APP-123", snapshot.getString("clientName"));
        assertEquals("creds", auth.getString("method"));
        assertTrue(auth.getBoolean("credentialSet"));
        assertFalse(auth.has("creds"));
        assertEquals("offline", snapshot.getString("lastError"));
        assertEquals("swift.wrapper.APP-123.commands.*", snapshot.getJSONObject("subjects").getString("commandSubject"));
    }
}
