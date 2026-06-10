package com.ilass.swifthtmlwebviewapp;

import android.Manifest;
import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;
import android.provider.Settings;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.Iterator;
import java.util.Locale;
import java.util.UUID;

final class AndroidNotificationBridge {
    static final String ACTION_FIRE_NOTIFICATION = "com.ilass.swifthtmlwebviewapp.NOTIFICATION_FIRE";
    static final String EXTRA_TAPPED = "swiftHTMLNotificationTapped";
    static final String EXTRA_ID = "notificationId";
    static final String EXTRA_TITLE = "notificationTitle";
    static final String EXTRA_SUBTITLE = "notificationSubtitle";
    static final String EXTRA_BODY = "notificationBody";
    static final String EXTRA_CHANNEL_ID = "notificationChannelId";
    static final String EXTRA_DATA = "notificationData";

    private static final String DEFAULT_CHANNEL_ID = "swift_html_alerts";
    private static final String DEFAULT_CHANNEL_NAME = "Local alerts";
    private static final String PREFS_NAME = "swift_html_webview_notifications";
    private static final String PENDING_KEY = "pending";

    private final Context context;

    AndroidNotificationBridge(Context context) {
        this.context = context.getApplicationContext();
        ensureChannel(DEFAULT_CHANNEL_ID, DEFAULT_CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH);
    }

    JSONObject permissionStatus(JSONObject request) throws JSONException {
        JSONObject response = baseResponse(request, "notificationPermissionGet");
        response.put("success", true);
        response.put("authorized", hasPermission());
        response.put("authorizationStatus", authorizationStatus());
        response.put("needsRuntimePermission", Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU);
        response.put("settingsIntentAction", Settings.ACTION_APP_NOTIFICATION_SETTINGS);
        return response;
    }

    JSONObject permissionRequestResult(JSONObject request, boolean granted) throws JSONException {
        JSONObject response = baseResponse(request, "notificationPermissionRequest");
        response.put("success", true);
        response.put("authorized", hasPermission());
        response.put("granted", granted);
        response.put("authorizationStatus", authorizationStatus());
        return response;
    }

    JSONObject show(JSONObject request) throws JSONException {
        if (!hasPermission()) {
            return permissionError(request, "notificationShow");
        }
        String id = notificationId(request);
        showNotification(context, request, id);

        JSONObject response = baseResponse(request, "notificationShow");
        response.put("success", true);
        response.put("id", id);
        response.put("immediate", true);
        return response;
    }

    JSONObject schedule(JSONObject request) throws JSONException {
        if (!hasPermission()) {
            return permissionError(request, "notificationSchedule");
        }
        String id = notificationId(request);
        long seconds = Math.max(1L, Math.round(request.optDouble("seconds",
                request.optDouble("delaySeconds", request.optDouble("timeIntervalSeconds", 10.0)))));
        long triggerAtMs = System.currentTimeMillis() + seconds * 1000L;
        JSONObject stored = notificationPayload(request, id);
        stored.put("scheduledAtMs", triggerAtMs);
        stored.put("seconds", seconds);

        Intent intent = receiverIntent(context, stored);
        PendingIntent pendingIntent = PendingIntent.getBroadcast(
                context,
                requestCode(id),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );

        AlarmManager alarmManager = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        if (alarmManager == null) {
            return errorResponse(request, "notificationSchedule", "AlarmManager is not available.");
        }
        alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAtMs, pendingIntent);
        storePending(id, stored);

