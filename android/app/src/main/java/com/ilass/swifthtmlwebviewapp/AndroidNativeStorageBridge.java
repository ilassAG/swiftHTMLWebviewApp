package com.ilass.swifthtmlwebviewapp;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Iterator;

final class AndroidNativeStorageBridge {
    private static final String PREFS_NAME = "native_storage_v1";

    private final Context context;

    AndroidNativeStorageBridge(Context context) {
        this.context = context.getApplicationContext();
    }

    JSONObject get(JSONObject request) throws JSONException {
        String namespace = namespace(request);
        JSONObject response = BridgeResponse.base(request, "storageGet");
        response.put("success", true);
        response.put("namespace", namespace);
        String key = optionalKey(request.opt("key"));
        if (!key.isEmpty()) {
            response.put("key", key);
            String raw = prefs().getString(storageKey(namespace, key), null);
            response.put("found", raw != null);
            response.put("value", raw == null ? JSONObject.NULL : decode(raw));
        } else {
            response.put("values", values(namespace));
        }
        return response;
    }

    JSONObject set(JSONObject request) throws JSONException {
        String namespace = namespace(request);
        JSONObject values = request.optJSONObject("values");
        if (values == null) {
            values = new JSONObject();
            values.put(requiredKey(request.opt("key")), request.has("value") ? request.opt("value") : JSONObject.NULL);
        }
        SharedPreferences.Editor editor = prefs().edit();
        ArrayList<String> keys = new ArrayList<>();
        for (Iterator<String> it = values.keys(); it.hasNext(); ) {
            String key = requiredKey(it.next());
            keys.add(key);
            Object value = values.opt(key);
            if (value == null || value == JSONObject.NULL) {
                editor.remove(storageKey(namespace, key));
            } else {
                editor.putString(storageKey(namespace, key), encode(value));
            }
        }
        editor.apply();
        Collections.sort(keys);
        JSONObject response = BridgeResponse.base(request, "storageSet");
        response.put("success", true);
        response.put("namespace", namespace);
        response.put("keys", new JSONArray(keys));
        response.put("values", values(namespace));
        return response;
    }

    JSONObject remove(JSONObject request) throws JSONException {
        String namespace = namespace(request);
        JSONArray rawKeys = request.optJSONArray("keys");
        ArrayList<String> keys = new ArrayList<>();
        if (rawKeys != null) {
            for (int i = 0; i < rawKeys.length(); i++) {
                keys.add(requiredKey(rawKeys.opt(i)));
            }
        } else {
            keys.add(requiredKey(request.opt("key")));
        }
        SharedPreferences.Editor editor = prefs().edit();
        for (String key : keys) {
            editor.remove(storageKey(namespace, key));
        }
        editor.apply();
        JSONObject response = BridgeResponse.base(request, "storageRemove");
        response.put("success", true);
        response.put("namespace", namespace);
        response.put("keys", new JSONArray(keys));
        response.put("values", values(namespace));
        return response;
    }

    JSONObject clear(JSONObject request) throws JSONException {
        String namespace = namespace(request);
        String prefix = storagePrefix(namespace);
        SharedPreferences.Editor editor = prefs().edit();
        for (String key : prefs().getAll().keySet()) {
            if (key.startsWith(prefix)) {
                editor.remove(key);
            }
        }
        editor.apply();
        JSONObject response = BridgeResponse.base(request, "storageClear");
        response.put("success", true);
        response.put("namespace", namespace);
        return response;
    }

    private JSONObject values(String namespace) throws JSONException {
        String prefix = storagePrefix(namespace);
        JSONObject result = new JSONObject();
        for (String key : prefs().getAll().keySet()) {
            if (key.startsWith(prefix)) {
                String raw = prefs().getString(key, null);
                result.put(key.substring(prefix.length()), raw == null ? JSONObject.NULL : decode(raw));
            }
        }
        return result;
    }

    private Object decode(String raw) throws JSONException {
        if (raw != null && raw.startsWith("s:")) {
            return raw.substring(2);
        }
        String trimmed = raw == null ? "" : raw.trim();
        if (trimmed.startsWith("{")) {
            return new JSONObject(trimmed);
        }
        if (trimmed.startsWith("[")) {
            return new JSONArray(trimmed);
        }
        if ("true".equals(trimmed) || "false".equals(trimmed)) {
            return Boolean.valueOf(trimmed);
        }
        if ("null".equals(trimmed)) {
            return JSONObject.NULL;
        }
        try {
            if (trimmed.contains(".")) {
                return Double.valueOf(trimmed);
            }
            return Long.valueOf(trimmed);
        } catch (NumberFormatException ignored) {
            return trimmed;
        }
    }

    private String encode(Object value) {
        if (value instanceof String) {
            return "s:" + value;
        }
        return String.valueOf(value);
    }

    private String namespace(JSONObject request) {
        String value = request.optString("namespace", "").trim();
        return value.isEmpty() ? "default" : value;
    }

    private String optionalKey(Object value) throws JSONException {
        if (value == null || value == JSONObject.NULL) {
            return "";
        }
        String key = String.valueOf(value).trim();
        if (key.indexOf('\0') >= 0) {
            throw new JSONException("Storage key is invalid.");
        }
        return key;
    }

    private String requiredKey(Object value) throws JSONException {
        String key = optionalKey(value);
        if (key.isEmpty()) {
            throw new JSONException("A non-empty storage key is required.");
        }
        return key;
    }

    private String storagePrefix(String namespace) {
        return namespace + ".";
    }

    private String storageKey(String namespace, String key) {
        return storagePrefix(namespace) + key;
    }

    private SharedPreferences prefs() {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
    }
}
