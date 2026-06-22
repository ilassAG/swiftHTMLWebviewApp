package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;

import org.json.JSONException;
import org.json.JSONObject;
import org.junit.Test;

public class AndroidRecoveryConfigParserTest {
    @Test
    public void parsesDirectServerUrlFromJsonAndAddsLink() {
        String rawCode = "{"
                + "\"serverURL\":\" https://example.invalid \","
                + "\"linkId\":\" install-42 \""
                + "}";

        assertEquals(
                "https://example.invalid/mobile/?link=install-42",
                AndroidRecoveryConfigParser.serverUrlFromCode(rawCode)
        );
    }

    @Test
    public void parsesBackendUrlFallbackFromJson() {
        String rawCode = "{"
                + "\"backendUrl\":\"https://backend.invalid/api\","
                + "\"linkId\":\"abc\""
                + "}";

        assertEquals(
                "https://backend.invalid/api?link=abc",
                AndroidRecoveryConfigParser.serverUrlFromCode(rawCode)
        );
    }

    @Test
    public void keepsExistingLinkAndRemovesFragment() {
        assertEquals(
                "https://example.invalid/mobile/?link=existing",
                AndroidRecoveryConfigParser.serverUrlFromCode("https://example.invalid/mobile/?link=existing#ignored")
        );
    }

    @Test
    public void rejectsBlankAndNonHttpValues() {
        assertEquals("", AndroidRecoveryConfigParser.serverUrlFromCode(" "));
        assertEquals("", AndroidRecoveryConfigParser.serverUrlFromCode("ftp://example.invalid/mobile/"));
        assertEquals("", AndroidRecoveryConfigParser.serverUrlFromCode("{\"serverURL\":\"not a url\"}"));
    }

    @Test
    public void extractsServerUrlFromPayloadAliases() throws JSONException {
        JSONObject payload = new JSONObject()
                .put("defaultServerUrl", "https://alias.invalid")
                .put("linkId", "alias-link");

        assertEquals(
                "https://alias.invalid/mobile/?link=alias-link",
                AndroidRecoveryConfigParser.serverUrlFromPayload(payload)
        );
    }
}
