package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import android.content.pm.ActivityInfo;
import android.content.res.Configuration;

import org.json.JSONObject;
import org.junit.Test;

public class AndroidScreenOrientationBridgeTest {
    @Test
    public void orientationRequestMapsKnownModes() throws Exception {
        assertEquals(
                ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT,
                AndroidScreenOrientationBridge.orientationRequest(new JSONObject().put("mode", "portrait")).requestedOrientation
        );
        assertEquals(
                ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE,
                AndroidScreenOrientationBridge.orientationRequest(new JSONObject().put("mode", "landscape")).requestedOrientation
        );
        assertEquals(
                ActivityInfo.SCREEN_ORIENTATION_LOCKED,
                AndroidScreenOrientationBridge.orientationRequest(new JSONObject().put("mode", "locked")).requestedOrientation
        );
        assertEquals(
                ActivityInfo.SCREEN_ORIENTATION_LOCKED,
                AndroidScreenOrientationBridge.orientationRequest(new JSONObject().put("mode", "current")).requestedOrientation
        );
    }

    @Test
    public void orientationRequestDefaultsUnknownAndAutoToUnlocked() throws Exception {
        AndroidScreenOrientationBridge.OrientationRequest auto = AndroidScreenOrientationBridge.orientationRequest(
                new JSONObject().put("orientation", "auto")
        );
        assertEquals("unlocked", auto.mode);
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED, auto.requestedOrientation);

        AndroidScreenOrientationBridge.OrientationRequest unknown = AndroidScreenOrientationBridge.orientationRequest(
                new JSONObject().put("mode", "sideways")
        );
        assertEquals("unlocked", unknown.mode);
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED, unknown.requestedOrientation);
    }

    @Test
    public void getReturnsRequestedAndCurrentOrientation() throws Exception {
        FakeHost host = new FakeHost();
        host.requested = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE;
        host.current = Configuration.ORIENTATION_LANDSCAPE;
        JSONObject response = new AndroidScreenOrientationBridge(host).get(new JSONObject().put("requestId", "req-1"));

        assertTrue(response.getBoolean("success"));
        assertEquals("screenOrientationGet", response.getString("action"));
        assertEquals("req-1", response.getString("requestId"));
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE, response.getInt("requestedOrientation"));
        assertEquals(Configuration.ORIENTATION_LANDSCAPE, response.getInt("currentOrientation"));
    }

    @Test
    public void setAppliesRequestedOrientationAndReturnsMode() throws Exception {
        FakeHost host = new FakeHost();
        JSONObject response = new AndroidScreenOrientationBridge(host).set(new JSONObject()
                .put("requestId", "req-2")
                .put("mode", "portrait"));

        assertTrue(response.getBoolean("success"));
        assertEquals("screenOrientationSet", response.getString("action"));
        assertEquals("req-2", response.getString("requestId"));
        assertEquals("portrait", response.getString("mode"));
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT, response.getInt("requestedOrientation"));
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT, host.applied);
    }

    private static final class FakeHost implements AndroidScreenOrientationBridge.Host {
        int requested = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED;
        int current = Configuration.ORIENTATION_PORTRAIT;
        int applied = Integer.MIN_VALUE;

        @Override
        public int requestedOrientation() {
            return requested;
        }

        @Override
        public int currentOrientation() {
            return current;
        }

        @Override
        public void applyRequestedOrientation(int requestedOrientation) {
            applied = requestedOrientation;
            requested = requestedOrientation;
        }
    }
}
