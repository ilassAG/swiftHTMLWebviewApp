package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

import org.json.JSONException;
import org.json.JSONObject;
import org.junit.Test;

public class AndroidContinuousScannerEventBuilderTest {
    @Test
    public void dataEventUsesBarcodeDataAndSourceAction() throws JSONException {
        AndroidContinuousScannerConfig config = AndroidContinuousScannerConfig.from(
                new JSONObject()
                        .put("action", "dataScanStart")
                        .put("mode", "data")
                        .put("camera", "back")
        );

        JSONObject event = AndroidContinuousScannerEventBuilder.event(config, "ABC-123", "qr", 0L);

        assertEquals("android", event.getString("platform"));
        assertEquals("barcodeData", event.getString("action"));
        assertEquals("dataScanStart", event.getString("sourceAction"));
        assertEquals("data", event.getString("mode"));
        assertEquals("back", event.getString("camera"));
        assertEquals("ABC-123", event.getString("code"));
        assertEquals("qr", event.getString("format"));
        assertEquals(expectedTimestamp(0L), event.getString("timestamp"));
    }

    @Test
    public void loginEventUsesBarcodeLogin() throws JSONException {
        AndroidContinuousScannerConfig config = AndroidContinuousScannerConfig.from(
                new JSONObject()
                        .put("action", "loginScanStart")
                        .put("mode", "login")
                        .put("camera", "front")
        );

        JSONObject event = AndroidContinuousScannerEventBuilder.event(config, "LOGIN", "code128", 1000L);

        assertEquals("barcodeLogin", event.getString("action"));
        assertEquals("loginScanStart", event.getString("sourceAction"));
        assertEquals("login", event.getString("mode"));
        assertEquals("front", event.getString("camera"));
        assertEquals("LOGIN", event.getString("code"));
        assertEquals("code128", event.getString("format"));
    }

    @Test
    public void continuousScanStartUsesExplicitModeForEventAction() throws JSONException {
        AndroidContinuousScannerConfig loginConfig = AndroidContinuousScannerConfig.from(
                new JSONObject()
                        .put("action", "continuousScanStart")
                        .put("mode", "login")
        );
        AndroidContinuousScannerConfig dataConfig = AndroidContinuousScannerConfig.from(
                new JSONObject()
                        .put("action", "continuousScanStart")
                        .put("mode", "data")
        );

        JSONObject loginEvent = AndroidContinuousScannerEventBuilder.event(loginConfig, "LOGIN", "qr", 2000L);
        JSONObject dataEvent = AndroidContinuousScannerEventBuilder.event(dataConfig, "DATA", "qr", 2000L);

        assertEquals("barcodeLogin", loginEvent.getString("action"));
        assertEquals("continuousScanStart", loginEvent.getString("sourceAction"));
        assertEquals("barcodeData", dataEvent.getString("action"));
        assertEquals("continuousScanStart", dataEvent.getString("sourceAction"));
    }


    private static String expectedTimestamp(long timeMs) {
        return new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", Locale.US).format(new Date(timeMs));
    }
}
