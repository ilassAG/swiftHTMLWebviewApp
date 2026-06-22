package com.ilass.swifthtmlwebviewapp;

import org.json.JSONException;
import org.json.JSONObject;

final class BridgeDispatcher {
    private BridgeDispatcher() {
    }

    static String action(JSONObject message) {
        if (message == null) {
            return "";
        }
        return message.optString("action", "").trim();
    }

    static JSONObject missingActionResponse(JSONObject message) throws JSONException {
        return BridgeResponse.error(message, "unknown", "Invalid request: Missing 'action' parameter.");
    }

    static JSONObject unknownActionResponse(JSONObject message, String action) throws JSONException {
        return BridgeResponse.error(message, action, "Unknown native action: " + action);
    }

    static JSONObject parseErrorResponse(String error) throws JSONException {
        return BridgeResponse.error(null, "unknown", error);
    }
}
