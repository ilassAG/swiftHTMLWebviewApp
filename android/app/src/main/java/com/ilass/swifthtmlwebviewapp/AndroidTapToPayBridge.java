package com.ilass.swifthtmlwebviewapp;

import org.json.JSONException;
import org.json.JSONObject;

interface AndroidTapToPayBridge {
    void sendAvailability(JSONObject message) throws JSONException;

    void collect(JSONObject message) throws JSONException;
}
