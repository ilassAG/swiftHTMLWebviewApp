package com.ilass.swifthtmlwebviewapp;

import org.json.JSONException;
import org.json.JSONObject;

final class AndroidUnavailableBridge {
    private AndroidUnavailableBridge() {
    }

    static JSONObject arPosition(JSONObject message) throws JSONException {
        return unavailable(
                message,
                "arPositionStart",
                "arkit-position",
                "ARKit local position tracking is iOS-only and not available on Android."
        );
    }

    static JSONObject roomPlan(JSONObject message) throws JSONException {
        return unavailable(
                message,
                "roomPlanScanStart",
                "roomplan",
                "RoomPlan/LiDAR scanning is iOS-only and not available on Android."
        );
    }

    static JSONObject arGuided(JSONObject message) throws JSONException {
        return unavailable(
                message,
                "arGuidedMeasurementStart",
                "arkit-guided",
                "ARKit guided measurement is iOS-only and not available on Android."
        );
    }

    static JSONObject arOverlay(JSONObject message) throws JSONException {
        return unavailable(
                message,
                "arOverlayOpen",
                "arkit-overlay",
                "ARKit overlays are iOS-only and not available on Android."
        );
    }

    static JSONObject portraitCapture(JSONObject message) throws JSONException {
        return unavailable(
                message,
                "portraitCapture",
                "portrait-capture",
                "Native portrait capture is currently implemented on iOS first and not available on Android yet."
        );
    }

    private static JSONObject unavailable(
            JSONObject message,
            String fallbackAction,
            String source,
            String error
    ) throws JSONException {
        String action = message == null ? fallbackAction : message.optString("action", fallbackAction);
        JSONObject response = BridgeResponse.base(message, action);
        response.put("success", false);
        response.put("supported", false);
        response.put("source", source);
        response.put("error", error);
        return response;
    }
}
