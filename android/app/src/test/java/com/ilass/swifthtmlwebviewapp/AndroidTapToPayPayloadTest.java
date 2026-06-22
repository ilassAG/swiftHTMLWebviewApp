package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.json.JSONObject;
import org.junit.Test;

public class AndroidTapToPayPayloadTest {
    @Test
    public void availabilityUnavailableUsesContractEnvelope() throws Exception {
        JSONObject response = AndroidTapToPayPayload.availabilityUnavailable(
                new JSONObject().put("requestId", "req-availability")
        );

        assertEquals("android", response.getString("platform"));
        assertEquals("tapToPayAvailability", response.getString("action"));
        assertEquals("req-availability", response.getString("requestId"));
        assertTrue(response.getBoolean("success"));
        assertFalse(response.getBoolean("available"));
        assertEquals("android_tap_to_pay", response.getString("readerType"));
        assertTrue(response.getString("reason").contains("not included"));
    }

    @Test
    public void collectUnavailableUsesSharedErrorEnvelope() throws Exception {
        JSONObject response = AndroidTapToPayPayload.collectUnavailable(
                new JSONObject()
                        .put("requestId", "req-collect")
                        .put("paymentId", "payment-1")
        );

        assertEquals("android", response.getString("platform"));
        assertEquals("tapToPayCollect", response.getString("action"));
        assertEquals("req-collect", response.getString("requestId"));
        assertEquals("payment-1", response.getString("paymentId"));
        assertFalse(response.getBoolean("success"));
        assertTrue(response.getString("error").contains("not included"));
    }
}
