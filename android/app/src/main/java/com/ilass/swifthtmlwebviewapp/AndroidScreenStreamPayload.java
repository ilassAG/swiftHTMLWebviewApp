package com.ilass.swifthtmlwebviewapp;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.Locale;

final class AndroidScreenStreamPayload {
    private AndroidScreenStreamPayload() {
    }

    static StreamRequest streamRequest(JSONObject request) {
        String targetUrl = nonEmpty(request.optString("targetUrl", ""), request.optString("url", ""));
        String format = request.optString("format", "jpeg").toLowerCase(Locale.US);
        if ("jpg".equals(format)) {
            format = "jpeg";
        }
        return new StreamRequest(
                targetUrl,
                format,
                clamp(request.optInt("fps", 2), 1, 10),
                clamp(request.optInt("quality", 65), 25, 95),
                clamp(request.optInt("maxWidth", 720), 240, 1920)
        );
    }

    static JSONObject response(JSONObject request, String action, boolean success, String error) throws JSONException {
        JSONObject response = BridgeResponse.base(request, action);
        response.put("success", success);
        if (error != null && !error.isEmpty()) {
            response.put("error", error);
        }
        return response;
    }

    static JSONObject startAck(JSONObject request, StreamRequest streamRequest) throws JSONException {
        JSONObject ack = response(request, "screenStreamStart", true, null);
        ack.put("targetUrl", streamRequest.targetUrl);
        ack.put("transport", "websocket");
        ack.put("format", streamRequest.format);
        ack.put("fps", streamRequest.fps);
        ack.put("quality", streamRequest.quality);
        ack.put("maxWidth", streamRequest.maxWidth);
        return ack;
    }

    static JSONObject stopAck(JSONObject request, long framesSent, long bytesSent) throws JSONException {
        JSONObject ack = response(request, "screenStreamStop", true, null);
        ack.put("frames", framesSent);
        ack.put("bytes", bytesSent);
        return ack;
    }

    static JSONObject meta(String format, int fps, int quality, int maxWidth) throws JSONException {
        JSONObject meta = new JSONObject();
        meta.put("type", "screenStreamMeta");
        meta.put("platform", "android");
        meta.put("format", format);
        meta.put("fps", fps);
        meta.put("quality", quality);
        meta.put("maxWidth", maxWidth);
        return meta;
    }

    static JSONObject event(String action, boolean success, String message) throws JSONException {
        JSONObject event = new JSONObject();
        event.put("platform", "android");
        event.put("action", action);
        event.put("success", success);
        if (message != null && !message.isEmpty()) {
            if (success) {
                event.put("message", message);
            } else {
                event.put("error", message);
            }
        }
        return event;
    }

    static JSONObject stats(long framesSent, long bytesSent, long lastFrameBytes, long startedAtMs, long nowMs) throws JSONException {
        JSONObject event = new JSONObject();
        event.put("platform", "android");
        event.put("action", "screenStreamStats");
        event.put("success", true);
        event.put("frames", framesSent);
        event.put("bytes", bytesSent);
        event.put("lastFrameBytes", lastFrameBytes);
        event.put("durationSeconds", Math.max(0.001, (nowMs - startedAtMs) / 1000.0));
        return event;
    }

    static int clamp(int value, int min, int max) {
        return Math.max(min, Math.min(max, value));
    }

    static String nonEmpty(String value, String fallback) {
        if (value == null || value.trim().isEmpty()) {
            return fallback == null ? "" : fallback.trim();
        }
        return value.trim();
    }

    static final class StreamRequest {
        final String targetUrl;
        final String format;
        final int fps;
        final int quality;
        final int maxWidth;

        StreamRequest(String targetUrl, String format, int fps, int quality, int maxWidth) {
            this.targetUrl = targetUrl;
            this.format = format;
            this.fps = fps;
            this.quality = quality;
            this.maxWidth = maxWidth;
        }

        boolean hasTargetUrl() {
            return !targetUrl.isEmpty();
        }

        boolean isJpeg() {
            return "jpeg".equals(format);
        }
    }
}
