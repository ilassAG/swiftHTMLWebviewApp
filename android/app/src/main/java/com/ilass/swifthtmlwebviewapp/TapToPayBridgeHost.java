package com.ilass.swifthtmlwebviewapp;

import android.content.Context;

import org.json.JSONException;
import org.json.JSONObject;

interface TapToPayBridgeHost {
    Context applicationContext();

    boolean hasSystemFeature(String featureName);

    void runOnUiThread(Runnable action);

    JSONObject baseResponse(JSONObject message, String action) throws JSONException;

    void sendResult(JSONObject payload);

    void sendError(JSONObject source, String action, String error) throws JSONException;

    void sendErrorSafe(JSONObject source, String action, String error);

    void showTapToPayTransition();

    void hideTapToPayTransition();
}
