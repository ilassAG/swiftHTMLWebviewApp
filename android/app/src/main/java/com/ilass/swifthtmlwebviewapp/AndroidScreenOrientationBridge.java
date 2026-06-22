package com.ilass.swifthtmlwebviewapp;

import android.content.pm.ActivityInfo;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.Locale;

final class AndroidScreenOrientationBridge {
    interface Host {
        int requestedOrientation();

        int currentOrientation();

        void applyRequestedOrientation(int requestedOrientation);
    }

    static final class OrientationRequest {
        final String mode;
        final int requestedOrientation;

        private OrientationRequest(String mode, int requestedOrientation) {
            this.mode = mode;
            this.requestedOrientation = requestedOrientation;
        }
    }

    private final Host host;

    AndroidScreenOrientationBridge(Host host) {
        this.host = host;
    }

    JSONObject get(JSONObject request) throws JSONException {
        JSONObject response = BridgeResponse.base(request, "screenOrientationGet");
        response.put("success", true);
        response.put("requestedOrientation", host.requestedOrientation());
        response.put("currentOrientation", host.currentOrientation());
        return response;
    }

    JSONObject set(JSONObject request) throws JSONException {
        OrientationRequest orientationRequest = orientationRequest(request);
        host.applyRequestedOrientation(orientationRequest.requestedOrientation);
        JSONObject response = BridgeResponse.base(request, "screenOrientationSet");
        response.put("success", true);
        response.put("mode", orientationRequest.mode);
        response.put("requestedOrientation", orientationRequest.requestedOrientation);
        return response;
    }

    static OrientationRequest orientationRequest(JSONObject request) {
        String mode = request.optString("mode", request.optString("orientation", "unlocked")).toLowerCase(Locale.US);
        switch (mode) {
            case "portrait":
                return new OrientationRequest("portrait", ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT);
            case "landscape":
                return new OrientationRequest("landscape", ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE);
            case "locked":
            case "current":
                return new OrientationRequest(mode, ActivityInfo.SCREEN_ORIENTATION_LOCKED);
            case "unlocked":
            case "auto":
            default:
                return new OrientationRequest("unlocked", ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED);
        }
    }
}
