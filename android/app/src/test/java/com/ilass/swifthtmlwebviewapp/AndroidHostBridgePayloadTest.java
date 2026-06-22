package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;

import org.json.JSONException;
import org.json.JSONObject;
import org.junit.Test;

public class AndroidHostBridgePayloadTest {
    @Test
    public void baseResponseUsesSharedBridgeEnvelope() throws JSONException {
        JSONObject response = AndroidHostBridgePayload.baseResponse(
                new JSONObject().put("requestId", "req-1"),
                "tapToPayCollect"
        );

        assertEquals("android", response.getString("platform"));
        assertEquals("tapToPayCollect", response.getString("action"));
        assertEquals("req-1", response.getString("requestId"));
    }

    @Test
    public void errorResponseDefaultsMissingInputs() throws JSONException {
        JSONObject response = AndroidHostBridgePayload.errorResponse(null, null, null);

        assertEquals("android", response.getString("platform"));
        assertEquals("unknown", response.getString("action"));
        assertFalse(response.getBoolean("success"));
        assertEquals("Unknown error", response.getString("error"));
    }

    @Test
    public void errorResponseUsesSharedBridgeErrorEnvelope() throws JSONException {
        JSONObject response = AndroidHostBridgePayload.errorResponse(
                new JSONObject().put("requestId", "req-2"),
                "printerPrint",
                "No printer"
        );

        assertEquals("android", response.getString("platform"));
        assertEquals("printerPrint", response.getString("action"));
        assertEquals("req-2", response.getString("requestId"));
        assertFalse(response.getBoolean("success"));
        assertEquals("No printer", response.getString("error"));
    }
}
