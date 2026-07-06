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

    interface Publisher {
        String publish(String subject, byte[] payload);
    }

    private final Activity activity;
    private final Listener listener;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService encoder = Executors.newSingleThreadExecutor();
    private final OkHttpClient client = new OkHttpClient.Builder().build();
    private final AtomicBoolean frameInFlight = new AtomicBoolean(false);
    private final Runnable captureRunnable = this::captureFrame;

    private WebSocket webSocket;
    private Publisher natsPublisher;
    private AndroidScreenStreamPayload.StreamRequest streamRequest;
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
        return start(request, null);
    }

    JSONObject start(JSONObject request, Publisher publisher) throws JSONException {
        stopInternal(true);

        streamRequest = AndroidScreenStreamPayload.streamRequest(request);
        natsPublisher = publisher;
        if (streamRequest.isWebSocket() && !streamRequest.hasTargetUrl()) {
            return AndroidScreenStreamPayload.response(request, "screenStreamStart", false, "targetUrl is required.");
        }
        if (streamRequest.isNats() && streamRequest.subject.isEmpty()) {
            return AndroidScreenStreamPayload.response(request, "screenStreamStart", false, "subject is required for NATS screen streaming.");
        }
        if (streamRequest.isNats() && natsPublisher == null) {
            return AndroidScreenStreamPayload.response(request, "screenStreamStart", false, "NATS publisher is required for NATS screen streaming.");
        }

        if (!streamRequest.isJpeg()) {
            return AndroidScreenStreamPayload.response(request, "screenStreamStart", false, "Only jpeg is implemented in this Android build.");
        }
        targetUrl = streamRequest.targetUrl;
        format = streamRequest.format;
        fps = streamRequest.fps;
        quality = streamRequest.quality;
        maxWidth = streamRequest.maxWidth;
        framesSent = 0;
        bytesSent = 0;
        startedAtMs = System.currentTimeMillis();
        lastStatsAtMs = 0;
        running = true;

        if (streamRequest.isWebSocket()) {
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
        } else {
            publishNatsMeta();
            emitEvent("screenStreamOpen", true, null);
            scheduleNextFrame();
        }

        return AndroidScreenStreamPayload.startAck(request, streamRequest);
    }

    JSONObject stop(JSONObject request) throws JSONException {
        stopInternal(true);
        return AndroidScreenStreamPayload.stopAck(request, framesSent, bytesSent);
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
        if (!running || !hasActiveTransport() || !frameInFlight.compareAndSet(false, true)) {
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
            boolean sent = false;
            if (streamRequest != null && streamRequest.isNats() && natsPublisher != null && running) {
                String error = natsPublisher.publish(streamRequest.subject, payload);
                if (error != null && !error.isEmpty()) {
                    emitEvent("screenStreamError", false, error);
                } else {
                    sent = true;
                }
            } else if (webSocket != null && running) {
                sent = webSocket.send(ByteString.of(payload));
            }
            if (sent) {
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
            socket.send(AndroidScreenStreamPayload.meta(streamRequest).toString());
        } catch (JSONException ignored) {
            // Metadata is optional; binary frames still carry the stream.
        }
    }

    private void publishNatsMeta() {
        try {
            if (streamRequest != null && !streamRequest.metaSubject.isEmpty() && natsPublisher != null) {
                String error = natsPublisher.publish(
                        streamRequest.metaSubject,
                        AndroidScreenStreamPayload.meta(streamRequest).toString().getBytes(java.nio.charset.StandardCharsets.UTF_8)
                );
                if (error != null && !error.isEmpty()) {
                    emitEvent("screenStreamError", false, error);
                }
            }
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
            emitJSONObject(AndroidScreenStreamPayload.stats(framesSent, bytesSent, lastFrameBytes, startedAtMs, now));
        } catch (JSONException ignored) {
            // Ignore secondary JSON failure.
        }
    }

    private void emitEvent(String action, boolean success, String message) {
        try {
            emitJSONObject(AndroidScreenStreamPayload.event(action, success, message));
        } catch (JSONException ignored) {
            // Ignore secondary JSON failure.
        }
    }

    private void emitJSONObject(JSONObject event) {
        if (streamRequest != null && streamRequest.isNats() && natsPublisher != null && !streamRequest.eventSubject.isEmpty()) {
            natsPublisher.publish(streamRequest.eventSubject, event.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8));
            return;
        }
        listener.onScreenStreamEvent(event);
    }

    private void stopInternal(boolean closeSocket) {
        running = false;
        mainHandler.removeCallbacks(captureRunnable);
        frameInFlight.set(false);
        if (webSocket != null && closeSocket) {
            webSocket.close(1000, "screen stream stopped");
        }
        webSocket = null;
        natsPublisher = null;
        streamRequest = null;
    }

    private boolean hasActiveTransport() {
        return (streamRequest != null && streamRequest.isNats() && natsPublisher != null) || webSocket != null;
    }

}
