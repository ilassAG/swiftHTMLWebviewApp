package com.ilass.swifthtmlwebviewapp;

import org.json.JSONException;
import org.json.JSONObject;

final class AndroidNativeCommandPayload {
    private AndroidNativeCommandPayload() {
    }

    static JSONObject reloadResponse(JSONObject request) throws JSONException {
        return successResponse(request, "reload");
    }

    static JSONObject launchConfettiResponse(JSONObject request, int burstCount, String nativeStatus) throws JSONException {
        JSONObject response = successResponse(request, "launchConfetti");
        response.put("launched", true);
        response.put("burstCount", burstCount);
        if (nativeStatus != null && !nativeStatus.trim().isEmpty()) {
            response.put("nativeStatus", nativeStatus);
        }
        return response;
    }

    static JSONObject successResponse(JSONObject request, String action) throws JSONException {
        JSONObject response = BridgeResponse.base(request, action);
        response.put("success", true);
        return response;
    }
}
