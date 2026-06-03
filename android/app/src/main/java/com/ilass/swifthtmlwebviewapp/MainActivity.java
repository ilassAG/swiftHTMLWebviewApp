package com.ilass.swifthtmlwebviewapp;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.ActivityManager;
import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.IntentSender;
import android.content.IntentFilter;
import android.content.ServiceConnection;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.content.pm.ActivityInfo;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.hardware.Sensor;
import android.hardware.SensorManager;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraManager;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioTrack;
import android.net.ConnectivityManager;
import android.net.LinkAddress;
import android.net.LinkProperties;
import android.net.Network;
import android.net.wifi.WifiConfiguration;
import android.net.wifi.WifiManager;
import android.net.wifi.WifiNetworkSuggestion;
import android.net.Uri;
import android.os.BatteryManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.RemoteException;
import android.provider.MediaStore;
import android.provider.Settings;
import android.util.Base64;
import android.util.DisplayMetrics;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import androidx.activity.ComponentActivity;

import com.google.mlkit.vision.barcode.common.Barcode;
import com.google.mlkit.vision.codescanner.GmsBarcodeScanner;
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions;
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning;
import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.documentscanner.GmsDocumentScanner;
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions;
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning;
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult;
import com.google.mlkit.vision.segmentation.Segmentation;
import com.google.mlkit.vision.segmentation.SegmentationMask;
import com.google.mlkit.vision.segmentation.Segmenter;
import com.google.mlkit.vision.segmentation.selfie.SelfieSegmenterOptions;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.nio.ByteBuffer;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Date;
import java.util.Enumeration;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;

import woyou.aidlservice.jiuiv5.ICallback;
import woyou.aidlservice.jiuiv5.IWoyouService;

public class MainActivity extends ComponentActivity implements ConfettiView.ActivityHost {
    private static final String DEFAULT_URL = "file:///android_asset/index.html";
    private static final int REQUEST_CAMERA_PERMISSION = 2001;
    private static final int REQUEST_IMAGE_CAPTURE = 2002;
    private static final int REQUEST_DOCUMENT_SCAN = 2003;
    private static final int REQUEST_CONTINUOUS_CAMERA_PERMISSION = 2004;
    private static final int REQUEST_BEACON_PERMISSION = 2005;
    private static final int REQUEST_LOCATION_PERMISSION = 2006;
    private static final int REQUEST_WIFI_ADD_NETWORK = 2007;
    private static final int REQUEST_WIFI_STATUS_PERMISSION = 2008;
    private static final String PRINTERCORE_CLASS_NAME = "com.ilass.printercore.Printercore";

