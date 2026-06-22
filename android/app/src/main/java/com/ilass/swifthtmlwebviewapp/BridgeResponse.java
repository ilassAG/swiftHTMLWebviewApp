package com.ilass.swifthtmlwebviewapp;

import org.json.JSONException;
import org.json.JSONObject;

final class BridgeResponse {
    private BridgeResponse() {
    }

    static JSONObject base(JSONObject message, String action) throws JSONException {
        JSONObject response = new JSONObject();
        response.put("platform", "android");
        response.put("action", action);
        if (message != null && message.has("requestId")) {
            response.put("requestId", message.optString("requestId"));
        }
        if (message != null && message.has("paymentId")) {
            response.put("paymentId", message.optString("paymentId"));
        }
        return response;
    }

    static JSONObject error(JSONObject message, String action, String error) throws JSONException {
        JSONObject response = base(message, action);
        response.put("success", false);
        response.put("error", error);
        return response;
    }

    static JSONObject unavailable(JSONObject message, String action, String error) throws JSONException {
        JSONObject response = error(message, action, error);
        response.put("available", false);
        return response;
    }
}
