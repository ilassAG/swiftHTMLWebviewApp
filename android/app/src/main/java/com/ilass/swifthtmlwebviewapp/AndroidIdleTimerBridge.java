package com.ilass.swifthtmlwebviewapp;

import org.json.JSONException;
import org.json.JSONObject;

final class AndroidIdleTimerBridge {
    interface Host {
        long currentTimeMillis();

        void scheduleIdleCheck(Runnable runnable, long delayMs);

        void cancelIdleCheck(Runnable runnable);

        void sendResult(JSONObject payload);
    }

    private final Host host;
    private boolean running = false;
    private boolean timedOut = false;
    private long lastActivityMs;
    private long timeoutMs = 30000L;
    private long intervalMs = 1000L;

    private final Runnable idleRunnable = new Runnable() {
        @Override
        public void run() {
            tick();
        }
    };

    AndroidIdleTimerBridge(Host host) {
        this.host = host;
        this.lastActivityMs = host.currentTimeMillis();
    }

    JSONObject start(JSONObject message) throws JSONException {
        timeoutMs = AndroidIdleTimerPayload.timeoutMillis(message);
        intervalMs = AndroidIdleTimerPayload.intervalMillis(message);
        running = true;
        timedOut = false;
        recordActivity();
        host.cancelIdleCheck(idleRunnable);
        host.scheduleIdleCheck(idleRunnable, intervalMs);

        return AndroidIdleTimerPayload.startResponse(message, timeoutMs, intervalMs);
    }

    JSONObject stop(JSONObject message) throws JSONException {
        stop();
        return AndroidIdleTimerPayload.stopResponse(message);
    }

    JSONObject reset(JSONObject message) throws JSONException {
        recordActivity();
        return AndroidIdleTimerPayload.resetResponse(message);
    }

    void recordActivity() {
        lastActivityMs = host.currentTimeMillis();
        timedOut = false;
    }

    void stop() {
        running = false;
        host.cancelIdleCheck(idleRunnable);
    }

    Runnable idleRunnable() {
        return idleRunnable;
    }

    private void tick() {
        if (!running) {
            return;
        }
        long idleMs = Math.max(0L, host.currentTimeMillis() - lastActivityMs);
        emitIdleEvent("idleTick", idleMs);
        if (!timedOut && idleMs >= timeoutMs) {
            timedOut = true;
            emitIdleEvent("idleTimeout", idleMs);
        }
        host.scheduleIdleCheck(idleRunnable, intervalMs);
    }

    private void emitIdleEvent(String action, long idleMs) {
        try {
            host.sendResult(AndroidIdleTimerPayload.event(action, idleMs, timeoutMs));
        } catch (JSONException ignored) {
            // Ignore secondary JSON failure.
        }
    }
}
