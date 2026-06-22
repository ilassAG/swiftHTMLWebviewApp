package com.ilass.swifthtmlwebviewapp;

import org.json.JSONObject;

final class AndroidBridgeScriptBuilder {
    private AndroidBridgeScriptBuilder() {
    }

    static String nativeResultScript(JSONObject payload) {
        return "if(window.handleNativeResult){window.handleNativeResult(" + payload.toString() + ");}";
    }
}
