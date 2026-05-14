package com.ilass.swifthtmlwebviewapp;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.os.Bundle;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;

import org.json.JSONException;
import org.json.JSONObject;

public class MainActivity extends Activity {
    private static final String DEFAULT_URL = "file:///android_asset/index.html";
    private WebView webView;

    @SuppressLint({"SetJavaScriptEnabled", "AddJavascriptInterface"})
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        webView = new WebView(this);
        setContentView(webView);

        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setMediaPlaybackRequiresUserGesture(false);
        settings.setAllowFileAccess(true);
        settings.setAllowContentAccess(true);
        settings.setLoadWithOverviewMode(true);
        settings.setUseWideViewPort(true);

        webView.setWebChromeClient(new WebChromeClient());
        webView.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageFinished(WebView view, String url) {
                injectBridgeShim();
            }
        });
        webView.addJavascriptInterface(new NativeBridge(), "AndroidNativeBridge");
        String startUrl = getIntent() != null && getIntent().getDataString() != null
                ? getIntent().getDataString()
                : DEFAULT_URL;
        webView.loadUrl(startUrl);
    }

    @Override
    public void onBackPressed() {
        if (webView != null && webView.canGoBack()) {
            webView.goBack();
            return;
        }
        super.onBackPressed();
    }

    private void injectBridgeShim() {
        String script = "(function(){"
                + "window.webkit=window.webkit||{};"
                + "window.webkit.messageHandlers=window.webkit.messageHandlers||{};"
                + "window.webkit.messageHandlers.swiftBridge={postMessage:function(message){"
                + "window.AndroidNativeBridge.postMessage(JSON.stringify(message||{}));"
                + "}};"
                + "})();";
        webView.evaluateJavascript(script, null);
    }

    private void sendResult(JSONObject payload) {
        String script = "if(window.handleNativeResult){window.handleNativeResult(" + payload.toString() + ");}";
        runOnUiThread(() -> webView.evaluateJavascript(script, null));
    }

    public class NativeBridge {
        @JavascriptInterface
        public void postMessage(String rawMessage) {
            try {
                JSONObject message = new JSONObject(rawMessage == null ? "{}" : rawMessage);
                String action = message.optString("action", "");
                JSONObject response = baseResponse(message, action);

                switch (action) {
                    case "launchConfetti":
                        response.put("status", "ok");
                        response.put("nativeStatus", "toast");
                        runOnUiThread(() -> Toast.makeText(MainActivity.this, "Confetti", Toast.LENGTH_SHORT).show());
                        break;
                    case "tapToPayAvailability":
                        response.put("available", false);
                        response.put("readerType", "android");
                        response.put("reason", "Android Tap to Pay bridge is not implemented in this wrapper build yet.");
                        break;
                    case "tapToPayCollect":
                        response.put("error", "Android Tap to Pay bridge is not implemented in this wrapper build yet.");
                        break;
                    case "scanDocument":
                    case "takePhoto":
                    case "scanBarcode":
                        response.put("error", action + " is not implemented on Android yet.");
                        break;
                    default:
                        response.put("error", "Unknown native action: " + action);
                }

                sendResult(response);
            } catch (JSONException error) {
                JSONObject response = new JSONObject();
                try {
                    response.put("action", "unknown");
                    response.put("error", error.getMessage());
                } catch (JSONException ignored) {
                    // Ignore secondary JSON failure.
                }
                sendResult(response);
            }
        }
    }

    private JSONObject baseResponse(JSONObject message, String action) throws JSONException {
        JSONObject response = new JSONObject();
        response.put("platform", "android");
        response.put("action", action);
        if (message.has("requestId")) {
            response.put("requestId", message.optString("requestId"));
        }
        if (message.has("paymentId")) {
            response.put("paymentId", message.optString("paymentId"));
        }
        return response;
    }
}
