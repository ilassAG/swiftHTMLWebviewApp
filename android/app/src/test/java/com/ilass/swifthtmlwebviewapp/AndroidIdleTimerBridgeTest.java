package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.json.JSONObject;
import org.junit.Test;

import java.util.ArrayList;
import java.util.List;

public class AndroidIdleTimerBridgeTest {
    @Test
    public void startClampsTimeoutAndIntervalAndSchedulesTick() throws Exception {
        FakeHost host = new FakeHost();
        AndroidIdleTimerBridge bridge = new AndroidIdleTimerBridge(host);

        JSONObject response = bridge.start(new JSONObject()
                .put("requestId", "req-1")
                .put("timeoutSeconds", 0.1)
                .put("intervalSeconds", 0.01));

        assertTrue(response.getBoolean("success"));
        assertEquals("idleTimerStart", response.getString("action"));
        assertEquals("req-1", response.getString("requestId"));
        assertEquals(1.0, response.getDouble("timeoutSeconds"), 0.001);
        assertEquals(0.25, response.getDouble("intervalSeconds"), 0.001);
        assertEquals(250L, host.lastDelayMs);
        assertEquals(1, host.cancelCount);
    }

    @Test
    public void tickEmitsIdleTickAndSingleTimeout() throws Exception {
        FakeHost host = new FakeHost();
        AndroidIdleTimerBridge bridge = new AndroidIdleTimerBridge(host);
        bridge.start(new JSONObject()
                .put("timeoutSeconds", 1.0)
                .put("intervalSeconds", 0.25));

        host.nowMs = 1200L;
        host.runScheduled();
        host.runScheduled();

        assertEquals(3, host.events.size());
        assertEquals("idleTick", host.events.get(0).getString("action"));
        assertEquals(1.2, host.events.get(0).getDouble("idleSeconds"), 0.001);
        assertEquals("idleTimeout", host.events.get(1).getString("action"));
        assertEquals(1.0, host.events.get(1).getDouble("timeoutSeconds"), 0.001);
        assertEquals("idleTick", host.events.get(2).getString("action"));
    }

    @Test
    public void resetClearsTimeoutStateAndStopCancelsSchedule() throws Exception {
        FakeHost host = new FakeHost();
        AndroidIdleTimerBridge bridge = new AndroidIdleTimerBridge(host);
        bridge.start(new JSONObject()
                .put("timeoutSeconds", 1.0)
                .put("intervalSeconds", 0.25));

        host.nowMs = 1100L;
        host.runScheduled();
        assertEquals("idleTimeout", host.events.get(1).getString("action"));

        JSONObject reset = bridge.reset(new JSONObject().put("requestId", "req-reset"));
        assertTrue(reset.getBoolean("success"));
        assertEquals("idleTimerReset", reset.getString("action"));

        host.nowMs = 1800L;
        host.runScheduled();
        assertEquals("idleTick", host.events.get(2).getString("action"));

        JSONObject stop = bridge.stop(new JSONObject().put("requestId", "req-stop"));
        assertTrue(stop.getBoolean("success"));
        assertEquals("idleTimerStop", stop.getString("action"));
        assertEquals(2, host.cancelCount);

        host.nowMs = 3000L;
        host.runScheduled();
        assertEquals(3, host.events.size());
    }

    private static final class FakeHost implements AndroidIdleTimerBridge.Host {
        long nowMs = 0L;
        long lastDelayMs = -1L;
        int cancelCount = 0;
        Runnable scheduled;
        final List<JSONObject> events = new ArrayList<>();

        @Override
        public long currentTimeMillis() {
            return nowMs;
        }

        @Override
        public void scheduleIdleCheck(Runnable runnable, long delayMs) {
            scheduled = runnable;
            lastDelayMs = delayMs;
        }

        @Override
        public void cancelIdleCheck(Runnable runnable) {
            if (scheduled == runnable) {
                scheduled = null;
            }
            cancelCount += 1;
        }

        @Override
        public void sendResult(JSONObject payload) {
            events.add(payload);
        }

        void runScheduled() {
            Runnable runnable = scheduled;
            if (runnable != null) {
                runnable.run();
            }
        }
    }
}
