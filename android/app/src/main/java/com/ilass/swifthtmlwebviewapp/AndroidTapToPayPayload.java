package com.ilass.swifthtmlwebviewapp;

import org.json.JSONException;
import org.json.JSONObject;

final class AndroidTapToPayPayload {
    static final String MISSING_BRIDGE_MESSAGE = "Android Tap to Pay bridge is not included in this wrapper build.";

    private AndroidTapToPayPayload() {
    }

    static JSONObject availabilityUnavailable(JSONObject request) throws JSONException {
        JSONObject response = BridgeResponse.base(request, "tapToPayAvailability");
        response.put("success", true);
        response.put("available", false);
        response.put("readerType", "android_tap_to_pay");
        response.put("reason", MISSING_BRIDGE_MESSAGE);
        return response;
    }

    static JSONObject collectUnavailable(JSONObject request) throws JSONException {
        return BridgeResponse.error(request, "tapToPayCollect", MISSING_BRIDGE_MESSAGE);
    }
}
