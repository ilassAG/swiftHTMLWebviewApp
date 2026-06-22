package com.ilass.swifthtmlwebviewapp;

import org.json.JSONException;
import org.json.JSONObject;

final class AndroidHostBridgePayload {
    private AndroidHostBridgePayload() {
    }

    static JSONObject baseResponse(JSONObject source, String action) throws JSONException {
        return BridgeResponse.base(
                source != null ? source : new JSONObject(),
                action != null ? action : "unknown"
        );
    }

    static JSONObject errorResponse(JSONObject source, String action, String error) throws JSONException {
        return BridgeResponse.error(
                source != null ? source : new JSONObject(),
                action != null ? action : "unknown",
                error != null ? error : "Unknown error"
        );
    }
}
