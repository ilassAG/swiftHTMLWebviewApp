package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

public class AndroidNotificationPayloadTest {
    @Test
    public void baseAndPermissionErrorUseCommonBridgeShape() throws Exception {
        JSONObject base = AndroidNotificationPayload.baseResponse(
                new JSONObject().put("requestId", "req-1"),
                "notificationPermissionGet"
        );

        assertEquals("android", base.getString("platform"));
        assertEquals("notificationPermissionGet", base.getString("action"));
        assertEquals("req-1", base.getString("requestId"));

        JSONObject error = AndroidNotificationPayload.permissionError(
                new JSONObject().put("requestId", "req-2"),
                "notificationShow",
                "denied"
        );

        assertEquals("android", error.getString("platform"));
        assertEquals("notificationShow", error.getString("action"));
        assertEquals("req-2", error.getString("requestId"));
        assertFalse(error.getBoolean("success"));
        assertFalse(error.getBoolean("authorized"));
        assertEquals("denied", error.getString("authorizationStatus"));
        assertEquals("Notification permission is not granted.", error.getString("error"));
    }

    @Test
    public void permissionResponsesUseCommonBridgeShape() throws Exception {
        JSONObject status = AndroidNotificationPayload.permissionStatusResponse(
                new JSONObject().put("requestId", "req-status"),
                true,
                "authorized",
                true,
                "android.settings.APP_NOTIFICATION_SETTINGS"
        );

        assertEquals("android", status.getString("platform"));
        assertEquals("notificationPermissionGet", status.getString("action"));
        assertEquals("req-status", status.getString("requestId"));
        assertTrue(status.getBoolean("success"));
        assertTrue(status.getBoolean("authorized"));
        assertEquals("authorized", status.getString("authorizationStatus"));
        assertTrue(status.getBoolean("needsRuntimePermission"));
        assertEquals("android.settings.APP_NOTIFICATION_SETTINGS", status.getString("settingsIntentAction"));

        JSONObject request = AndroidNotificationPayload.permissionRequestResponse(
                new JSONObject().put("requestId", "req-request"),
                false,
                false,
                "denied"
        );

        assertEquals("notificationPermissionRequest", request.getString("action"));
        assertEquals("req-request", request.getString("requestId"));
        assertTrue(request.getBoolean("success"));
        assertFalse(request.getBoolean("authorized"));
        assertFalse(request.getBoolean("granted"));
        assertEquals("denied", request.getString("authorizationStatus"));
    }

    @Test
    public void commandResponsesUseCommonBridgeShape() throws Exception {
        JSONObject show = AndroidNotificationPayload.showResponse(new JSONObject().put("requestId", "req-show"), "notif-show");
        assertEquals("notificationShow", show.getString("action"));
        assertEquals("req-show", show.getString("requestId"));
        assertTrue(show.getBoolean("success"));
        assertEquals("notif-show", show.getString("id"));
        assertTrue(show.getBoolean("immediate"));

        JSONObject schedule = AndroidNotificationPayload.scheduleResponse(
                new JSONObject().put("requestId", "req-schedule"),
                "notif-schedule",
                12,
                123456789L
        );
        assertEquals("notificationSchedule", schedule.getString("action"));
        assertEquals("req-schedule", schedule.getString("requestId"));
        assertTrue(schedule.getBoolean("success"));
        assertEquals("notif-schedule", schedule.getString("id"));
        assertEquals(12, schedule.getLong("seconds"));
        assertEquals(123456789L, schedule.getLong("scheduledAtMs"));

        JSONArray ids = new JSONArray().put("first").put("second");
        JSONObject cancel = AndroidNotificationPayload.cancelResponse(new JSONObject().put("requestId", "req-cancel"), ids);
        assertEquals("notificationCancel", cancel.getString("action"));
        assertEquals("req-cancel", cancel.getString("requestId"));
        assertTrue(cancel.getBoolean("success"));
        assertEquals(2, cancel.getInt("count"));
        assertEquals("second", cancel.getJSONArray("ids").getString(1));

        JSONObject cancelAll = AndroidNotificationPayload.cancelAllResponse(new JSONObject().put("requestId", "req-all"));
        assertEquals("notificationCancelAll", cancelAll.getString("action"));
        assertEquals("req-all", cancelAll.getString("requestId"));
        assertTrue(cancelAll.getBoolean("success"));
    }

    @Test
    public void listResponseWrapsPendingAndDeliveredArrays() throws Exception {
        JSONArray pending = new JSONArray().put(new JSONObject().put("id", "pending-1"));
        JSONObject response = AndroidNotificationPayload.listResponse(
                new JSONObject().put("requestId", "req-list"),
                pending
        );

        assertEquals("android", response.getString("platform"));
        assertEquals("notificationList", response.getString("action"));
        assertEquals("req-list", response.getString("requestId"));
        assertTrue(response.getBoolean("success"));
        assertEquals("pending-1", response.getJSONArray("pending").getJSONObject(0).getString("id"));
        assertEquals(0, response.getJSONArray("delivered").length());
    }

    @Test
    public void notificationPayloadNormalizesFallbacksAndData() throws Exception {
        JSONObject payload = AndroidNotificationPayload.notificationPayload(
                new JSONObject()
                        .put("message", "Fallback body")
                        .put("channelName", "Staff alerts")
                        .put("sound", false)
                        .put("data", new JSONObject().put("jobId", "42")),
                "notif-1"
        );

        assertEquals("notif-1", payload.getString("id"));
        assertEquals("Notification", payload.getString("title"));
        assertEquals("", payload.getString("subtitle"));
        assertEquals("Fallback body", payload.getString("body"));
        assertEquals(AndroidNotificationPayload.DEFAULT_CHANNEL_ID, payload.getString("channelId"));
        assertEquals("Staff alerts", payload.getString("channelName"));
        assertEquals("high", payload.getString("importance"));
        assertFalse(payload.getBoolean("sound"));
        assertEquals("42", payload.getJSONObject("data").getString("jobId"));
    }

    @Test
    public void idsFromRequestPrefersExplicitArrayAndSkipsBlanks() throws Exception {
        JSONArray ids = AndroidNotificationPayload.idsFromRequest(new JSONObject()
                .put("id", "fallback")
                .put("ids", new JSONArray()
                        .put(" first ")
                        .put("")
                        .put("second")));

        assertEquals(2, ids.length());
        assertEquals("first", ids.getString(0));
        assertEquals("second", ids.getString(1));

        assertEquals("legacy-id", AndroidNotificationPayload.idsFromRequest(
                new JSONObject().put("notificationId", "legacy-id")
        ).getString(0));
    }

    @Test
    public void openedEventWrapsNotificationAndDataPayloads() throws Exception {
        JSONObject notification = AndroidNotificationPayload.notificationPayload(
                "notif-2",
                "Printed",
                "Kitchen",
                "Bon fertig",
                "kitchen",
                "{\"ticket\":\"A7\"}"
        );
        JSONObject event = AndroidNotificationPayload.openedEvent(
                "notif-2",
                notification,
                AndroidNotificationPayload.dataObject("{\"ticket\":\"A7\"}")
        );

        assertEquals("android", event.getString("platform"));
        assertEquals("notificationOpened", event.getString("action"));
        assertTrue(event.getBoolean("success"));
        assertEquals("local", event.getString("source"));
        assertEquals("notif-2", event.getString("id"));
        assertEquals("Printed", event.getJSONObject("notification").getString("title"));
        assertEquals("A7", event.getJSONObject("data").getString("ticket"));
    }
}
