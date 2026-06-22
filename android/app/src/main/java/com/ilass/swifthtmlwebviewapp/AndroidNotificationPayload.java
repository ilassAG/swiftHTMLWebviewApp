package com.ilass.swifthtmlwebviewapp;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.UUID;

final class AndroidNotificationPayload {
    static final String DEFAULT_CHANNEL_ID = "swift_html_alerts";
    static final String DEFAULT_CHANNEL_NAME = "Local alerts";

    private AndroidNotificationPayload() {
    }

    static JSONObject baseResponse(JSONObject request, String action) throws JSONException {
        JSONObject response = new JSONObject();
        response.put("platform", "android");
        response.put("action", action);
        if (request != null && request.has("requestId")) {
            response.put("requestId", request.optString("requestId"));
        }
        return response;
    }

    static JSONObject errorResponse(JSONObject request, String action, String error) throws JSONException {
        JSONObject response = baseResponse(request, action);
        response.put("success", false);
        response.put("error", error);
        return response;
    }

    static JSONObject permissionError(JSONObject request, String action, String authorizationStatus) throws JSONException {
        JSONObject response = baseResponse(request, action);
        response.put("success", false);
        response.put("authorized", false);
        response.put("authorizationStatus", authorizationStatus);
        response.put("error", "Notification permission is not granted.");
        return response;
    }

    static JSONObject permissionStatusResponse(
            JSONObject request,
            boolean authorized,
            String authorizationStatus,
            boolean needsRuntimePermission,
            String settingsIntentAction
    ) throws JSONException {
        JSONObject response = baseResponse(request, "notificationPermissionGet");
        response.put("success", true);
        response.put("authorized", authorized);
        response.put("authorizationStatus", authorizationStatus);
        response.put("needsRuntimePermission", needsRuntimePermission);
        response.put("settingsIntentAction", settingsIntentAction);
        return response;
    }

    static JSONObject permissionRequestResponse(
            JSONObject request,
            boolean authorized,
            boolean granted,
            String authorizationStatus
    ) throws JSONException {
        JSONObject response = baseResponse(request, "notificationPermissionRequest");
        response.put("success", true);
        response.put("authorized", authorized);
        response.put("granted", granted);
        response.put("authorizationStatus", authorizationStatus);
        return response;
    }

    static JSONObject showResponse(JSONObject request, String id) throws JSONException {
        JSONObject response = baseResponse(request, "notificationShow");
        response.put("success", true);
        response.put("id", id);
        response.put("immediate", true);
        return response;
    }

    static JSONObject scheduleResponse(JSONObject request, String id, long seconds, long scheduledAtMs) throws JSONException {
        JSONObject response = baseResponse(request, "notificationSchedule");
        response.put("success", true);
        response.put("id", id);
        response.put("seconds", seconds);
        response.put("scheduledAtMs", scheduledAtMs);
        return response;
    }

    static JSONObject cancelResponse(JSONObject request, JSONArray ids) throws JSONException {
        JSONArray safeIds = ids != null ? ids : new JSONArray();
        JSONObject response = baseResponse(request, "notificationCancel");
        response.put("success", true);
        response.put("ids", safeIds);
        response.put("count", safeIds.length());
        return response;
    }

    static JSONObject cancelAllResponse(JSONObject request) throws JSONException {
        JSONObject response = baseResponse(request, "notificationCancelAll");
        response.put("success", true);
        return response;
    }

    static JSONObject listResponse(JSONObject request, JSONArray pending) throws JSONException {
        JSONObject response = baseResponse(request, "notificationList");
        response.put("success", true);
        response.put("pending", pending != null ? pending : new JSONArray());
        response.put("delivered", new JSONArray());
        return response;
    }

    static JSONObject notificationPayload(JSONObject request, String id) throws JSONException {
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

    static JSONObject notificationPayload(
            String id,
            String title,
            String subtitle,
            String body,
            String channelId,
            String dataRaw
    ) throws JSONException {
        JSONObject payload = new JSONObject();
        payload.put("id", id);
        payload.put("title", title);
        payload.put("subtitle", subtitle);
        payload.put("body", body);
        payload.put("channelId", channelId);
        payload.put("data", dataObject(dataRaw));
        return payload;
    }

    static JSONObject openedEvent(String id, JSONObject notification, JSONObject data) throws JSONException {
        JSONObject response = new JSONObject();
        response.put("platform", "android");
        response.put("action", "notificationOpened");
        response.put("success", true);
        response.put("source", "local");
        response.put("id", id);
        response.put("notification", notification);
        response.put("data", data);
        return response;
    }

    static JSONArray idsFromRequest(JSONObject request) throws JSONException {
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

    static String notificationId(JSONObject request) {
        return notificationId(request, UUID.randomUUID().toString());
    }

    static String notificationId(JSONObject request, String fallback) {
        return nonEmpty(request.optString("id", request.optString("notificationId", "")), fallback);
    }

    static String dataString(JSONObject payload) {
        JSONObject data = payload.optJSONObject("data");
        return data != null ? data.toString() : "{}";
    }

    static JSONObject dataObject(String raw) throws JSONException {
        if (raw == null || raw.trim().isEmpty()) {
            return new JSONObject();
        }
        return new JSONObject(raw);
    }

    static String nonEmpty(String value, String fallback) {
        String trimmed = value != null ? value.trim() : "";
        return trimmed.isEmpty() ? fallback : trimmed;
    }
}
