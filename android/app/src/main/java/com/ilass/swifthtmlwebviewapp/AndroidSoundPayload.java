package com.ilass.swifthtmlwebviewapp;

import org.json.JSONException;
import org.json.JSONObject;

final class AndroidSoundPayload {
    private AndroidSoundPayload() {
    }

    static final class Request {
        final int frequencyHz;
        final int durationMs;
        final double volume;

        private Request(int frequencyHz, int durationMs, double volume) {
            this.frequencyHz = frequencyHz;
            this.durationMs = durationMs;
            this.volume = volume;
        }
    }

    static Request request(JSONObject source) {
        JSONObject request = source != null ? source : new JSONObject();
        return new Request(
                clamp(request.optInt("frequencyHz", 880), 80, 4000),
                clamp(request.optInt("durationMs", 240), 40, 5000),
                Math.max(0.0, Math.min(1.0, request.optDouble("volume", 0.85)))
        );
    }

    static JSONObject response(JSONObject source, Request sound) throws JSONException {
        JSONObject response = BridgeResponse.base(source, "soundPlay");
        response.put("success", true);
        response.put("frequencyHz", sound.frequencyHz);
        response.put("durationMs", sound.durationMs);
        response.put("volume", sound.volume);
        return response;
    }

    private static int clamp(int value, int min, int max) {
        return Math.max(min, Math.min(max, value));
    }
}
