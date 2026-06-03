package com.ilass.swifthtmlwebviewapp;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.os.Handler;
import android.os.Looper;
import android.view.View;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.WebSocket;
import okhttp3.WebSocketListener;
import okio.ByteString;

final class AndroidScreenStreamBridge {
    interface Listener {
        void onScreenStreamEvent(JSONObject event);
    }

    private final Activity activity;
    private final Listener listener;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService encoder = Executors.newSingleThreadExecutor();
    private final OkHttpClient client = new OkHttpClient.Builder().build();
    private final AtomicBoolean frameInFlight = new AtomicBoolean(false);
    private final Runnable captureRunnable = this::captureFrame;

    private WebSocket webSocket;
    private boolean running;
    private String targetUrl = "";
    private String format = "jpeg";
    private int fps = 2;
    private int quality = 65;
    private int maxWidth = 720;
    private long framesSent;
    private long bytesSent;
    private long startedAtMs;
    private long lastStatsAtMs;

    AndroidScreenStreamBridge(Activity activity, Listener listener) {
        this.activity = activity;
        this.listener = listener;
    }

    JSONObject start(JSONObject request) throws JSONException {
        stopInternal(false);

        targetUrl = nonEmpty(request.optString("targetUrl", ""), request.optString("url", ""));
        if (targetUrl.isEmpty()) {
            return response(request, "screenStreamStart", false, "targetUrl is required.");
        }

        format = request.optString("format", "jpeg").toLowerCase(Locale.US);
        if (!"jpeg".equals(format) && !"jpg".equals(format)) {
            return response(request, "screenStreamStart", false, "Only jpeg is implemented in this Android build.");
        }
        format = "jpeg";
        fps = clamp(request.optInt("fps", 2), 1, 10);
        quality = clamp(request.optInt("quality", 65), 25, 95);
        maxWidth = clamp(request.optInt("maxWidth", 720), 240, 1920);
        framesSent = 0;
        bytesSent = 0;
        startedAtMs = System.currentTimeMillis();
        lastStatsAtMs = 0;
        running = true;

        Request wsRequest = new Request.Builder().url(targetUrl).build();
        webSocket = client.newWebSocket(wsRequest, new WebSocketListener() {
            @Override
            public void onOpen(WebSocket socket, Response response) {
                sendTextMeta(socket);
                emitEvent("screenStreamOpen", true, null);
                scheduleNextFrame();
            }

            @Override
            public void onFailure(WebSocket socket, Throwable throwable, Response response) {
                String message = throwable != null ? throwable.getMessage() : "WebSocket failed.";
                emitEvent("screenStreamError", false, message);
                stopInternal(false);
            }

            @Override
            public void onClosed(WebSocket socket, int code, String reason) {
                emitEvent("screenStreamClosed", true, reason);
                stopInternal(false);
            }
        });

        JSONObject ack = response(request, "screenStreamStart", true, null);
        ack.put("targetUrl", targetUrl);
        ack.put("transport", "websocket");
        ack.put("format", format);
        ack.put("fps", fps);
        ack.put("quality", quality);
        ack.put("maxWidth", maxWidth);
        return ack;
    }

    JSONObject stop(JSONObject request) throws JSONException {
        stopInternal(true);
        JSONObject ack = response(request, "screenStreamStop", true, null);
        ack.put("frames", framesSent);
        ack.put("bytes", bytesSent);
        return ack;
    }

    void shutdown() {
        stopInternal(true);
        encoder.shutdownNow();
        client.dispatcher().executorService().shutdown();
    }

    private void scheduleNextFrame() {
        if (!running) {
            return;
        }
        long delayMs = Math.max(100L, 1000L / Math.max(1, fps));
        mainHandler.postDelayed(captureRunnable, delayMs);
    }

