package com.ilass.swifthtmlwebviewapp;

import org.json.JSONException;
import org.json.JSONObject;

final class AndroidIdleTimerPayload {
    private AndroidIdleTimerPayload() {
    }

    static long timeoutMillis(JSONObject message) {
        return Math.max(1000L, Math.round(message.optDouble("timeoutSeconds", 30.0) * 1000.0));
    }

    static long intervalMillis(JSONObject message) {
        return Math.max(250L, Math.round(message.optDouble("intervalSeconds", 1.0) * 1000.0));
    }

    static JSONObject startResponse(JSONObject request, long timeoutMs, long intervalMs) throws JSONException {
        JSONObject response = successResponse(request, "idleTimerStart");
        response.put("timeoutSeconds", seconds(timeoutMs));
        response.put("intervalSeconds", seconds(intervalMs));
        return response;
    }

    static JSONObject stopResponse(JSONObject request) throws JSONException {
        return successResponse(request, "idleTimerStop");
    }

    static JSONObject resetResponse(JSONObject request) throws JSONException {
        return successResponse(request, "idleTimerReset");
    }

    static JSONObject event(String action, long idleMs, long timeoutMs) throws JSONException {
        JSONObject event = new JSONObject();
        event.put("platform", "android");
        event.put("action", action);
        event.put("success", true);
        event.put("idleSeconds", seconds(idleMs));
        event.put("timeoutSeconds", seconds(timeoutMs));
        return event;
    }

    private static JSONObject successResponse(JSONObject request, String action) throws JSONException {
        JSONObject response = BridgeResponse.base(request, action);
        response.put("success", true);
        return response;
    }

    private static double seconds(long millis) {
        return millis / 1000.0;
    }
}
