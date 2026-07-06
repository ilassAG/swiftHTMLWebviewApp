package com.ilass.swifthtmlwebviewapp;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.Locale;

final class AndroidScreenStreamPayload {
    private AndroidScreenStreamPayload() {
    }

    static StreamRequest streamRequest(JSONObject request) {
        String targetUrl = nonEmpty(request.optString("targetUrl", ""), request.optString("url", ""));
        String subject = request.optString("subject", "").trim();
        String explicitTransport = request.optString("transport", "").trim().toLowerCase(Locale.US);
        String transport = explicitTransport.isEmpty()
                ? (subject.isEmpty() ? "websocket" : "nats")
                : explicitTransport;
        String format = request.optString("format", "jpeg").toLowerCase(Locale.US);
        if ("jpg".equals(format)) {
            format = "jpeg";
        }
        return new StreamRequest(
                normalizedSource(request.optString("source", request.optString("captureSource", ""))),
                "nats".equals(transport) ? "nats" : "websocket",
                targetUrl,
                subject,
                request.optString("metaSubject", "").trim(),
                request.optString("eventSubject", "").trim(),
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
        ack.put("source", streamRequest.source);
        ack.put("transport", streamRequest.transport);
        if (streamRequest.isWebSocket()) {
            ack.put("targetUrl", streamRequest.targetUrl);
        } else {
            ack.put("subject", streamRequest.subject);
            ack.put("metaSubject", streamRequest.metaSubject);
            ack.put("eventSubject", streamRequest.eventSubject);
        }
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

    static JSONObject meta(StreamRequest request) throws JSONException {
        JSONObject meta = new JSONObject();
        meta.put("type", "screenStreamMeta");
        meta.put("platform", "android");
        meta.put("source", request.source);
        meta.put("transport", request.transport);
        meta.put("format", request.format);
        meta.put("fps", request.fps);
        meta.put("quality", request.quality);
        meta.put("maxWidth", request.maxWidth);
        meta.put("subject", request.subject);
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

    static String normalizedSource(String value) {
        String source = value == null ? "" : value.trim().toLowerCase(Locale.US);
        if (source.isEmpty() || "app".equals(source) || "webview".equals(source) || "surface".equals(source)) {
            return "app";
        }
        if ("device".equals(source) || "screen".equals(source) || "system".equals(source)) {
            return "device";
        }
        return source;
    }

    static final class StreamRequest {
        final String source;
        final String targetUrl;
        final String transport;
        final String subject;
        final String metaSubject;
        final String eventSubject;
        final String format;
        final int fps;
        final int quality;
        final int maxWidth;

        StreamRequest(String source, String transport, String targetUrl, String subject, String metaSubject, String eventSubject, String format, int fps, int quality, int maxWidth) {
            this.source = source;
            this.transport = transport;
            this.targetUrl = targetUrl;
            this.subject = subject;
            this.metaSubject = metaSubject;
            this.eventSubject = eventSubject;
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

        boolean isNats() {
            return "nats".equals(transport);
        }

        boolean isWebSocket() {
            return "websocket".equals(transport);
        }
    }
}