    private void captureFrame() {
        if (!running || webSocket == null || !frameInFlight.compareAndSet(false, true)) {
            scheduleNextFrame();
            return;
        }

        try {
            View root = activity.getWindow().getDecorView().getRootView();
            int width = Math.max(1, root.getWidth());
            int height = Math.max(1, root.getHeight());
            Bitmap bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
            Canvas canvas = new Canvas(bitmap);
            root.draw(canvas);
            encoder.execute(() -> encodeAndSend(bitmap));
        } catch (Exception error) {
            frameInFlight.set(false);
            emitEvent("screenStreamError", false, "Capture failed: " + error.getMessage());
            scheduleNextFrame();
        }
    }

    private void encodeAndSend(Bitmap bitmap) {
        try {
            Bitmap output = scaleIfNeeded(bitmap, maxWidth);
            ByteArrayOutputStream bytes = new ByteArrayOutputStream();
            output.compress(Bitmap.CompressFormat.JPEG, quality, bytes);
            byte[] payload = bytes.toByteArray();
            if (webSocket != null && running && webSocket.send(ByteString.of(payload))) {
                framesSent += 1;
                bytesSent += payload.length;
                emitStatsIfNeeded(payload.length);
            }
            if (output != bitmap) {
                output.recycle();
            }
        } catch (Exception error) {
            emitEvent("screenStreamError", false, "Encode/send failed: " + error.getMessage());
        } finally {
            bitmap.recycle();
            frameInFlight.set(false);
            scheduleNextFrame();
        }
    }

    private Bitmap scaleIfNeeded(Bitmap bitmap, int maxWidth) {
        if (bitmap.getWidth() <= maxWidth) {
            return bitmap;
        }
        int scaledHeight = Math.max(1, Math.round(bitmap.getHeight() * (maxWidth / (float) bitmap.getWidth())));
        return Bitmap.createScaledBitmap(bitmap, maxWidth, scaledHeight, true);
    }

    private void sendTextMeta(WebSocket socket) {
        try {
            JSONObject meta = new JSONObject();
            meta.put("type", "screenStreamMeta");
            meta.put("platform", "android");
            meta.put("format", format);
            meta.put("fps", fps);
            meta.put("quality", quality);
            meta.put("maxWidth", maxWidth);
            socket.send(meta.toString());
        } catch (JSONException ignored) {
            // Metadata is optional; binary frames still carry the stream.
        }
    }

    private void emitStatsIfNeeded(long lastFrameBytes) {
        long now = System.currentTimeMillis();
        if (now - lastStatsAtMs < 2000) {
            return;
        }
        lastStatsAtMs = now;
        try {
            JSONObject event = new JSONObject();
            event.put("platform", "android");
            event.put("action", "screenStreamStats");
            event.put("success", true);
            event.put("frames", framesSent);
            event.put("bytes", bytesSent);
            event.put("lastFrameBytes", lastFrameBytes);
            event.put("durationSeconds", Math.max(0.001, (now - startedAtMs) / 1000.0));
            listener.onScreenStreamEvent(event);
        } catch (JSONException ignored) {
            // Ignore secondary JSON failure.
        }
    }

    private void emitEvent(String action, boolean success, String message) {
        try {
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
            listener.onScreenStreamEvent(event);
        } catch (JSONException ignored) {
            // Ignore secondary JSON failure.
        }
    }

    private void stopInternal(boolean closeSocket) {
        running = false;
        mainHandler.removeCallbacks(captureRunnable);
        frameInFlight.set(false);
        if (webSocket != null && closeSocket) {
            webSocket.close(1000, "screen stream stopped");
        }
        webSocket = null;
    }

    private JSONObject response(JSONObject request, String action, boolean success, String error) throws JSONException {
        JSONObject response = new JSONObject();
        response.put("platform", "android");
        response.put("action", action);
        response.put("success", success);
        if (request != null && request.has("requestId")) {
            response.put("requestId", request.optString("requestId"));
        }
        if (error != null && !error.isEmpty()) {
            response.put("error", error);
        }
        return response;
    }

    private int clamp(int value, int min, int max) {
        return Math.max(min, Math.min(max, value));
    }

    private String nonEmpty(String value, String fallback) {
        if (value == null || value.trim().isEmpty()) {
            return fallback == null ? "" : fallback.trim();
        }
        return value.trim();
    }
}