        JSONObject response = baseResponse(request, "notificationSchedule");
        response.put("success", true);
        response.put("id", id);
        response.put("seconds", seconds);
        response.put("scheduledAtMs", triggerAtMs);
        return response;
    }

    JSONObject cancel(JSONObject request) throws JSONException {
        JSONArray ids = idsFromRequest(request);
        for (int index = 0; index < ids.length(); index += 1) {
            String id = ids.optString(index, "").trim();
            if (id.isEmpty()) {
                continue;
            }
            cancelOne(id);
        }

        JSONObject response = baseResponse(request, "notificationCancel");
        response.put("success", true);
        response.put("ids", ids);
        response.put("count", ids.length());
        return response;
    }

    JSONObject cancelAll(JSONObject request) throws JSONException {
        JSONObject pending = pendingObject();
        Iterator<String> keys = pending.keys();
        while (keys.hasNext()) {
            cancelAlarm(keys.next());
        }
        prefs().edit().remove(PENDING_KEY).apply();
        NotificationManager manager = notificationManager(context);
        if (manager != null) {
            manager.cancelAll();
        }

        JSONObject response = baseResponse(request, "notificationCancelAll");
        response.put("success", true);
        return response;
    }

    JSONObject list(JSONObject request) throws JSONException {
        JSONObject response = baseResponse(request, "notificationList");
        response.put("success", true);
        response.put("pending", pendingArray());
        response.put("delivered", new JSONArray());
        return response;
    }

    JSONObject openedEvent(Intent intent) throws JSONException {
        JSONObject response = new JSONObject();
        response.put("platform", "android");
        response.put("action", "notificationOpened");
        response.put("success", true);
        response.put("source", "local");
        response.put("id", intent.getStringExtra(EXTRA_ID));
        response.put("notification", notificationPayload(intent));
        response.put("data", dataObject(intent.getStringExtra(EXTRA_DATA)));
        return response;
    }

    static void handleAlarmIntent(Context context, Intent intent) {
        String id = intent.getStringExtra(EXTRA_ID);
        try {
            showNotification(context, notificationPayload(intent), id != null ? id : UUID.randomUUID().toString());
            removePending(context, id);
        } catch (JSONException ignored) {
            // The receiver cannot report bridge errors; ignore malformed notification payloads.
        }
    }

    static void showNotification(Context context, JSONObject payload, String id) throws JSONException {
        String channelId = nonEmpty(payload.optString("channelId", payload.optString("channel", "")), DEFAULT_CHANNEL_ID);
        String channelName = nonEmpty(payload.optString("channelName", ""), DEFAULT_CHANNEL_NAME);
        int importance = importanceFromPayload(payload);
        ensureChannel(context, channelId, channelName, importance);

        Intent tapIntent = new Intent(context, MainActivity.class)
                .setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .putExtra(EXTRA_TAPPED, true)
                .putExtra(EXTRA_ID, id)
                .putExtra(EXTRA_TITLE, payload.optString("title", "Notification"))
                .putExtra(EXTRA_SUBTITLE, payload.optString("subtitle", ""))
                .putExtra(EXTRA_BODY, payload.optString("body", payload.optString("message", "")))
                .putExtra(EXTRA_CHANNEL_ID, channelId)
                .putExtra(EXTRA_DATA, dataString(payload));
        PendingIntent contentIntent = PendingIntent.getActivity(
                context,
                requestCode(id),
                tapIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );

        Notification.Builder builder = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? new Notification.Builder(context, channelId)
                : new Notification.Builder(context);
        builder.setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(nonEmpty(payload.optString("title", ""), "Notification"))
                .setContentText(nonEmpty(payload.optString("body", payload.optString("message", "")), ""))
                .setAutoCancel(true)
                .setContentIntent(contentIntent)
                .setCategory(Notification.CATEGORY_STATUS)
                .setPriority(priorityFromImportance(importance))
                .setTicker(nonEmpty(payload.optString("title", ""), "Notification"))
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setShowWhen(true)
                .setWhen(System.currentTimeMillis());
        String subtitle = payload.optString("subtitle", "").trim();
        if (!subtitle.isEmpty()) {
            builder.setSubText(subtitle);
        }
        String body = payload.optString("body", payload.optString("message", ""));
        if (!body.trim().isEmpty()) {
            builder.setStyle(new Notification.BigTextStyle().bigText(body));
        }
        if (!payload.has("sound") || payload.optBoolean("sound", true)) {
            builder.setDefaults(Notification.DEFAULT_SOUND);
        }

        NotificationManager manager = notificationManager(context);
        if (manager != null) {
            manager.notify(requestCode(id), builder.build());
        }
    }

    private JSONObject permissionError(JSONObject request, String action) throws JSONException {
        JSONObject response = baseResponse(request, action);
        response.put("success", false);
        response.put("authorized", false);
        response.put("authorizationStatus", authorizationStatus());
        response.put("error", "Notification permission is not granted.");
        return response;
    }

    private JSONObject notificationPayload(JSONObject request, String id) throws JSONException {
        JSONObject payload = new JSONObject();
        payload.put("id", id);
        payload.put("title", nonEmpty(request.optString("title", ""), "Notification"));
        payload.put("subtitle", request.optString("subtitle", ""));
        payload.put("body", request.optString("body", request.optString("message", "")));
        payload.put("channelId", request.optString("channelId", DEFAULT_CHANNEL_ID));
        payload.put("channelName", request.optString("channelName", DEFAULT_CHANNEL_NAME));
        payload.put("importance", request.optString("importance", "high"));
        payload.put("sound", !request.has("sound") || request.optBoolean("sound", true));
        payload.put("data", request.optJSONObject("data") != null ? request.optJSONObject("data") : new JSONObject());
        return payload;
    }

    private static JSONObject notificationPayload(Intent intent) throws JSONException {
        JSONObject payload = new JSONObject();
        payload.put("id", intent.getStringExtra(EXTRA_ID));
        payload.put("title", intent.getStringExtra(EXTRA_TITLE));
        payload.put("subtitle", intent.getStringExtra(EXTRA_SUBTITLE));
        payload.put("body", intent.getStringExtra(EXTRA_BODY));
        payload.put("channelId", intent.getStringExtra(EXTRA_CHANNEL_ID));
        payload.put("data", dataObject(intent.getStringExtra(EXTRA_DATA)));
        return payload;
    }

    private static Intent receiverIntent(Context context, JSONObject payload) {
        return new Intent(context, NotificationReceiver.class)
                .setAction(ACTION_FIRE_NOTIFICATION)
                .putExtra(EXTRA_ID, payload.optString("id", ""))
                .putExtra(EXTRA_TITLE, payload.optString("title", "Notification"))
                .putExtra(EXTRA_SUBTITLE, payload.optString("subtitle", ""))
                .putExtra(EXTRA_BODY, payload.optString("body", ""))
                .putExtra(EXTRA_CHANNEL_ID, payload.optString("channelId", DEFAULT_CHANNEL_ID))
                .putExtra(EXTRA_DATA, dataString(payload));
    }

    private JSONArray idsFromRequest(JSONObject request) throws JSONException {
        JSONArray ids = new JSONArray();
        JSONArray requestIds = request.optJSONArray("ids");
        if (requestIds != null) {
            for (int index = 0; index < requestIds.length(); index += 1) {
                String id = requestIds.optString(index, "").trim();
                if (!id.isEmpty()) {
                    ids.put(id);
                }
            }
            return ids;
        }
        String id = notificationId(request);
        if (!id.isEmpty()) {
            ids.put(id);
        }
        return ids;
    }

    private void cancelOne(String id) throws JSONException {
        cancelAlarm(id);
        JSONObject pending = pendingObject();
        pending.remove(id);
        prefs().edit().putString(PENDING_KEY, pending.toString()).apply();
        NotificationManager manager = notificationManager(context);
        if (manager != null) {
            manager.cancel(requestCode(id));
        }
    }

    private void cancelAlarm(String id) {
        Intent intent = new Intent(context, NotificationReceiver.class).setAction(ACTION_FIRE_NOTIFICATION);
        PendingIntent pendingIntent = PendingIntent.getBroadcast(
                context,
                requestCode(id),
                intent,
                PendingIntent.FLAG_NO_CREATE | PendingIntent.FLAG_IMMUTABLE
        );
        if (pendingIntent != null) {
            AlarmManager alarmManager = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
            if (alarmManager != null) {
                alarmManager.cancel(pendingIntent);
            }
            pendingIntent.cancel();
        }
    }

    private void storePending(String id, JSONObject payload) throws JSONException {
        JSONObject pending = pendingObject();
        pending.put(id, payload);
        prefs().edit().putString(PENDING_KEY, pending.toString()).apply();
    }

    private JSONArray pendingArray() throws JSONException {
        JSONObject pending = pendingObject();
        JSONArray array = new JSONArray();
        Iterator<String> keys = pending.keys();
        while (keys.hasNext()) {
            String key = keys.next();
            JSONObject item = pending.optJSONObject(key);
            if (item != null) {
                array.put(item);
            }
        }
        return array;
    }

    private JSONObject pendingObject() throws JSONException {
        return new JSONObject(prefs().getString(PENDING_KEY, "{}"));
    }

    private SharedPreferences prefs() {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
    }

    private String notificationId(JSONObject request) {
        return nonEmpty(request.optString("id", request.optString("notificationId", "")), UUID.randomUUID().toString());
    }

    private boolean hasPermission() {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU
                || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED;
    }

    private String authorizationStatus() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return "authorized";
        }
        return hasPermission() ? "authorized" : "denied";
    }

    private JSONObject baseResponse(JSONObject request, String action) throws JSONException {
        JSONObject response = new JSONObject();
        response.put("platform", "android");
        response.put("action", action);
        if (request != null && request.has("requestId")) {
            response.put("requestId", request.optString("requestId"));
        }
        return response;
    }

    private JSONObject errorResponse(JSONObject request, String action, String error) throws JSONException {
        JSONObject response = baseResponse(request, action);
        response.put("success", false);
        response.put("error", error);
        return response;
    }

    private static void removePending(Context context, String id) throws JSONException {
        if (id == null || id.trim().isEmpty()) {
            return;
        }
        SharedPreferences prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        JSONObject pending = new JSONObject(prefs.getString(PENDING_KEY, "{}"));
        pending.remove(id);
        prefs.edit().putString(PENDING_KEY, pending.toString()).apply();
    }

    private static void ensureChannel(Context context, String channelId, String channelName, int importance) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return;
        }
        NotificationManager manager = notificationManager(context);
        if (manager == null || manager.getNotificationChannel(channelId) != null) {
            return;
        }
        NotificationChannel channel = new NotificationChannel(channelId, channelName, importance);
        manager.createNotificationChannel(channel);
    }

    private static int importanceFromPayload(JSONObject payload) {
        String importance = payload.optString("importance", payload.optString("priority", "high")).trim().toLowerCase(Locale.US);
        switch (importance) {
            case "min":
            case "minimum":
                return NotificationManager.IMPORTANCE_MIN;
            case "low":
                return NotificationManager.IMPORTANCE_LOW;
            case "default":
            case "normal":
                return NotificationManager.IMPORTANCE_DEFAULT;
            case "max":
            case "urgent":
            case "high":
            default:
                return NotificationManager.IMPORTANCE_HIGH;
        }
    }

    private static int priorityFromImportance(int importance) {
        if (importance >= NotificationManager.IMPORTANCE_HIGH) {
            return Notification.PRIORITY_HIGH;
        }
        if (importance <= NotificationManager.IMPORTANCE_LOW) {
            return Notification.PRIORITY_LOW;
        }
        return Notification.PRIORITY_DEFAULT;
    }

    private void ensureChannel(String channelId, String channelName, int importance) {
        ensureChannel(context, channelId, channelName, importance);
    }

    private static NotificationManager notificationManager(Context context) {
        return (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
    }

    private static int requestCode(String id) {
        return nonEmpty(id, "notification").toLowerCase(Locale.US).hashCode() & 0x7fffffff;
    }

    private static String dataString(JSONObject payload) {
        JSONObject data = payload.optJSONObject("data");
        return data != null ? data.toString() : "{}";
    }

    private static JSONObject dataObject(String raw) throws JSONException {
        if (raw == null || raw.trim().isEmpty()) {
            return new JSONObject();
        }
        return new JSONObject(raw);
    }

    private static String nonEmpty(String value, String fallback) {
        String trimmed = value != null ? value.trim() : "";
        return trimmed.isEmpty() ? fallback : trimmed;
    }
}
