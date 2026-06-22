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

    private static final String PREFS_NAME = "swift_html_webview_notifications";
    private static final String PENDING_KEY = "pending";

    private final Context context;

    AndroidNotificationBridge(Context context) {
        this.context = context.getApplicationContext();
        ensureChannel(AndroidNotificationPayload.DEFAULT_CHANNEL_ID, AndroidNotificationPayload.DEFAULT_CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH);
    }

    JSONObject permissionStatus(JSONObject request) throws JSONException {
        return AndroidNotificationPayload.permissionStatusResponse(
                request,
                hasPermission(),
                authorizationStatus(),
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU,
                Settings.ACTION_APP_NOTIFICATION_SETTINGS
        );
    }

    JSONObject permissionRequestResult(JSONObject request, boolean granted) throws JSONException {
        return AndroidNotificationPayload.permissionRequestResponse(
                request,
                hasPermission(),
                granted,
                authorizationStatus()
        );
    }

    JSONObject show(JSONObject request) throws JSONException {
        if (!hasPermission()) {
            return permissionError(request, "notificationShow");
        }
        String id = AndroidNotificationPayload.notificationId(request);
        showNotification(context, request, id);
        return AndroidNotificationPayload.showResponse(request, id);
    }

    JSONObject schedule(JSONObject request) throws JSONException {
        if (!hasPermission()) {
            return permissionError(request, "notificationSchedule");
        }
        String id = AndroidNotificationPayload.notificationId(request);
        long seconds = Math.max(1L, Math.round(request.optDouble("seconds",
                request.optDouble("delaySeconds", request.optDouble("timeIntervalSeconds", 10.0)))));
        long triggerAtMs = System.currentTimeMillis() + seconds * 1000L;
        JSONObject stored = AndroidNotificationPayload.notificationPayload(request, id);
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
            return AndroidNotificationPayload.errorResponse(request, "notificationSchedule", "AlarmManager is not available.");
        }
        alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAtMs, pendingIntent);
        storePending(id, stored);
        return AndroidNotificationPayload.scheduleResponse(request, id, seconds, triggerAtMs);
    }

    JSONObject cancel(JSONObject request) throws JSONException {
        JSONArray ids = AndroidNotificationPayload.idsFromRequest(request);
        for (int index = 0; index < ids.length(); index += 1) {
            String id = ids.optString(index, "").trim();
            if (id.isEmpty()) {
                continue;
            }
            cancelOne(id);
        }

        return AndroidNotificationPayload.cancelResponse(request, ids);
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

        return AndroidNotificationPayload.cancelAllResponse(request);
    }

    JSONObject list(JSONObject request) throws JSONException {
        return AndroidNotificationPayload.listResponse(request, pendingArray());
    }

    JSONObject openedEvent(Intent intent) throws JSONException {
        return AndroidNotificationPayload.openedEvent(
                intent.getStringExtra(EXTRA_ID),
                notificationPayload(intent),
                AndroidNotificationPayload.dataObject(intent.getStringExtra(EXTRA_DATA))
        );
    }

    static void handleAlarmIntent(Context context, Intent intent) {
        String id = intent.getStringExtra(EXTRA_ID);
        try {
            showNotification(context, notificationPayload(intent), AndroidNotificationPayload.nonEmpty(id, UUID.randomUUID().toString()));
            removePending(context, id);
        } catch (JSONException ignored) {
            // The receiver cannot report bridge errors; ignore malformed notification payloads.
        }
    }

    static void showNotification(Context context, JSONObject payload, String id) throws JSONException {
        String channelId = AndroidNotificationPayload.nonEmpty(payload.optString("channelId", payload.optString("channel", "")), AndroidNotificationPayload.DEFAULT_CHANNEL_ID);
        String channelName = AndroidNotificationPayload.nonEmpty(payload.optString("channelName", ""), AndroidNotificationPayload.DEFAULT_CHANNEL_NAME);
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
                .putExtra(EXTRA_DATA, AndroidNotificationPayload.dataString(payload));
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
                .setContentTitle(AndroidNotificationPayload.nonEmpty(payload.optString("title", ""), "Notification"))
                .setContentText(AndroidNotificationPayload.nonEmpty(payload.optString("body", payload.optString("message", "")), ""))
                .setAutoCancel(true)
                .setContentIntent(contentIntent)
                .setCategory(Notification.CATEGORY_STATUS)
                .setPriority(priorityFromImportance(importance))
                .setTicker(AndroidNotificationPayload.nonEmpty(payload.optString("title", ""), "Notification"))
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
        return AndroidNotificationPayload.permissionError(request, action, authorizationStatus());
    }

    private static JSONObject notificationPayload(Intent intent) throws JSONException {
        return AndroidNotificationPayload.notificationPayload(
                intent.getStringExtra(EXTRA_ID),
                intent.getStringExtra(EXTRA_TITLE),
                intent.getStringExtra(EXTRA_SUBTITLE),
                intent.getStringExtra(EXTRA_BODY),
                intent.getStringExtra(EXTRA_CHANNEL_ID),
                intent.getStringExtra(EXTRA_DATA)
        );
    }

    private static Intent receiverIntent(Context context, JSONObject payload) {
        return new Intent(context, NotificationReceiver.class)
                .setAction(ACTION_FIRE_NOTIFICATION)
                .putExtra(EXTRA_ID, payload.optString("id", ""))
                .putExtra(EXTRA_TITLE, payload.optString("title", "Notification"))
                .putExtra(EXTRA_SUBTITLE, payload.optString("subtitle", ""))
                .putExtra(EXTRA_BODY, payload.optString("body", ""))
                .putExtra(EXTRA_CHANNEL_ID, payload.optString("channelId", AndroidNotificationPayload.DEFAULT_CHANNEL_ID))
                .putExtra(EXTRA_DATA, AndroidNotificationPayload.dataString(payload));
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
        return AndroidNotificationPayload.nonEmpty(id, "notification").toLowerCase(Locale.US).hashCode() & 0x7fffffff;
    }
}
