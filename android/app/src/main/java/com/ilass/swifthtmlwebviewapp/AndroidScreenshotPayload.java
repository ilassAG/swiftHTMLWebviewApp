package com.ilass.swifthtmlwebviewapp;

import org.json.JSONException;
import org.json.JSONObject;

final class AndroidScreenshotPayload {
    private AndroidScreenshotPayload() {
    }

    static final class Request {
        final int maxWidth;
        final int quality;

        private Request(int maxWidth, int quality) {
            this.maxWidth = maxWidth;
            this.quality = quality;
        }
    }

    static Request request(JSONObject source) {
        JSONObject request = source != null ? source : new JSONObject();
        return new Request(
                clamp(request.optInt("maxWidth", 1080), 240, 2160),
                clamp(request.optInt("quality", 82), 25, 95)
        );
    }

    static JSONObject response(
            JSONObject source,
            int width,
            int height,
            String imageDataUrl
    ) throws JSONException {
        JSONObject response = BridgeResponse.base(source, "screenshotGet");
        response.put("success", true);
        response.put("format", "jpeg");
        response.put("width", width);
        response.put("height", height);
        response.put("imageData", imageDataUrl);
        return response;
    }

    private static int clamp(int value, int min, int max) {
        return Math.max(min, Math.min(max, value));
    }
}
