package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertTrue;

import org.json.JSONException;
import org.json.JSONObject;
import org.junit.Test;

public class AndroidBridgeScriptBuilderTest {
    @Test
    public void nativeResultScriptWrapsPayloadForHandleNativeResult() throws JSONException {
        String script = AndroidBridgeScriptBuilder.nativeResultScript(new JSONObject()
                .put("action", "settingsGet")
                .put("success", true)
                .put("requestId", "req-1"));

        assertTrue(script.startsWith("if(window.handleNativeResult){window.handleNativeResult("));
        assertTrue(script.endsWith(");}"));
        assertTrue(script.contains("\"action\":\"settingsGet\""));
        assertTrue(script.contains("\"requestId\":\"req-1\""));
    }

    @Test
    public void nativeResultScriptUsesJsonEscapingForStringValues() throws JSONException {
        String script = AndroidBridgeScriptBuilder.nativeResultScript(new JSONObject()
                .put("action", "echo")
                .put("value", "line 1\n\"quoted\""));

        assertTrue(script.contains("\\n"));
        assertTrue(script.contains("\\\"quoted\\\""));
    }
}
