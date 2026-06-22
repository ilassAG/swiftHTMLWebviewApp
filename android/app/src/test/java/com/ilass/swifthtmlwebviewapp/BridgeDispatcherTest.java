package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;

import org.json.JSONException;
import org.json.JSONObject;
import org.junit.Test;

public class BridgeDispatcherTest {
    @Test
    public void actionTrimsValidActions() throws JSONException {
        assertEquals("settingsGet", BridgeDispatcher.action(new JSONObject().put("action", " settingsGet ")));
    }

    @Test
    public void actionRejectsMissingAndBlankActions() throws JSONException {
        assertEquals("", BridgeDispatcher.action(new JSONObject()));
        assertEquals("", BridgeDispatcher.action(new JSONObject().put("action", "  ")));
        assertEquals("", BridgeDispatcher.action(null));
    }

    @Test
    public void missingActionResponseUsesStructuredErrorShape() throws JSONException {
        JSONObject response = BridgeDispatcher.missingActionResponse(
                new JSONObject().put("requestId", "req-1")
        );

        assertEquals("android", response.getString("platform"));
        assertEquals("unknown", response.getString("action"));
        assertEquals("req-1", response.getString("requestId"));
        assertEquals(false, response.getBoolean("success"));
        assertEquals("Invalid request: Missing 'action' parameter.", response.getString("error"));
    }

    @Test
    public void unknownActionResponseEchoesUnknownAction() throws JSONException {
        JSONObject response = BridgeDispatcher.unknownActionResponse(
                new JSONObject().put("requestId", "req-2"),
                "madeUpAction"
        );

        assertEquals("android", response.getString("platform"));
        assertEquals("madeUpAction", response.getString("action"));
        assertEquals("req-2", response.getString("requestId"));
        assertEquals(false, response.getBoolean("success"));
        assertEquals("Unknown native action: madeUpAction", response.getString("error"));
    }
}
