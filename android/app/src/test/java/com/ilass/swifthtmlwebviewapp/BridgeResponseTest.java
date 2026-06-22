package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;

import org.json.JSONException;
import org.json.JSONObject;
import org.junit.Test;

public class BridgeResponseTest {
    @Test
    public void baseResponseIncludesPlatformActionRequestAndPaymentIds() throws JSONException {
        JSONObject response = BridgeResponse.base(new JSONObject()
                .put("requestId", "req-1")
                .put("paymentId", "pay-1"), "tapToPayCollect");

        assertEquals("android", response.getString("platform"));
        assertEquals("tapToPayCollect", response.getString("action"));
        assertEquals("req-1", response.getString("requestId"));
        assertEquals("pay-1", response.getString("paymentId"));
    }

    @Test
    public void errorResponseUsesCommonShape() throws JSONException {
        JSONObject response = BridgeResponse.error(
                new JSONObject().put("requestId", "req-2"),
                "settingsSet",
                "securityToken is required for settingsSet."
        );

        assertEquals("android", response.getString("platform"));
        assertEquals("settingsSet", response.getString("action"));
        assertEquals("req-2", response.getString("requestId"));
        assertFalse(response.getBoolean("success"));
        assertEquals("securityToken is required for settingsSet.", response.getString("error"));
    }

    @Test
    public void unavailableResponseMarksAvailability() throws JSONException {
        JSONObject response = BridgeResponse.unavailable(
                new JSONObject().put("requestId", "req-3"),
                "arPositionStart",
                "Not available."
        );

        assertFalse(response.getBoolean("success"));
        assertFalse(response.getBoolean("available"));
        assertEquals("Not available.", response.getString("error"));
    }
}
