package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.json.JSONException;
import org.json.JSONObject;
import org.junit.Test;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;

public class AndroidBridgeRouterTest {
    @Test
    public void postMessageRoutesKnownActions() throws JSONException {
        List<JSONObject> results = new ArrayList<>();
        AtomicInteger calls = new AtomicInteger(0);
        AndroidBridgeRouter router = new AndroidBridgeRouter.Builder(results::add)
                .on("settingsGet", message -> {
                    calls.incrementAndGet();
                    results.add(BridgeResponse.base(message, "settingsGet").put("success", true));
                })
                .build();

        router.postMessage("{\"action\":\" settingsGet \",\"requestId\":\"req-1\"}");

        assertEquals(1, calls.get());
        assertEquals(1, results.size());
        assertEquals("settingsGet", results.get(0).getString("action"));
        assertEquals("req-1", results.get(0).getString("requestId"));
        assertTrue(results.get(0).getBoolean("success"));
    }

    @Test
    public void postMessageReturnsStructuredMissingActionError() throws JSONException {
        List<JSONObject> results = new ArrayList<>();
        AndroidBridgeRouter router = new AndroidBridgeRouter.Builder(results::add).build();

        router.postMessage("{\"requestId\":\"req-2\"}");

        assertEquals(1, results.size());
        assertEquals("unknown", results.get(0).getString("action"));
        assertEquals("req-2", results.get(0).getString("requestId"));
        assertFalse(results.get(0).getBoolean("success"));
        assertEquals("Invalid request: Missing 'action' parameter.", results.get(0).getString("error"));
    }

    @Test
    public void postMessageReturnsStructuredUnknownActionError() throws JSONException {
        List<JSONObject> results = new ArrayList<>();
        AndroidBridgeRouter router = new AndroidBridgeRouter.Builder(results::add).build();

        router.postMessage("{\"action\":\"madeUpAction\",\"requestId\":\"req-3\"}");

        assertEquals(1, results.size());
        assertEquals("madeUpAction", results.get(0).getString("action"));
        assertEquals("req-3", results.get(0).getString("requestId"));
        assertFalse(results.get(0).getBoolean("success"));
        assertEquals("Unknown native action: madeUpAction", results.get(0).getString("error"));
    }

    @Test
    public void postMessageReturnsStructuredParseError() throws JSONException {
        List<JSONObject> results = new ArrayList<>();
        AndroidBridgeRouter router = new AndroidBridgeRouter.Builder(results::add).build();

        router.postMessage("{not-json");

        assertEquals(1, results.size());
        assertEquals("unknown", results.get(0).getString("action"));
        assertFalse(results.get(0).getBoolean("success"));
        assertTrue(results.get(0).getString("error").length() > 0);
    }

    @Test
    public void builderRegistersGroupedActions() throws JSONException {
        List<JSONObject> results = new ArrayList<>();
        AndroidBridgeRouter router = new AndroidBridgeRouter.Builder(results::add)
                .onAll(message -> results.add(BridgeResponse.base(message, message.getString("action"))),
                        "continuousScanStart",
                        "dataScanStart",
                        "loginScanStart")
                .build();

        assertTrue(router.actions().contains("continuousScanStart"));
        assertTrue(router.actions().contains("dataScanStart"));
        assertTrue(router.actions().contains("loginScanStart"));
    }
}