    private WebView webView;
    private JSONObject pendingRequest;
    private String pendingAction;
    private JSONObject pendingContinuousScanRequest;
    private JSONObject pendingBeaconStartRequest;
    private JSONObject pendingLocationRequest;
    private JSONObject pendingWifiRequest;
    private JSONObject pendingWifiStatusRequest;
    private ContinuousBarcodeScannerController continuousScannerController;
    private AndroidBeaconBridge beaconBridge;
    private AndroidScreenStreamBridge screenStreamBridge;
    private AndroidSensorBridge sensorBridge;
    private final Handler idleHandler = new Handler(Looper.getMainLooper());
    private boolean idleTimerRunning = false;
    private boolean idleTimedOut = false;
    private long idleLastActivityMs = System.currentTimeMillis();
    private long idleTimeoutMs = 30000L;
    private long idleIntervalMs = 1000L;
    private LocationManager locationManager;
    private LocationListener locationListener;
    private int confettiBursts = 0;

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
                injectIdleActivityShim();
            }
        });
        webView.setOnTouchListener((view, event) -> {
            recordIdleActivity();
            return false;
        });
        webView.addJavascriptInterface(new NativeBridge(), "AndroidNativeBridge");
        continuousScannerController = new ContinuousBarcodeScannerController(this, new ContinuousBarcodeScannerController.Listener() {
            @Override
            public void onScannerEvent(JSONObject event) {
                sendResult(event);
            }

            @Override
            public void onScannerError(String message) {
                sendContinuousScannerError(message);
            }

            @Override
            public void onScannerClosedByUser() {
                sendContinuousScannerClosedByUser();
            }
        });
        beaconBridge = new AndroidBeaconBridge(this, this::sendResult);
        screenStreamBridge = new AndroidScreenStreamBridge(this, this::sendResult);
        sensorBridge = new AndroidSensorBridge(this, this::sendResult);
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

    @Override
    protected void onDestroy() {
        if (continuousScannerController != null) {
            continuousScannerController.shutdown();
        }
        if (beaconBridge != null) {
            beaconBridge.shutdown();
        }
        if (screenStreamBridge != null) {
            screenStreamBridge.shutdown();
        }
        if (sensorBridge != null) {
            sensorBridge.shutdown();
        }
        stopLocationUpdates();
        stopIdleTimer();
        super.onDestroy();
    }

    @Override
    public android.content.Context context() {
        return this;
    }

    @Override
    public void addOverlay(View view) {
        addContentView(view, new ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
        ));
    }

    @Override
    public void removeOverlay(View view) {
        ViewGroup parent = (ViewGroup) view.getParent();
        if (parent != null) {
            parent.removeView(view);
        }
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

    private void injectIdleActivityShim() {
        String script = "(function(){"
                + "if(window.__swiftHTMLIdleShimInstalled){return;}"
                + "window.__swiftHTMLIdleShimInstalled=true;"
                + "function notify(){try{window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.swiftBridge.postMessage({action:'idleActivity',source:'web'});}catch(e){}}"
                + "['pointerdown','touchstart','mousedown','keydown','scroll'].forEach(function(name){document.addEventListener(name,notify,{capture:true,passive:true});});"
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

                switch (action) {
                    case "launchConfetti":
                        launchConfetti(message);
                        break;
                    case "takePhoto":
                        startPhotoCapture(message);
                        break;
                    case "scanBarcode":
                        startBarcodeScanner(message);
                        break;
                    case "scanDocument":
                        startDocumentScanner(message);
                        break;
                    case "tapToPayAvailability":
                        sendTapToPayAvailability(message);
                        break;
                    case "tapToPayCollect":
                        sendError(message, action, "Android Tap to Pay bridge is not implemented in this wrapper build yet.");
                        break;
                    case "deviceInfoGet":
                        sendResult(deviceInfo(message));
                        break;
                    case "screenOrientationGet":
                        sendResult(screenOrientationGet(message));
                        break;
                    case "screenOrientationSet":
                        sendResult(screenOrientationSet(message));
                        break;
                    case "wifiStatusGet":
                        sendWifiStatus(message);
                        break;
                    case "wifiConfigure":
                        configureWifi(message);
                        break;
                    case "screenshotGet":
                        sendResult(screenshotGet(message));
                        break;
                    case "geoLocationGet":
                        getGeoLocation(message);
                        break;
                    case "geoLocationStart":
                        startGeoLocation(message);
                        break;
                    case "geoLocationStop":
                        sendResult(stopGeoLocation(message));
                        break;
                    case "soundPlay":
                        sendResult(playSound(message));
                        break;
                    case "idleTimerStart":
                        sendResult(startIdleTimer(message));
                        break;
                    case "idleTimerStop":
                        sendResult(stopIdleTimer(message));
                        break;
                    case "idleTimerReset":
                        sendResult(resetIdleTimer(message));
                        break;
                    case "idleActivity":
                        recordIdleActivity();
                        break;
                    case "screenStreamStart":
                        sendResult(screenStreamBridge.start(message));
                        break;
                    case "screenStreamStop":
                        sendResult(screenStreamBridge.stop(message));
                        break;
                    case "sensorCapabilitiesGet":
                        sendResult(sensorBridge.capabilities(message));
                        break;
                    case "sensorStreamStart":
                        sendResult(sensorBridge.start(message));
                        break;
                    case "sensorStreamStop":
                        sendResult(sensorBridge.stop(message));
                        break;
                    case "continuousScanStart":
                    case "dataScanStart":
                    case "loginScanStart":
                        startContinuousScanner(message);
                        break;
                    case "continuousScanStop":
                    case "dataScanEnd":
                    case "loginScanEnd":
                        stopContinuousScanner(message);
                        break;
                    case "previewBoxLocationUpdate":
                        updateContinuousScannerPreviewRect(message);
                        break;
                    case "beaconsStart":
                        startBeacons(message);
                        break;
                    case "beaconsStop":
                        stopBeacons(message);
                        break;
                    case "printerHelloWorld":
                        printHelloWorld(message);
                        break;
                    case "printerEpsonHelloWorld":
                        printEpsonHelloWorld(message);
                        break;
                    case "printerDiscover":
                        discoverPrinters(message);
                        break;
                    default:
                        sendError(message, action, "Unknown native action: " + action);
                }
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

    private void launchConfetti(JSONObject message) throws JSONException {
        JSONObject response = baseResponse(message, "launchConfetti");
        confettiBursts += 1;
        response.put("launched", true);
        response.put("burstCount", confettiBursts);
        response.put("nativeStatus", "android_overlay");
        runOnUiThread(() -> ConfettiView.attachAndStart(this, null));
        sendResult(response);
    }

    private void sendTapToPayAvailability(JSONObject message) throws JSONException {
        JSONObject response = baseResponse(message, "tapToPayAvailability");
        response.put("available", false);
        response.put("readerType", "android");
        response.put("reason", "Android Tap to Pay bridge is not implemented in this wrapper build yet.");
        sendResult(response);
    }

    private JSONObject deviceInfo(JSONObject message) throws JSONException {
        JSONObject response = baseResponse(message, "deviceInfoGet");
        response.put("success", true);
        response.put("name", Build.DEVICE != null ? Build.DEVICE : "");
        response.put("os", "Android");
        response.put("osVersion", Build.VERSION.RELEASE != null ? Build.VERSION.RELEASE : "");
        response.put("sdkInt", Build.VERSION.SDK_INT);
        response.put("manufacturer", Build.MANUFACTURER != null ? Build.MANUFACTURER : "");
        response.put("brand", Build.BRAND != null ? Build.BRAND : "");
        response.put("device", Build.DEVICE != null ? Build.DEVICE : "");
        response.put("model", Build.MODEL != null ? Build.MODEL : "");
        response.put("product", Build.PRODUCT != null ? Build.PRODUCT : "");
        response.put("hardware", Build.HARDWARE != null ? Build.HARDWARE : "");
        response.put("serialNumber", safeSerialNumber());
        response.put("androidId", Settings.Secure.getString(getContentResolver(), Settings.Secure.ANDROID_ID));
        response.put("appVersion", appVersionName());
        response.put("battery", batteryInfo());
        response.put("screen", screenInfo());
        response.put("memory", memoryInfo());
        response.put("network", wifiStatusPayload(hasLocationPermission()));
        response.put("cameras", cameraInfo());
        response.put("sensors", sensorList());
        response.put("capabilities", deviceCapabilities());
        return response;
    }

    private JSONObject deviceCapabilities() throws JSONException {
        JSONObject capabilities = new JSONObject();
        capabilities.put("deviceInfoGet", true);
        capabilities.put("screenOrientationSet", true);
        capabilities.put("wifiConfigure", true);
        capabilities.put("screenshotGet", true);
        capabilities.put("geoLocationGet", true);
        capabilities.put("screenStreamStart", true);
        capabilities.put("screenStreamFormats", new JSONArray(Arrays.asList("jpeg")));
        capabilities.put("soundPlay", true);
        capabilities.put("idleTimerStart", true);
        capabilities.put("sensorStreamStart", true);
        return capabilities;
    }

    private JSONObject screenOrientationGet(JSONObject message) throws JSONException {
        JSONObject response = baseResponse(message, "screenOrientationGet");
        response.put("success", true);
        response.put("requestedOrientation", getRequestedOrientation());
        response.put("currentOrientation", getResources().getConfiguration().orientation);
        return response;
    }

    private JSONObject screenOrientationSet(JSONObject message) throws JSONException {
        String mode = message.optString("mode", message.optString("orientation", "unlocked")).toLowerCase(Locale.US);
        int requested;
        switch (mode) {
            case "portrait":
                requested = ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT;
                break;
            case "landscape":
                requested = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE;
                break;
            case "locked":
            case "current":
                requested = ActivityInfo.SCREEN_ORIENTATION_LOCKED;
                break;
            case "unlocked":
            case "auto":
            default:
                requested = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED;
                mode = "unlocked";
                break;
        }
        setRequestedOrientation(requested);
        JSONObject response = baseResponse(message, "screenOrientationSet");
        response.put("success", true);
        response.put("mode", mode);
        response.put("requestedOrientation", requested);
        return response;
    }

    private void sendWifiStatus(JSONObject message) throws JSONException {
        JSONObject request = copyRequest(message);
        if (!hasLocationPermission()) {
            pendingWifiStatusRequest = request;
            requestPermissions(new String[]{Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION}, REQUEST_WIFI_STATUS_PERMISSION);
            return;
        }
        sendResult(wifiStatusGet(request));
    }

    private JSONObject wifiStatusGet(JSONObject message) throws JSONException {
        JSONObject response = baseResponse(message, "wifiStatusGet");
        response.put("success", true);
        response.put("wifi", wifiStatusPayload(true));
        return response;
    }

    private void configureWifi(JSONObject message) throws JSONException {
        JSONObject request = copyRequest(message);
        String ssid = request.optString("ssid", "").trim();
        String passphrase = request.optString("passphrase", request.optString("password", "")).trim();
        if (ssid.isEmpty()) {
            sendError(request, "wifiConfigure", "ssid is required.");
            return;
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            WifiNetworkSuggestion.Builder builder = new WifiNetworkSuggestion.Builder().setSsid(ssid);
            if (!passphrase.isEmpty()) {
                builder.setWpa2Passphrase(passphrase);
            }
            ArrayList<WifiNetworkSuggestion> suggestions = new ArrayList<>();
            suggestions.add(builder.build());
            Intent intent = new Intent(Settings.ACTION_WIFI_ADD_NETWORKS);
            intent.putParcelableArrayListExtra(Settings.EXTRA_WIFI_NETWORK_LIST, suggestions);
            pendingWifiRequest = request;
            startActivityForResult(intent, REQUEST_WIFI_ADD_NETWORK);
            return;
        }

        WifiManager wifiManager = (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        if (wifiManager == null) {
            sendError(request, "wifiConfigure", "Wi-Fi service is not available.");
            return;
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            WifiNetworkSuggestion.Builder builder = new WifiNetworkSuggestion.Builder().setSsid(ssid);
            if (!passphrase.isEmpty()) {
                builder.setWpa2Passphrase(passphrase);
            }
            int status = wifiManager.addNetworkSuggestions(Arrays.asList(builder.build()));
            JSONObject response = baseResponse(request, "wifiConfigure");
            response.put("success", status == WifiManager.STATUS_NETWORK_SUGGESTIONS_SUCCESS);
            response.put("method", "WifiNetworkSuggestion");
            response.put("status", status);
            if (status != WifiManager.STATUS_NETWORK_SUGGESTIONS_SUCCESS) {
                response.put("error", "Android rejected the Wi-Fi suggestion with status " + status + ".");
            }
            sendResult(response);
            return;
        }

        WifiConfiguration configuration = new WifiConfiguration();
        configuration.SSID = quoteWifiValue(ssid);
        if (passphrase.isEmpty()) {
            configuration.allowedKeyManagement.set(WifiConfiguration.KeyMgmt.NONE);
        } else {
            configuration.preSharedKey = quoteWifiValue(passphrase);
        }
        int networkId = wifiManager.addNetwork(configuration);
        boolean enabled = networkId >= 0 && wifiManager.enableNetwork(networkId, true);
        JSONObject response = baseResponse(request, "wifiConfigure");
        response.put("success", enabled);
        response.put("method", "WifiConfiguration");
        response.put("networkId", networkId);
        if (!enabled) {
            response.put("error", "Could not add or enable the requested Wi-Fi network.");
        }
        sendResult(response);
    }

    private JSONObject screenshotGet(JSONObject message) throws JSONException {
        int maxWidth = clamp(message.optInt("maxWidth", 1080), 240, 2160);
        int quality = clamp(message.optInt("quality", 82), 25, 95);
        Bitmap bitmap = captureRootBitmap();
        Bitmap output = scaleBitmapIfNeeded(bitmap, maxWidth);
        JSONObject response = baseResponse(message, "screenshotGet");
        response.put("success", true);
        response.put("format", "jpeg");
        response.put("width", output.getWidth());
        response.put("height", output.getHeight());
        response.put("imageData", bitmapToDataUrl(output, Bitmap.CompressFormat.JPEG, quality));
        if (output != bitmap) {
            output.recycle();
        }
        bitmap.recycle();
        return response;
    }

    private void getGeoLocation(JSONObject message) throws JSONException {
        JSONObject request = copyRequest(message);
        if (!hasLocationPermission()) {
            pendingLocationRequest = request;
            pendingAction = "geoLocationGet";
            requestPermissions(new String[]{Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION}, REQUEST_LOCATION_PERMISSION);
            return;
        }
        Location location = lastKnownLocation();
        if (location == null) {
            sendError(request, "geoLocationGet", "No last known location is available yet.");
            return;
        }
        sendResult(locationPayload(request, "geoLocationGet", location));
    }

    private void startGeoLocation(JSONObject message) throws JSONException {
        JSONObject request = copyRequest(message);
        if (!hasLocationPermission()) {
            pendingLocationRequest = request;
            pendingAction = "geoLocationStart";
            requestPermissions(new String[]{Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION}, REQUEST_LOCATION_PERMISSION);
            return;
        }
        sendResult(startLocationUpdates(request));
    }

    private JSONObject stopGeoLocation(JSONObject message) throws JSONException {
        stopLocationUpdates();
        JSONObject response = baseResponse(message, "geoLocationStop");
        response.put("success", true);
        return response;
    }

    private JSONObject playSound(JSONObject message) throws JSONException {
        int frequencyHz = clamp(message.optInt("frequencyHz", 880), 80, 4000);
        int durationMs = clamp(message.optInt("durationMs", 240), 40, 5000);
        double volume = Math.max(0.0, Math.min(1.0, message.optDouble("volume", 0.85)));
        new Thread(() -> playTone(frequencyHz, durationMs, volume), "NativeSoundTone").start();
        JSONObject response = baseResponse(message, "soundPlay");
        response.put("success", true);
        response.put("frequencyHz", frequencyHz);
        response.put("durationMs", durationMs);
        response.put("volume", volume);
        return response;
    }

    private JSONObject startIdleTimer(JSONObject message) throws JSONException {
        idleTimeoutMs = Math.max(1000L, Math.round(message.optDouble("timeoutSeconds", 30.0) * 1000.0));
        idleIntervalMs = Math.max(250L, Math.round(message.optDouble("intervalSeconds", 1.0) * 1000.0));
        idleTimerRunning = true;
        idleTimedOut = false;
        recordIdleActivity();
        idleHandler.removeCallbacks(idleRunnable);
        idleHandler.postDelayed(idleRunnable, idleIntervalMs);
        JSONObject response = baseResponse(message, "idleTimerStart");
        response.put("success", true);
        response.put("timeoutSeconds", idleTimeoutMs / 1000.0);
        response.put("intervalSeconds", idleIntervalMs / 1000.0);
        return response;
    }

    private JSONObject stopIdleTimer(JSONObject message) throws JSONException {
        stopIdleTimer();
        JSONObject response = baseResponse(message, "idleTimerStop");
        response.put("success", true);
        return response;
    }

    private JSONObject resetIdleTimer(JSONObject message) throws JSONException {
        recordIdleActivity();
        JSONObject response = baseResponse(message, "idleTimerReset");
        response.put("success", true);
        return response;
    }

    private String safeSerialNumber() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                return Build.getSerial();
            }
            return Build.SERIAL != null ? Build.SERIAL : "";
        } catch (SecurityException error) {
            return "unavailable";
        }
    }

    private String appVersionName() {
        try {
            return getPackageManager().getPackageInfo(getPackageName(), 0).versionName;
        } catch (Exception ignored) {
            return "";
        }
    }

    private JSONObject batteryInfo() throws JSONException {
        Intent battery = registerReceiver(null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
        JSONObject info = new JSONObject();
        if (battery == null) {
            return info;
        }
        int level = battery.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
        int scale = battery.getIntExtra(BatteryManager.EXTRA_SCALE, -1);
        int plugged = battery.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0);
        int status = battery.getIntExtra(BatteryManager.EXTRA_STATUS, -1);
        info.put("level", level);
        info.put("scale", scale);
        info.put("percent", scale > 0 && level >= 0 ? Math.round((level * 1000f) / scale) / 10f : JSONObject.NULL);
        info.put("charging", status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL);
        info.put("plugged", plugged);
        info.put("powerSource", powerSourceName(plugged));
        return info;
    }

    private String powerSourceName(int plugged) {
        if ((plugged & BatteryManager.BATTERY_PLUGGED_AC) != 0) {
            return "ac";
        }
        if ((plugged & BatteryManager.BATTERY_PLUGGED_USB) != 0) {
            return "usb";
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR1
                && (plugged & BatteryManager.BATTERY_PLUGGED_WIRELESS) != 0) {
            return "wireless";
        }
        return "battery";
    }

    private JSONObject screenInfo() throws JSONException {
        DisplayMetrics metrics = new DisplayMetrics();
        WindowManager windowManager = (WindowManager) getSystemService(WINDOW_SERVICE);
        if (windowManager != null) {
            windowManager.getDefaultDisplay().getRealMetrics(metrics);
        } else {
            metrics = getResources().getDisplayMetrics();
        }
        JSONObject screen = new JSONObject();
        screen.put("widthPixels", metrics.widthPixels);
        screen.put("heightPixels", metrics.heightPixels);
        screen.put("density", metrics.density);
        screen.put("densityDpi", metrics.densityDpi);
        screen.put("scaledDensity", metrics.scaledDensity);
        return screen;
    }

    private JSONObject memoryInfo() throws JSONException {
        ActivityManager manager = (ActivityManager) getSystemService(ACTIVITY_SERVICE);
        ActivityManager.MemoryInfo memoryInfo = new ActivityManager.MemoryInfo();
        if (manager != null) {
            manager.getMemoryInfo(memoryInfo);
        }
        JSONObject memory = new JSONObject();
        memory.put("totalBytes", memoryInfo.totalMem);
        memory.put("availableBytes", memoryInfo.availMem);
        memory.put("lowMemory", memoryInfo.lowMemory);
        memory.put("thresholdBytes", memoryInfo.threshold);
        return memory;
    }

    private JSONObject wifiStatusPayload(boolean hasWifiDetailsPermission) throws JSONException {
        JSONObject network = new JSONObject();
        network.put("cidrs", localIPv4CIDRs());
        network.put("ipAddresses", localIPAddresses());
        network.put("ssidAvailable", false);
        network.put("ssid", "unavailable");
        network.put("securityType", "unknown");
        network.put("securityTypeRawValue", JSONObject.NULL);
        WifiManager wifiManager = (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        if (wifiManager == null) {
            network.put("wifiEnabled", false);
            network.put("wifiIpAddresses", new JSONArray());
            network.put("unavailableReason", "Wi-Fi service is not available.");
            return network;
        }

        network.put("wifiEnabled", wifiManager.isWifiEnabled());
        try {
            android.net.wifi.WifiInfo info = wifiManager.getConnectionInfo();
            network.put("wifiIpAddresses", wifiIPAddresses(info));
            if (info == null) {
                network.put("unavailableReason", "Android returned no Wi-Fi connection details.");
                return network;
            }

            String ssid = sanitizeWifiSsid(info.getSSID());
            boolean ssidAvailable = hasWifiDetailsPermission && isRealWifiSsid(ssid);
            network.put("ssidAvailable", ssidAvailable);
            network.put("ssid", ssidAvailable ? ssid : "unavailable");
            network.put("bssid", info.getBSSID() != null ? info.getBSSID() : "");
            network.put("rssi", info.getRssi());
            network.put("linkSpeedMbps", info.getLinkSpeed());
            network.put("ipAddress", ipv4FromInt(info.getIpAddress()));

            int securityTypeRawValue = wifiSecurityTypeRawValue(info);
            if (securityTypeRawValue >= 0) {
                network.put("securityTypeRawValue", securityTypeRawValue);
                network.put("securityType", wifiSecurityTypeName(securityTypeRawValue));
            }

            if (!ssidAvailable) {
                String reason = hasWifiDetailsPermission
                        ? "Android did not expose the current SSID. The device may not be connected to Wi-Fi, location services may be disabled, or the OS returned a redacted SSID."
                        : "Location permission is required before Android exposes SSID/BSSID details to apps.";
                network.put("unavailableReason", reason);
            }
        } catch (Exception error) {
            network.put("wifiIpAddresses", new JSONArray());
            network.put("unavailableReason", error.getMessage() != null ? error.getMessage() : "Wi-Fi status lookup failed.");
        }
        return network;
    }

    private JSONArray cameraInfo() throws JSONException {
        JSONArray cameras = new JSONArray();
        CameraManager cameraManager = (CameraManager) getSystemService(CAMERA_SERVICE);
        if (cameraManager == null) {
            return cameras;
        }
        try {
            for (String id : cameraManager.getCameraIdList()) {
                CameraCharacteristics characteristics = cameraManager.getCameraCharacteristics(id);
                JSONObject camera = new JSONObject();
                Integer lensFacing = characteristics.get(CameraCharacteristics.LENS_FACING);
                camera.put("id", id);
                camera.put("lensFacing", lensFacingName(lensFacing));
                cameras.put(camera);
            }
        } catch (Exception ignored) {
            // Return the cameras collected so far.
        }
        return cameras;
    }

    private JSONArray sensorList() throws JSONException {
        JSONArray sensors = new JSONArray();
        SensorManager manager = (SensorManager) getSystemService(SENSOR_SERVICE);
        if (manager == null) {
            return sensors;
        }
        for (Sensor sensor : manager.getSensorList(Sensor.TYPE_ALL)) {
            JSONObject item = new JSONObject();
            item.put("name", sensor.getName());
            item.put("vendor", sensor.getVendor());
            item.put("type", sensor.getType());
            item.put("version", sensor.getVersion());
            item.put("maximumRange", sensor.getMaximumRange());
            item.put("resolution", sensor.getResolution());
            item.put("powerMilliAmp", sensor.getPower());
            sensors.put(item);
        }
        return sensors;
    }

    private String lensFacingName(Integer lensFacing) {
        if (lensFacing == null) {
            return "unknown";
        }
        if (lensFacing == CameraCharacteristics.LENS_FACING_FRONT) {
            return "front";
        }
        if (lensFacing == CameraCharacteristics.LENS_FACING_BACK) {
            return "back";
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
                && lensFacing == CameraCharacteristics.LENS_FACING_EXTERNAL) {
            return "external";
        }
        return "unknown";
    }

    private String sanitizeWifiSsid(String ssid) {
        if (ssid == null) {
            return "";
        }
        String trimmed = ssid.trim();
        if (trimmed.startsWith("\"") && trimmed.endsWith("\"") && trimmed.length() >= 2) {
            return trimmed.substring(1, trimmed.length() - 1);
        }
        return trimmed;
    }

    private boolean isRealWifiSsid(String ssid) {
        return ssid != null
                && !ssid.trim().isEmpty()
                && !"<unknown ssid>".equalsIgnoreCase(ssid.trim());
    }

    private int wifiSecurityTypeRawValue(android.net.wifi.WifiInfo info) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                return info.getCurrentSecurityType();
            } catch (Exception ignored) {
                return -1;
            }
        }
        return -1;
    }

    private String wifiSecurityTypeName(int rawValue) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            switch (rawValue) {
                case android.net.wifi.WifiInfo.SECURITY_TYPE_OPEN:
                    return "open";
                case android.net.wifi.WifiInfo.SECURITY_TYPE_WEP:
                    return "wep";
                case android.net.wifi.WifiInfo.SECURITY_TYPE_PSK:
                case android.net.wifi.WifiInfo.SECURITY_TYPE_SAE:
                    return "personal";
                case android.net.wifi.WifiInfo.SECURITY_TYPE_EAP:
                case android.net.wifi.WifiInfo.SECURITY_TYPE_EAP_WPA3_ENTERPRISE:
                case android.net.wifi.WifiInfo.SECURITY_TYPE_EAP_WPA3_ENTERPRISE_192_BIT:
                    return "enterprise";
                default:
                    return "unknown";
            }
        }
        return "unknown";
    }

    private String ipv4FromInt(int ip) {
        return (ip & 0xff) + "." + ((ip >> 8) & 0xff) + "." + ((ip >> 16) & 0xff) + "." + ((ip >> 24) & 0xff);
    }

    private String quoteWifiValue(String value) {
        return "\"" + value.replace("\"", "\\\"") + "\"";
    }

    private Bitmap captureRootBitmap() {
        View root = getWindow().getDecorView().getRootView();
        int width = Math.max(1, root.getWidth());
        int height = Math.max(1, root.getHeight());
        Bitmap bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
        root.draw(new Canvas(bitmap));
        return bitmap;
    }

    private Bitmap scaleBitmapIfNeeded(Bitmap bitmap, int maxWidth) {
        if (bitmap.getWidth() <= maxWidth) {
            return bitmap;
        }
        int scaledHeight = Math.max(1, Math.round(bitmap.getHeight() * (maxWidth / (float) bitmap.getWidth())));
        return Bitmap.createScaledBitmap(bitmap, maxWidth, scaledHeight, true);
    }

    private boolean hasLocationPermission() {
        return checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
                || checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED;
    }

    private Location lastKnownLocation() {
        if (!hasLocationPermission()) {
            return null;
        }
        LocationManager manager = (LocationManager) getSystemService(LOCATION_SERVICE);
        if (manager == null) {
            return null;
        }
        Location best = null;
        for (String provider : manager.getProviders(true)) {
            try {
                Location location = manager.getLastKnownLocation(provider);
                if (location != null && (best == null || location.getTime() > best.getTime())) {
                    best = location;
                }
            } catch (SecurityException ignored) {
                return null;
            }
        }
        return best;
    }

    private JSONObject startLocationUpdates(JSONObject request) throws JSONException {
        stopLocationUpdates();
        locationManager = (LocationManager) getSystemService(LOCATION_SERVICE);
        if (locationManager == null) {
            return errorResponse(request, "geoLocationStart", "Location service is not available.");
        }

        long intervalMs = Math.max(1000L, request.optLong("intervalMs", 3000L));
        float minDistanceM = (float) Math.max(0.0, request.optDouble("minDistanceMeters", 0.0));
        locationListener = location -> {
            try {
                sendResult(locationPayload(request, "geoLocation", location));
            } catch (JSONException error) {
                sendErrorSafe(request, "geoLocation", error.getMessage());
            }
        };

        try {
            List<String> providers = locationManager.getProviders(true);
            for (String provider : providers) {
                locationManager.requestLocationUpdates(provider, intervalMs, minDistanceM, locationListener);
            }
        } catch (SecurityException error) {
            stopLocationUpdates();
            return errorResponse(request, "geoLocationStart", "Location permission was denied.");
        }

        JSONObject response = baseResponse(request, "geoLocationStart");
        response.put("success", true);
        response.put("intervalMs", intervalMs);
        response.put("minDistanceMeters", minDistanceM);
        Location last = lastKnownLocation();
        if (last != null) {
            response.put("lastLocation", locationObject(last));
        }
        return response;
    }

    private void stopLocationUpdates() {
        if (locationManager != null && locationListener != null) {
            try {
                locationManager.removeUpdates(locationListener);
            } catch (SecurityException ignored) {
                // Already denied or stopped.
            }
        }
        locationListener = null;
        locationManager = null;
    }

    private JSONObject locationPayload(JSONObject request, String action, Location location) throws JSONException {
        JSONObject response = baseResponse(request, action);
        response.put("success", true);
        response.put("location", locationObject(location));
        return response;
    }

    private JSONObject locationObject(Location location) throws JSONException {
        JSONObject payload = new JSONObject();
        payload.put("latitude", location.getLatitude());
        payload.put("longitude", location.getLongitude());
        payload.put("accuracyMeters", location.hasAccuracy() ? location.getAccuracy() : JSONObject.NULL);
        payload.put("altitudeMeters", location.hasAltitude() ? location.getAltitude() : JSONObject.NULL);
        payload.put("speedMetersPerSecond", location.hasSpeed() ? location.getSpeed() : JSONObject.NULL);
        payload.put("bearingDegrees", location.hasBearing() ? location.getBearing() : JSONObject.NULL);
        payload.put("provider", location.getProvider() != null ? location.getProvider() : "");
        payload.put("timestampMs", location.getTime());
        return payload;
    }

    private JSONObject errorResponse(JSONObject request, String action, String error) throws JSONException {
        JSONObject response = baseResponse(request, action);
        response.put("success", false);
        response.put("error", error);
        return response;
    }

    private void playTone(int frequencyHz, int durationMs, double volume) {
        int sampleRate = 44100;
        int sampleCount = Math.max(1, durationMs * sampleRate / 1000);
        short[] samples = new short[sampleCount];
        double amplitude = Short.MAX_VALUE * Math.max(0.0, Math.min(1.0, volume));
        for (int i = 0; i < sampleCount; i += 1) {
            double angle = 2.0 * Math.PI * i * frequencyHz / sampleRate;
            samples[i] = (short) Math.round(Math.sin(angle) * amplitude);
        }
        AudioTrack track = new AudioTrack.Builder()
                .setAudioAttributes(new AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build())
                .setAudioFormat(new AudioFormat.Builder()
                        .setSampleRate(sampleRate)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build())
                .setBufferSizeInBytes(samples.length * 2)
                .build();
        try {
            track.write(samples, 0, samples.length);
            track.play();
            Thread.sleep(durationMs + 40L);
        } catch (Exception ignored) {
            // The bridge response is immediate; playback failures are non-fatal.
        } finally {
            try {
                track.stop();
            } catch (Exception ignored) {
                // Track may already be stopped or uninitialized.
            }
            track.release();
        }
    }

    private final Runnable idleRunnable = new Runnable() {
        @Override
        public void run() {
            if (!idleTimerRunning) {
                return;
            }
            long now = System.currentTimeMillis();
            long idleMs = Math.max(0L, now - idleLastActivityMs);
            emitIdleEvent("idleTick", idleMs);
            if (!idleTimedOut && idleMs >= idleTimeoutMs) {
                idleTimedOut = true;
                emitIdleEvent("idleTimeout", idleMs);
            }
            idleHandler.postDelayed(this, idleIntervalMs);
        }
    };

    private void recordIdleActivity() {
        idleLastActivityMs = System.currentTimeMillis();
        idleTimedOut = false;
    }

    private void stopIdleTimer() {
        idleTimerRunning = false;
        idleHandler.removeCallbacks(idleRunnable);
    }

    private void emitIdleEvent(String action, long idleMs) {
        try {
            JSONObject event = new JSONObject();
            event.put("platform", "android");
            event.put("action", action);
            event.put("success", true);
            event.put("idleSeconds", idleMs / 1000.0);
            event.put("timeoutSeconds", idleTimeoutMs / 1000.0);
            sendResult(event);
        } catch (JSONException ignored) {
            // Ignore secondary JSON failure.
        }
    }

    private int clamp(int value, int min, int max) {
        return Math.max(min, Math.min(max, value));
    }

    private void startContinuousScanner(JSONObject message) throws JSONException {
        JSONObject request = copyRequest(message);
        if (!continuousScannerController.hasCameraPermission()) {
            pendingContinuousScanRequest = request;
            requestPermissions(new String[]{Manifest.permission.CAMERA}, REQUEST_CONTINUOUS_CAMERA_PERMISSION);
            return;
        }
        sendResult(continuousScannerController.start(request));
    }

    private void stopContinuousScanner(JSONObject message) throws JSONException {
        pendingContinuousScanRequest = null;
        sendResult(continuousScannerController.stop(copyRequest(message)));
    }

    private void updateContinuousScannerPreviewRect(JSONObject message) throws JSONException {
        sendResult(continuousScannerController.updatePreviewRect(copyRequest(message)));
    }

    private void sendContinuousScannerError(String message) {
        try {
            JSONObject response = new JSONObject();
            response.put("platform", "android");
            response.put("action", "continuousScanStart");
            response.put("success", false);
            response.put("error", message);
            sendResult(response);
        } catch (JSONException ignored) {
            // Ignore secondary JSON failure.
        }
    }

    private void sendContinuousScannerClosedByUser() {
        try {
            JSONObject response = new JSONObject();
            response.put("platform", "android");
            response.put("action", "continuousScanStop");
            response.put("success", true);
            response.put("closedByUser", true);
            sendResult(response);
        } catch (JSONException ignored) {
            // Ignore secondary JSON failure.
        }
    }

    private void startBeacons(JSONObject message) throws JSONException {
        JSONObject request = copyRequest(message);
        if (!beaconBridge.hasRequiredPermissions()) {
            pendingBeaconStartRequest = request;
            requestPermissions(beaconPermissions(), REQUEST_BEACON_PERMISSION);
            return;
        }
        sendResult(beaconBridge.start(request));
    }

    private void stopBeacons(JSONObject message) throws JSONException {
        pendingBeaconStartRequest = null;
        sendResult(beaconBridge.stop(copyRequest(message)));
    }

    private String[] beaconPermissions() {
        ArrayList<String> permissions = new ArrayList<>();
        permissions.add(Manifest.permission.ACCESS_FINE_LOCATION);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            permissions.add(Manifest.permission.BLUETOOTH_SCAN);
            permissions.add(Manifest.permission.BLUETOOTH_CONNECT);
        }
        return permissions.toArray(new String[0]);
    }

    private void printHelloWorld(JSONObject message) {
        JSONObject request = copyRequest(message);
        String kind = selectedPrinterKind(request);
        if ("sunmi_internal".equals(kind)) {
            printSunmiHelloWorld(request);
            return;
        }
        if ("epson_epos_xml".equals(kind)) {
            printEpsonHelloWorld(request, "printerHelloWorld");
            return;
        }
        if ("escpos_raw".equals(kind)) {
            sendErrorSafe(request, "printerHelloWorld", "Raw ESC/POS printing is not implemented in this demo build yet.");
            return;
        }
        sendErrorSafe(request, "printerHelloWorld", "Unsupported printer kind: " + kind);
    }

    private void printEpsonHelloWorld(JSONObject message) {
        printEpsonHelloWorld(message, "printerEpsonHelloWorld");
    }

    private void printEpsonHelloWorld(JSONObject message, String responseAction) {
        JSONObject request = new JSONObject();
        try {
            request = new JSONObject(message != null ? message.toString() : "{}");
        } catch (JSONException ignored) {
            // Fall back to an empty request below.
        }

        final JSONObject printRequest = request;
        new Thread(() -> {
            try {
                String host = nonEmpty(printRequest.optString("host", ""), "");
                String devid = nonEmpty(printRequest.optString("devid", "local_printer"), "local_printer");
                long timeoutMs = printRequest.optLong("timeoutMs", 20000L);
                String title = nonEmpty(printRequest.optString("title", "Hallo Welt"), "Hallo Welt");
                String subtitle = nonEmpty(printRequest.optString("subtitle", "swiftHTMLWebviewApp"), "swiftHTMLWebviewApp");
                String body = nonEmpty(printRequest.optString("body", "Android bridge test"), "Android bridge test");

                String coreJson = printercorePrintEpsonHelloWorld(host, devid, timeoutMs, title, subtitle, body);
                JSONObject coreResponse = new JSONObject(coreJson);
                JSONObject response = baseResponse(printRequest, responseAction);
                copyFields(coreResponse, response);
                response.put("host", host);
                response.put("devid", devid);
                response.put("printerKind", "epson_epos_xml");
                response.put("printerLabel", selectedPrinterLabel(printRequest, "Epson ePOS-Print"));
                response.put("goCoreVersion", printercoreCoreVersion());
                if (!coreResponse.optBoolean("success", false) && !response.has("error")) {
                    response.put("error", nonEmpty(coreResponse.optString("message", ""), "Printer returned an unsuccessful response."));
                }
                sendResult(response);
            } catch (ClassNotFoundException error) {
                sendPrintercoreUnavailable(printRequest, responseAction, "epson_epos_xml");
            } catch (Exception error) {
                sendErrorSafe(printRequest, responseAction, "Printer request failed: " + reflectionMessage(error));
            }
        }, "PrintercoreEpsonPrint").start();
    }

    private void printSunmiHelloWorld(JSONObject message) {
        JSONObject request = copyRequest(message);
        new Thread(() -> {
            try {
                SunmiPrintOutcome outcome = runSunmiPrintJob(request);
                JSONObject response = baseResponse(request, "printerHelloWorld");
                response.put("success", outcome.success);
                response.put("printerKind", "sunmi_internal");
                response.put("printerLabel", selectedPrinterLabel(request, "Sunmi interner Drucker"));
                response.put("provider", "android_aidl");
                response.put("model", Build.MODEL != null ? Build.MODEL : "");
                if (outcome.serviceVersion != null && !outcome.serviceVersion.isEmpty()) {
                    response.put("serviceVersion", outcome.serviceVersion);
                }
                if (outcome.printerModal != null && !outcome.printerModal.isEmpty()) {
                    response.put("printerModal", outcome.printerModal);
                }
                if (outcome.printerVersion != null && !outcome.printerVersion.isEmpty()) {
                    response.put("printerVersion", outcome.printerVersion);
                }
                if (!outcome.success) {
                    response.put("error", outcome.message);
                } else {
                    response.put("message", outcome.message);
                }
                sendResult(response);
            } catch (Exception error) {
                sendErrorSafe(request, "printerHelloWorld", "Sunmi printer request failed: " + error.getMessage());
            }
        }, "SunmiInternalPrint").start();
    }

    private SunmiPrintOutcome runSunmiPrintJob(JSONObject request) {
        if (!isSunmiInternalPrinterAvailable()) {
            return SunmiPrintOutcome.failure("Sunmi internal printer service is not available.");
        }

        CountDownLatch connected = new CountDownLatch(1);
        AtomicReference<IWoyouService> serviceRef = new AtomicReference<>();
        AtomicBoolean bindStarted = new AtomicBoolean(false);

        ServiceConnection connection = new ServiceConnection() {
            @Override
            public void onServiceConnected(ComponentName name, IBinder service) {
                serviceRef.set(IWoyouService.Stub.asInterface(service));
                connected.countDown();
            }

            @Override
            public void onServiceDisconnected(ComponentName name) {
                serviceRef.set(null);
            }
        };

        Intent intent = new Intent("woyou.aidlservice.jiuiv5.IWoyouService");
        intent.setPackage("woyou.aidlservice.jiuiv5");
        runOnUiThread(() -> {
            boolean bound = bindService(intent, connection, BIND_AUTO_CREATE);
            bindStarted.set(bound);
            if (!bound) {
                connected.countDown();
            }
        });

        try {
            if (!connected.await(5, TimeUnit.SECONDS)) {
                return SunmiPrintOutcome.failure("Timed out while binding Sunmi printer service.");
            }
            IWoyouService service = serviceRef.get();
            if (!bindStarted.get() || service == null) {
                return SunmiPrintOutcome.failure("Could not bind Sunmi printer service.");
            }
            return submitSunmiPrintJob(service, request);
        } catch (InterruptedException error) {
            Thread.currentThread().interrupt();
            return SunmiPrintOutcome.failure("Interrupted while binding Sunmi printer service.");
        } finally {
            if (bindStarted.get()) {
                runOnUiThread(() -> {
                    try {
                        unbindService(connection);
                    } catch (IllegalArgumentException ignored) {
                        // Already unbound.
                    }
                });
            }
        }
    }

    private SunmiPrintOutcome submitSunmiPrintJob(IWoyouService service, JSONObject request) {
        ICallback callback = new ICallback.Stub() {
            @Override
            public void onRunResult(boolean isSuccess) {
                // Result is returned through the synchronous binder submission below.
            }

            @Override
            public void onReturnString(String result) {
                // Not needed for the demo response.
            }

            @Override
            public void onRaiseException(int code, String msg) {
                // Sunmi reports detailed printer state asynchronously.
            }

            @Override
            public void onPrintResult(int code, String msg) {
                // Submission success is enough for this smoke-test bridge.
            }
        };

        try {
            String title = nonEmpty(request.optString("title", "Hallo Welt"), "Hallo Welt");
            String subtitle = nonEmpty(request.optString("subtitle", "swiftHTMLWebviewApp"), "swiftHTMLWebviewApp");
            String body = nonEmpty(request.optString("body", "Android bridge test"), "Android bridge test");
            String time = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(new Date());

            SunmiPrintOutcome outcome = SunmiPrintOutcome.success("Sunmi print job submitted.");
            outcome.serviceVersion = nonEmpty(service.getServiceVersion(), "");
            outcome.printerModal = nonEmpty(service.getPrinterModal(), "");
            outcome.printerVersion = nonEmpty(service.getPrinterVersion(), "");

            service.printerInit(callback);
            service.setAlignment(1, callback);
            service.printTextWithFont(title + "\n", null, 34f, callback);
            service.printTextWithFont(subtitle + "\n", null, 26f, callback);
            service.lineWrap(1, callback);
            service.setAlignment(0, callback);
            service.printTextWithFont(body + "\n", null, 24f, callback);
            service.printTextWithFont(time + "\n", null, 22f, callback);
            service.lineWrap(4, callback);
            return outcome;
        } catch (RemoteException error) {
            return SunmiPrintOutcome.failure("Sunmi printer failed: " + error.getMessage());
        }
    }

    private void discoverPrinters(JSONObject message) {
        JSONObject request = new JSONObject();
        try {
            request = new JSONObject(message != null ? message.toString() : "{}");
        } catch (JSONException ignored) {
            // Fall back to an empty request below.
        }

        final JSONObject discoveryRequest = request;
        new Thread(() -> {
            try {
                JSONObject response = baseResponse(discoveryRequest, "printerDiscover");
                try {
                    JSONObject discoveryOptions = buildDiscoveryOptions(discoveryRequest);
                    String coreJson = printercoreDiscoverPrinters(discoveryOptions.toString());
                    JSONObject coreResponse = new JSONObject(coreJson);
                    copyFields(coreResponse, response);
                    response.put("goCoreVersion", printercoreCoreVersion());
                } catch (ClassNotFoundException error) {
                    response.put("success", true);
                    response.put("available", false);
                    response.put("goCoreAvailable", false);
                    response.put("message", "printercore.aar is not linked in this build.");
                    response.put("printers", new JSONArray());
                }
                appendSunmiInternalPrinter(response);
                sendResult(response);
            } catch (Exception error) {
                sendErrorSafe(discoveryRequest, "printerDiscover", "Printer discovery failed: " + reflectionMessage(error));
            }
        }, "PrintercoreDiscovery").start();
    }

    private String printercoreCoreVersion() throws Exception {
        Method method = printercoreClass().getMethod("coreVersion");
        return (String) method.invoke(null);
    }

    private String printercorePrintEpsonHelloWorld(
            String host,
            String devid,
            long timeoutMs,
            String title,
            String subtitle,
            String body
    ) throws Exception {
        Method method = printercoreClass().getMethod(
                "printEpsonHelloWorld",
                String.class,
                String.class,
                long.class,
                String.class,
                String.class,
                String.class
        );
        return (String) method.invoke(null, host, devid, timeoutMs, title, subtitle, body);
    }

    private String printercoreDiscoverPrinters(String optionsJson) throws Exception {
        Method method = printercoreClass().getMethod("discoverPrinters", String.class);
        return (String) method.invoke(null, optionsJson);
    }

    private Class<?> printercoreClass() throws ClassNotFoundException {
        return Class.forName(PRINTERCORE_CLASS_NAME);
    }

    private void sendPrintercoreUnavailable(JSONObject request, String action, String printerKind) {
        try {
            JSONObject response = baseResponse(request, action);
            response.put("success", false);
            response.put("available", false);
            response.put("printerKind", printerKind);
            response.put("error", "printercore.aar is not linked in this build.");
            sendResult(response);
        } catch (JSONException error) {
            sendErrorSafe(request, action, "printercore.aar is not linked in this build.");
        }
    }

    private String reflectionMessage(Exception error) {
        Throwable cause = error instanceof InvocationTargetException && error.getCause() != null
                ? error.getCause()
                : error;
        String message = cause.getMessage();
        return message != null && !message.trim().isEmpty() ? message : cause.getClass().getSimpleName();
    }

    private JSONObject buildDiscoveryOptions(JSONObject request) throws JSONException {
        JSONObject options = new JSONObject(request != null ? request.toString() : "{}");
        if (!hasDiscoveryTargets(options)) {
            JSONArray cidrs = localIPv4CIDRs();
            if (cidrs.length() > 0) {
                options.put("cidrs", cidrs);
            }
        }
        return options;
    }

    private boolean hasDiscoveryTargets(JSONObject options) {
        return options.has("host")
                || options.has("hosts")
                || options.has("cidr")
                || options.has("cidrs");
    }

    private JSONArray localIPv4CIDRs() {
        Set<String> cidrs = new LinkedHashSet<>();
        addActiveNetworkCIDRs(cidrs);
        addJavaNetworkInterfaceCIDRs(cidrs);

        JSONArray result = new JSONArray();
        for (String cidr : cidrs) {
            result.put(cidr);
        }
        return result;
    }

    private JSONArray localIPAddresses() {
        Set<String> addresses = new LinkedHashSet<>();
        addActiveNetworkIPAddresses(addresses);
        addJavaNetworkInterfaceIPAddresses(addresses, null);

        JSONArray result = new JSONArray();
        for (String address : addresses) {
            result.put(address);
        }
        return result;
    }

    private JSONArray wifiIPAddresses(android.net.wifi.WifiInfo info) {
        Set<String> addresses = new LinkedHashSet<>();
        if (info != null && info.getIpAddress() != 0) {
            String ipv4 = ipv4FromInt(info.getIpAddress());
            if (!"0.0.0.0".equals(ipv4)) {
                addresses.add(ipv4);
            }
        }
        addJavaNetworkInterfaceIPAddresses(addresses, "wlan0");

        JSONArray result = new JSONArray();
        for (String address : addresses) {
            result.put(address);
        }
        return result;
    }

    private void addActiveNetworkCIDRs(Set<String> cidrs) {
        try {
            ConnectivityManager manager = (ConnectivityManager) getSystemService(CONNECTIVITY_SERVICE);
            Network network = manager != null ? manager.getActiveNetwork() : null;
            LinkProperties properties = network != null ? manager.getLinkProperties(network) : null;
            if (properties == null) {
                return;
            }
            for (LinkAddress address : properties.getLinkAddresses()) {
                addIPv4CIDR(cidrs, address.getAddress());
            }
        } catch (Exception ignored) {
            // Discovery still works with explicit hosts or Java network-interface fallback.
        }
    }

    private void addActiveNetworkIPAddresses(Set<String> addresses) {
        try {
            ConnectivityManager manager = (ConnectivityManager) getSystemService(CONNECTIVITY_SERVICE);
            Network network = manager != null ? manager.getActiveNetwork() : null;
            LinkProperties properties = network != null ? manager.getLinkProperties(network) : null;
            if (properties == null) {
                return;
            }
            for (LinkAddress address : properties.getLinkAddresses()) {
                addIPAddress(addresses, address.getAddress());
            }
        } catch (Exception ignored) {
            // Status still works with Java network-interface fallback.
        }
    }

    private void addJavaNetworkInterfaceCIDRs(Set<String> cidrs) {
        try {
            Enumeration<NetworkInterface> interfaces = NetworkInterface.getNetworkInterfaces();
            while (interfaces != null && interfaces.hasMoreElements()) {
                NetworkInterface networkInterface = interfaces.nextElement();
                if (!networkInterface.isUp() || networkInterface.isLoopback()) {
                    continue;
                }
                Enumeration<InetAddress> addresses = networkInterface.getInetAddresses();
                while (addresses != null && addresses.hasMoreElements()) {
                    addIPv4CIDR(cidrs, addresses.nextElement());
                }
            }
        } catch (Exception ignored) {
            // Discovery still works with explicit hosts.
        }
    }

    private void addJavaNetworkInterfaceIPAddresses(Set<String> addresses, String interfaceName) {
        try {
            Enumeration<NetworkInterface> interfaces = NetworkInterface.getNetworkInterfaces();
            while (interfaces != null && interfaces.hasMoreElements()) {
                NetworkInterface networkInterface = interfaces.nextElement();
                if (interfaceName != null && !interfaceName.equals(networkInterface.getName())) {
                    continue;
                }
                if (!networkInterface.isUp() || networkInterface.isLoopback()) {
                    continue;
                }
                Enumeration<InetAddress> interfaceAddresses = networkInterface.getInetAddresses();
                while (interfaceAddresses != null && interfaceAddresses.hasMoreElements()) {
                    addIPAddress(addresses, interfaceAddresses.nextElement());
                }
            }
        } catch (Exception ignored) {
            // IP status remains best-effort.
        }
    }

    private void addIPv4CIDR(Set<String> cidrs, InetAddress address) {
        if (!(address instanceof Inet4Address) || address.isLoopbackAddress() || address.isLinkLocalAddress()) {
            return;
        }
        byte[] bytes = address.getAddress();
        cidrs.add((bytes[0] & 0xff) + "." + (bytes[1] & 0xff) + "." + (bytes[2] & 0xff) + ".0/24");
    }

    private void addIPAddress(Set<String> addresses, InetAddress address) {
        if (address == null || address.isLoopbackAddress() || address.isLinkLocalAddress()) {
            return;
        }
        addresses.add(address.getHostAddress());
    }

    private void appendSunmiInternalPrinter(JSONObject response) throws JSONException {
        if (!isSunmiInternalPrinterAvailable()) {
            return;
        }

        JSONArray printers = response.optJSONArray("printers");
        if (printers == null) {
            printers = new JSONArray();
            response.put("printers", printers);
        }
        if (containsPrinterId(printers, "sunmi-internal")) {
            return;
        }

        JSONObject sunmiPrinter = new JSONObject();
        sunmiPrinter.put("id", "sunmi-internal");
        sunmiPrinter.put("kind", "sunmi_internal");
        sunmiPrinter.put("label", "Sunmi interner Drucker");
        sunmiPrinter.put("local", true);
        sunmiPrinter.put("confidence", "confirmed");
        sunmiPrinter.put("provider", "android_aidl");
        sunmiPrinter.put("packageName", "woyou.aidlservice.jiuiv5");
        sunmiPrinter.put("model", Build.MODEL != null ? Build.MODEL : "");
        printers.put(sunmiPrinter);
    }

    private boolean isSunmiInternalPrinterAvailable() {
        String manufacturer = Build.MANUFACTURER != null ? Build.MANUFACTURER : "";
        String brand = Build.BRAND != null ? Build.BRAND : "";
        String model = Build.MODEL != null ? Build.MODEL : "";
        boolean looksLikeSunmiDevice = containsIgnoreCase(manufacturer, "sunmi")
                || containsIgnoreCase(brand, "sunmi")
                || containsIgnoreCase(model, "sunmi")
                || containsIgnoreCase(model, "v2s");

        Intent serviceIntent = new Intent("woyou.aidlservice.jiuiv5.IWoyouService");
        serviceIntent.setPackage("woyou.aidlservice.jiuiv5");
        List<ResolveInfo> services = getPackageManager().queryIntentServices(serviceIntent, 0);
        return looksLikeSunmiDevice && services != null && !services.isEmpty();
    }

    private boolean containsIgnoreCase(String haystack, String needle) {
        return haystack != null && needle != null && haystack.toLowerCase().contains(needle.toLowerCase());
    }

    private boolean containsPrinterId(JSONArray printers, String printerId) {
        for (int i = 0; i < printers.length(); i += 1) {
            JSONObject printer = printers.optJSONObject(i);
            if (printer != null && printerId.equals(printer.optString("id", ""))) {
                return true;
            }
        }
        return false;
    }

    private JSONObject copyRequest(JSONObject message) {
        try {
            return new JSONObject(message != null ? message.toString() : "{}");
        } catch (JSONException ignored) {
            return new JSONObject();
        }
    }

    private String selectedPrinterKind(JSONObject request) {
        String kind = nonEmpty(request.optString("kind", ""), "");
        if (!kind.isEmpty()) {
            return kind;
        }
        JSONObject printer = request.optJSONObject("printer");
        if (printer != null) {
            kind = nonEmpty(printer.optString("kind", ""), "");
            if (!kind.isEmpty()) {
                return kind;
            }
        }
        return "epson_epos_xml";
    }

    private String selectedPrinterLabel(JSONObject request, String fallback) {
        JSONObject printer = request.optJSONObject("printer");
        if (printer != null) {
            String label = nonEmpty(printer.optString("label", ""), "");
            if (!label.isEmpty()) {
                return label;
            }
        }
        return fallback;
    }

    private static final class SunmiPrintOutcome {
        final boolean success;
        final String message;
        String serviceVersion = "";
        String printerModal = "";
        String printerVersion = "";

        private SunmiPrintOutcome(boolean success, String message) {
            this.success = success;
            this.message = message;
        }

        static SunmiPrintOutcome success(String message) {
            return new SunmiPrintOutcome(true, message);
        }

        static SunmiPrintOutcome failure(String message) {
            return new SunmiPrintOutcome(false, message);
        }
    }

    private void startPhotoCapture(JSONObject message) throws JSONException {
        pendingRequest = message;
        pendingAction = "takePhoto";
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.CAMERA}, REQUEST_CAMERA_PERMISSION);
            return;
        }
        launchCameraIntent();
    }

    private void launchCameraIntent() throws JSONException {
        Intent intent = new Intent(MediaStore.ACTION_IMAGE_CAPTURE);
        if ("front".equalsIgnoreCase(pendingRequest != null ? pendingRequest.optString("camera") : null)) {
            intent.putExtra("android.intent.extras.CAMERA_FACING", 1);
            intent.putExtra("android.intent.extra.USE_FRONT_CAMERA", true);
        }
        if (intent.resolveActivity(getPackageManager()) == null) {
            sendError(pendingRequest, pendingAction, "No Android camera app is available.");
            clearPendingAction();
            return;
        }
        startActivityForResult(intent, REQUEST_IMAGE_CAPTURE);
    }

    private void startBarcodeScanner(JSONObject message) throws JSONException {
        pendingRequest = message;
        pendingAction = "scanBarcode";
        GmsBarcodeScannerOptions options = new GmsBarcodeScannerOptions.Builder()
                .setBarcodeFormats(
                        Barcode.FORMAT_QR_CODE,
                        Barcode.FORMAT_EAN_13,
                        Barcode.FORMAT_EAN_8,
                        Barcode.FORMAT_CODE_128,
                        Barcode.FORMAT_DATA_MATRIX,
                        Barcode.FORMAT_AZTEC,
                        Barcode.FORMAT_PDF417,
                        Barcode.FORMAT_UPC_A,
                        Barcode.FORMAT_UPC_E
                )
                .enableAutoZoom()
                .build();
        GmsBarcodeScanner scanner = GmsBarcodeScanning.getClient(this, options);
        scanner.startScan()
                .addOnSuccessListener(this::sendBarcodeResult)
                .addOnCanceledListener(() -> {
                    sendErrorSafe(pendingRequest, "scanBarcode", "Barcode scan was cancelled.");
                    clearPendingAction();
                })
                .addOnFailureListener(error -> {
                    sendErrorSafe(pendingRequest, "scanBarcode", "Barcode scan failed: " + error.getMessage());
                    clearPendingAction();
                });
    }

    private void startDocumentScanner(JSONObject message) throws JSONException {
        pendingRequest = message;
        pendingAction = "scanDocument";
        String outputType = message.optString("outputType", "png").toLowerCase();
        GmsDocumentScannerOptions.Builder builder = new GmsDocumentScannerOptions.Builder()
                .setGalleryImportAllowed(true)
                .setPageLimit(10)
                .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL);
        if ("pdf".equals(outputType)) {
            builder.setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_PDF);
        } else {
            builder.setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG);
        }
        GmsDocumentScanner scanner = GmsDocumentScanning.getClient(builder.build());
        scanner.getStartScanIntent(this)
                .addOnSuccessListener(intentSender -> {
                    try {
                        startIntentSenderForResult(intentSender, REQUEST_DOCUMENT_SCAN, null, 0, 0, 0);
                    } catch (IntentSender.SendIntentException error) {
                        sendErrorSafe(pendingRequest, "scanDocument", "Document scanner could not start: " + error.getMessage());
                        clearPendingAction();
                    }
                })
                .addOnFailureListener(error -> {
                    sendErrorSafe(pendingRequest, "scanDocument", "Document scanner failed to start: " + error.getMessage());
                    clearPendingAction();
                });
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQUEST_CAMERA_PERMISSION) {
            if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                try {
                    launchCameraIntent();
                } catch (JSONException error) {
                    sendErrorSafe(pendingRequest, pendingAction, error.getMessage());
                    clearPendingAction();
                }
            } else {
                sendErrorSafe(pendingRequest, pendingAction, "Camera permission was denied.");
                clearPendingAction();
            }
            return;
        }
        if (requestCode == REQUEST_CONTINUOUS_CAMERA_PERMISSION) {
            if (allPermissionsGranted(grantResults) && pendingContinuousScanRequest != null) {
                try {
                    sendResult(continuousScannerController.start(pendingContinuousScanRequest));
                } catch (JSONException error) {
                    sendContinuousScannerError(error.getMessage());
                } finally {
                    pendingContinuousScanRequest = null;
                }
            } else {
                sendContinuousScannerError("Camera permission was denied.");
                pendingContinuousScanRequest = null;
            }
            return;
        }
        if (requestCode == REQUEST_BEACON_PERMISSION) {
            if (allPermissionsGranted(grantResults) && pendingBeaconStartRequest != null) {
                try {
                    sendResult(beaconBridge.start(pendingBeaconStartRequest));
                } catch (JSONException error) {
                    sendErrorSafe(pendingBeaconStartRequest, "beaconsStart", error.getMessage());
                } finally {
                    pendingBeaconStartRequest = null;
                }
            } else {
                sendErrorSafe(pendingBeaconStartRequest, "beaconsStart", "Location and Bluetooth permissions are required for iBeacon ranging.");
                pendingBeaconStartRequest = null;
            }
            return;
        }
        if (requestCode == REQUEST_LOCATION_PERMISSION) {
            JSONObject request = pendingLocationRequest;
            String action = pendingAction != null ? pendingAction : "geoLocationGet";
            pendingLocationRequest = null;
            pendingAction = null;
            if (allPermissionsGranted(grantResults) && request != null) {
                try {
                    if ("geoLocationStart".equals(action)) {
                        sendResult(startLocationUpdates(request));
                    } else {
                        Location location = lastKnownLocation();
                        if (location != null) {
                            sendResult(locationPayload(request, "geoLocationGet", location));
                        } else {
                            sendErrorSafe(request, "geoLocationGet", "No last known location is available yet.");
                        }
                    }
                } catch (JSONException error) {
                    sendErrorSafe(request, action, error.getMessage());
                }
            } else {
                sendErrorSafe(request, action, "Location permission was denied.");
            }
            return;
        }
        if (requestCode == REQUEST_WIFI_STATUS_PERMISSION) {
            JSONObject request = pendingWifiStatusRequest;
            pendingWifiStatusRequest = null;
            if (hasLocationPermission() && request != null) {
                try {
                    sendResult(wifiStatusGet(request));
                } catch (JSONException error) {
                    sendErrorSafe(request, "wifiStatusGet", error.getMessage());
                }
            } else if (request != null) {
                try {
                    JSONObject response = baseResponse(request, "wifiStatusGet");
                    response.put("success", true);
                    response.put("wifi", wifiStatusPayload(false));
                    sendResult(response);
                } catch (JSONException error) {
                    sendErrorSafe(request, "wifiStatusGet", error.getMessage());
                }
            }
        }
    }

    private boolean allPermissionsGranted(int[] grantResults) {
        if (grantResults.length == 0) {
            return false;
        }
        for (int result : grantResults) {
            if (result != PackageManager.PERMISSION_GRANTED) {
                return false;
            }
        }
        return true;
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQUEST_IMAGE_CAPTURE) {
            handlePhotoCaptureResult(resultCode, data);
            return;
        }
        if (requestCode == REQUEST_DOCUMENT_SCAN) {
            handleDocumentScanResult(resultCode, data);
            return;
        }
        if (requestCode == REQUEST_WIFI_ADD_NETWORK) {
            handleWifiAddNetworkResult(resultCode);
        }
    }

    private void handleWifiAddNetworkResult(int resultCode) {
        JSONObject request = pendingWifiRequest != null ? pendingWifiRequest : new JSONObject();
        pendingWifiRequest = null;
        try {
            JSONObject response = baseResponse(request, "wifiConfigure");
            response.put("success", resultCode == RESULT_OK);
            response.put("method", "ACTION_WIFI_ADD_NETWORKS");
            response.put("userApproved", resultCode == RESULT_OK);
            if (resultCode != RESULT_OK) {
                response.put("error", "The Wi-Fi add-network request was cancelled or denied.");
            }
            sendResult(response);
        } catch (JSONException ignored) {
            // Ignore secondary JSON failure.
        }
    }

    private void handlePhotoCaptureResult(int resultCode, Intent data) {
        if (pendingRequest == null || pendingAction == null) {
            return;
        }
        if (resultCode != RESULT_OK) {
            sendErrorSafe(pendingRequest, pendingAction, "Camera action was cancelled.");
            clearPendingAction();
            return;
        }
        Bitmap bitmap = extractBitmap(data);
        if (bitmap == null) {
            sendErrorSafe(pendingRequest, pendingAction, "Camera did not return image data.");
            clearPendingAction();
            return;
        }
        if (pendingRequest.optBoolean("removeBackground", false)) {
            processPhotoBackgroundRemoval(bitmap);
            return;
        }

        try {
            sendPhotoResult(bitmap, false);
        } catch (JSONException error) {
            sendErrorSafe(pendingRequest, pendingAction, error.getMessage());
        } finally {
            clearPendingAction();
        }
    }

    private void handleDocumentScanResult(int resultCode, Intent data) {
        if (pendingRequest == null) {
            return;
        }
        if (resultCode != RESULT_OK) {
            sendErrorSafe(pendingRequest, "scanDocument", "Document scan was cancelled.");
            clearPendingAction();
            return;
        }
        try {
            GmsDocumentScanningResult result = GmsDocumentScanningResult.fromActivityResultIntent(data);
            JSONObject response = baseResponse(pendingRequest, "scanDocument");
            response.put("ocr", false);
            String outputType = pendingRequest.optString("outputType", "png").toLowerCase();
            if ("pdf".equals(outputType) && result != null && result.getPdf() != null) {
                response.put("format", "pdf");
                response.put("pages", result.getPdf().getPageCount());
                response.put("pdfData", uriToDataUrl(result.getPdf().getUri(), "application/pdf"));
            } else {
                JSONArray images = new JSONArray();
                List<GmsDocumentScanningResult.Page> pages = result != null ? result.getPages() : null;
                if (pages != null) {
                    for (GmsDocumentScanningResult.Page page : pages) {
                        images.put(uriToDataUrl(page.getImageUri(), "image/jpeg"));
                    }
                }
                response.put("format", "jpeg");
                response.put("pages", images.length());
                response.put("images", images);
            }
            sendResult(response);
        } catch (Exception error) {
            sendErrorSafe(pendingRequest, "scanDocument", "Document scan result failed: " + error.getMessage());
        } finally {
            clearPendingAction();
        }
    }

    private Bitmap extractBitmap(Intent data) {
        if (data == null) {
            return null;
        }
        Object extra = data.getExtras() != null ? data.getExtras().get("data") : null;
        if (extra instanceof Bitmap) {
            return (Bitmap) extra;
        }
        Uri uri = data.getData();
        if (uri != null) {
            try {
                return BitmapFactory.decodeStream(getContentResolver().openInputStream(uri));
            } catch (Exception ignored) {
                return null;
            }
        }
        return null;
    }

    private void processPhotoBackgroundRemoval(Bitmap bitmap) {
        SelfieSegmenterOptions options = new SelfieSegmenterOptions.Builder()
                .setDetectorMode(SelfieSegmenterOptions.SINGLE_IMAGE_MODE)
                .build();
        Segmenter segmenter = Segmentation.getClient(options);
        InputImage image = InputImage.fromBitmap(bitmap, 0);
        segmenter.process(image)
                .addOnSuccessListener(mask -> {
                    try {
                        Bitmap composited = applySegmentationMask(bitmap, mask);
                        sendPhotoResult(composited, true);
                    } catch (Exception error) {
                        sendErrorSafe(pendingRequest, "takePhoto", "Background removal failed: " + error.getMessage());
                    } finally {
                        segmenter.close();
                        clearPendingAction();
                    }
                })
                .addOnFailureListener(error -> {
                    segmenter.close();
                    sendErrorSafe(pendingRequest, "takePhoto", "Background removal failed: " + error.getMessage());
                    clearPendingAction();
                });
    }

    private Bitmap applySegmentationMask(Bitmap source, SegmentationMask mask) {
        int width = source.getWidth();
        int height = source.getHeight();
        int maskWidth = mask.getWidth();
        int maskHeight = mask.getHeight();
        ByteBuffer buffer = mask.getBuffer();
        buffer.rewind();

        boolean transparentBackground = !"color".equalsIgnoreCase(pendingRequest.optString("background", "transparent"));
        int backgroundColor = parseBackgroundColor(pendingRequest.optString("backgroundColor", "#FFFFFF"));
        Bitmap output = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);

        int minX = width;
        int minY = height;
        int maxX = -1;
        int maxY = -1;

        for (int y = 0; y < height; y++) {
            int maskY = Math.min(maskHeight - 1, Math.max(0, Math.round((y / (float) Math.max(1, height - 1)) * (maskHeight - 1))));
            for (int x = 0; x < width; x++) {
                int maskX = Math.min(maskWidth - 1, Math.max(0, Math.round((x / (float) Math.max(1, width - 1)) * (maskWidth - 1))));
                float confidence = getMaskConfidence(buffer, maskWidth, maskX, maskY);
                int sourceColor = source.getPixel(x, y);
                int alpha = confidenceToAlpha(confidence);
                int pixel;
                if (transparentBackground) {
                    pixel = Color.argb(alpha, Color.red(sourceColor), Color.green(sourceColor), Color.blue(sourceColor));
                } else {
                    pixel = blendOverBackground(sourceColor, backgroundColor, alpha / 255f);
                }
                output.setPixel(x, y, pixel);
                if (alpha > 24) {
                    minX = Math.min(minX, x);
                    minY = Math.min(minY, y);
                    maxX = Math.max(maxX, x);
                    maxY = Math.max(maxY, y);
                }
            }
        }

        if (pendingRequest.optBoolean("cropTransparent", false) && maxX >= minX && maxY >= minY) {
            int padding = Math.max(8, Math.round(Math.max(width, height) * 0.03f));
            int left = Math.max(0, minX - padding);
            int top = Math.max(0, minY - padding);
            int right = Math.min(width, maxX + padding);
            int bottom = Math.min(height, maxY + padding);
            return Bitmap.createBitmap(output, left, top, Math.max(1, right - left), Math.max(1, bottom - top));
        }
        return output;
    }

    private float getMaskConfidence(ByteBuffer buffer, int maskWidth, int x, int y) {
        int index = (y * maskWidth + x) * 4;
        if (index < 0 || index + 4 > buffer.capacity()) {
            return 0f;
        }
        return buffer.getFloat(index);
    }

    private int confidenceToAlpha(float confidence) {
        float softened = Math.max(0f, Math.min(1f, (confidence - 0.18f) / 0.72f));
        return Math.max(0, Math.min(255, Math.round(softened * 255f)));
    }

    private int parseBackgroundColor(String raw) {
        try {
            String value = raw == null || raw.trim().isEmpty() ? "#FFFFFF" : raw.trim();
            if (!value.startsWith("#")) {
                value = "#" + value;
            }
            return Color.parseColor(value);
        } catch (Exception ignored) {
            return Color.WHITE;
        }
    }

    private int blendOverBackground(int foreground, int background, float alpha) {
        float inverse = 1f - alpha;
        int red = Math.round(Color.red(foreground) * alpha + Color.red(background) * inverse);
        int green = Math.round(Color.green(foreground) * alpha + Color.green(background) * inverse);
        int blue = Math.round(Color.blue(foreground) * alpha + Color.blue(background) * inverse);
        return Color.argb(255, red, green, blue);
    }

    private void sendPhotoResult(Bitmap bitmap, boolean backgroundRemoved) throws JSONException {
        String requestedFormat = pendingRequest.optString("outputType", "jpeg");
        boolean wantsPng = backgroundRemoved || "png".equalsIgnoreCase(requestedFormat);
        JSONObject response = baseResponse(pendingRequest, "takePhoto");
        response.put("format", wantsPng ? "png" : "jpeg");
        response.put("imageData", bitmapToDataUrl(bitmap, wantsPng ? Bitmap.CompressFormat.PNG : Bitmap.CompressFormat.JPEG, wantsPng ? 100 : 88));
        response.put("backgroundRemoved", backgroundRemoved);
        if (backgroundRemoved) {
            response.put("background", pendingRequest.optString("background", "transparent"));
            response.put("backgroundColor", pendingRequest.optString("backgroundColor", "#FFFFFF"));
            response.put("cropped", pendingRequest.optBoolean("cropTransparent", false));
        }
        response.put("camera", pendingRequest.optString("camera", "back"));
        sendResult(response);
    }

    private void sendBarcodeResult(Barcode barcode) {
        try {
            JSONObject response = baseResponse(pendingRequest, "scanBarcode");
            response.put("code", barcode.getRawValue() != null ? barcode.getRawValue() : "");
            response.put("format", barcodeFormatName(barcode.getFormat()));
            sendResult(response);
        } catch (JSONException error) {
            sendErrorSafe(pendingRequest, "scanBarcode", error.getMessage());
        } finally {
            clearPendingAction();
        }
    }

    private String barcodeFormatName(int format) {
        switch (format) {
            case Barcode.FORMAT_QR_CODE: return "qr";
            case Barcode.FORMAT_EAN_13: return "ean13";
            case Barcode.FORMAT_EAN_8: return "ean8";
            case Barcode.FORMAT_CODE_128: return "code128";
            case Barcode.FORMAT_DATA_MATRIX: return "datamatrix";
            case Barcode.FORMAT_PDF417: return "pdf417";
            case Barcode.FORMAT_AZTEC: return "aztec";
            case Barcode.FORMAT_UPC_A: return "upca";
            case Barcode.FORMAT_UPC_E: return "upce";
            default: return "unknown";
        }
    }

    private String bitmapToDataUrl(Bitmap bitmap, Bitmap.CompressFormat format, int quality) {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        bitmap.compress(format, quality, output);
        String mime = format == Bitmap.CompressFormat.PNG ? "image/png" : "image/jpeg";
        return "data:" + mime + ";base64," + Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP);
    }

    private String uriToDataUrl(Uri uri, String mimeType) throws Exception {
        try (InputStream input = getContentResolver().openInputStream(uri);
             ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            if (input == null) {
                throw new IllegalStateException("Could not open scanner output.");
            }
            byte[] buffer = new byte[8192];
            int read;
            while ((read = input.read(buffer)) != -1) {
                output.write(buffer, 0, read);
            }
            return "data:" + mimeType + ";base64," + Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP);
        }
    }

    private void clearPendingAction() {
        pendingRequest = null;
        pendingAction = null;
    }

    private void sendErrorSafe(JSONObject source, String action, String error) {
        try {
            sendError(source, action, error);
        } catch (JSONException ignored) {
            // Ignore secondary JSON failure.
        }
    }

    private void sendError(JSONObject source, String action, String error) throws JSONException {
        JSONObject response = baseResponse(source != null ? source : new JSONObject(), action != null ? action : "unknown");
        response.put("error", error != null ? error : "Unknown error");
        sendResult(response);
    }

    private void copyFields(JSONObject source, JSONObject target) throws JSONException {
        JSONArray names = source.names();
        if (names == null) {
            return;
        }
        for (int i = 0; i < names.length(); i += 1) {
            String key = names.getString(i);
            target.put(key, source.get(key));
        }
    }

    private String nonEmpty(String value, String fallback) {
        if (value == null) {
            return fallback;
        }
        String trimmed = value.trim();
        return trimmed.isEmpty() ? fallback : trimmed;
    }

    private JSONObject baseResponse(JSONObject message, String action) throws JSONException {
        JSONObject response = new JSONObject();
        response.put("platform", "android");
        response.put("action", action);
        if (message != null && message.has("requestId")) {
            response.put("requestId", message.optString("requestId"));
        }
        if (message != null && message.has("paymentId")) {
            response.put("paymentId", message.optString("paymentId"));
        }
        return response;
    }
}
