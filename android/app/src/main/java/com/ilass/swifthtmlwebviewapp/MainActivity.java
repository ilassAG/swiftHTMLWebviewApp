package com.ilass.swifthtmlwebviewapp;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.ActivityManager;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentSender;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.content.ServiceConnection;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
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
import android.os.Looper;
import android.provider.MediaStore;
import android.provider.Settings;
import android.util.Base64;
import android.util.DisplayMetrics;
import android.view.View;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.ImageButton;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

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
import java.nio.ByteBuffer;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Enumeration;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

public class MainActivity extends ComponentActivity implements ConfettiView.ActivityHost, TapToPayBridgeHost, AndroidSettingsBridge.Host, AndroidPrinterBridge.Host, AndroidScreenOrientationBridge.Host, AndroidIdleTimerBridge.Host {
    private static final String DEFAULT_URL = "file:///android_asset/index.html";
    private static final int REQUEST_CAMERA_PERMISSION = 2001;
    private static final int REQUEST_IMAGE_CAPTURE = 2002;
    private static final int REQUEST_DOCUMENT_SCAN = 2003;
    private static final int REQUEST_CONTINUOUS_CAMERA_PERMISSION = 2004;
    private static final int REQUEST_BEACON_PERMISSION = 2005;
    private static final int REQUEST_LOCATION_PERMISSION = 2006;
    private static final int REQUEST_WIFI_ADD_NETWORK = 2007;
    private static final int REQUEST_WIFI_STATUS_PERMISSION = 2008;
    private static final int REQUEST_CONFIG_PAIRING_PERMISSION = 2009;
    private static final int REQUEST_BEACON_ADVERTISE_PERMISSION = 2010;
    private static final int REQUEST_NOTIFICATION_PERMISSION = 2011;
    private static final int REQUEST_TAP_TO_PAY_LOCATION_PERMISSION = 2012;
    private static final int REQUEST_PORTRAIT_CAMERA_PERMISSION = 2013;
    private static final String META_DEFAULT_SERVER_URL = "com.ilass.DEFAULT_SERVER_URL";
    private static final String META_DEFAULT_SECURITY_TOKEN = "com.ilass.DEFAULT_SECURITY_TOKEN";
    private static final String META_DEFAULT_BEACON_UUID = "com.ilass.DEFAULT_BEACON_UUID";
    private static final String META_RECOVERY_SHORT_MARK = "com.ilass.RECOVERY_SHORT_MARK";
    private static final String META_RECOVERY_TITLE = "com.ilass.RECOVERY_TITLE";
    private static final String META_RECOVERY_BODY = "com.ilass.RECOVERY_BODY";
    private static final String META_RECOVERY_SUCCESS_MESSAGE = "com.ilass.RECOVERY_SUCCESS_MESSAGE";
    private static final String META_RECOVERY_INVALID_QR_MESSAGE = "com.ilass.RECOVERY_INVALID_QR_MESSAGE";
    private static final String DEFAULT_LOCAL_SERVER_URL = "local";
    private static final String DEFAULT_SECURITY_TOKEN = "";
    private static final String DEFAULT_BEACON_UUID = AndroidBeaconBridge.DEFAULT_BEACON_UUID;
    private static final String DEFAULT_RECOVERY_SHORT_MARK = "SW";
    private static final String DEFAULT_RECOVERY_TITLE = "Server nicht erreichbar";
    private static final String DEFAULT_RECOVERY_BODY = "Die gespeicherte Server-Adresse kann in diesem Netzwerk nicht geladen werden. Scanne den aktuellen Konfigurations-QR-Code oder pruefe WLAN und Server.";
    private static final String DEFAULT_RECOVERY_SUCCESS_MESSAGE = "Neue Server-Adresse gespeichert. Verbindung wird geprueft...";
    private static final String DEFAULT_RECOVERY_INVALID_QR_MESSAGE = "QR-Code erkannt, aber keine Server-Adresse gefunden.";

    private WebView webView;
    private JSONObject pendingRequest;
    private String pendingAction;
    private JSONObject pendingContinuousScanRequest;
    private JSONObject pendingBeaconStartRequest;
    private JSONObject pendingBeaconAdvertiseStartRequest;
    private JSONObject pendingLocationRequest;
    private JSONObject pendingWifiRequest;
    private JSONObject pendingWifiStatusRequest;
    private JSONObject pendingConfigPairingRequest;
    private JSONObject pendingNotificationPermissionRequest;
    private JSONObject pendingPortraitCaptureRequest;
    private String pendingConfigPairingAction;
    private AndroidConfigPairingBridge.ResultCallback pendingWifiConfigCallback;
    private ContinuousBarcodeScannerController continuousScannerController;
    private AndroidPortraitCaptureController portraitCaptureController;
    private AndroidBeaconBridge beaconBridge;
    private AndroidBeaconAdvertiserBridge beaconAdvertiserBridge;
    private AndroidScreenStreamBridge screenStreamBridge;
    private AndroidSensorBridge sensorBridge;
    private AndroidConfigPairingBridge configPairingBridge;
    private AndroidNfcTagReaderBridge nfcTagReaderBridge;
    private AndroidNotificationBridge notificationBridge;
    private AndroidSettingsBridge settingsBridge;
    private AndroidTapToPayBridge tapToPayBridge;
    private AndroidBridgeRouter bridgeRouter;
    private AndroidPrinterBridge printerBridge;
    private AndroidScreenOrientationBridge screenOrientationBridge;
    private AndroidIdleTimerBridge idleTimerBridge;
    private AndroidNativeStorageBridge nativeStorageBridge;
    private AndroidNativeFilesystemBridge nativeFilesystemBridge;
    private AndroidNativeSQLiteBridge nativeSQLiteBridge;
    private AndroidNatsBridge natsBridge;
    private final Handler idleHandler = new Handler(Looper.getMainLooper());
    private final Handler loadHandler = new Handler(Looper.getMainLooper());
    private final AndroidStartupLoadCoordinator startupLoadCoordinator = new AndroidStartupLoadCoordinator(this::isLocalConfiguredUrl);
    private LocationManager locationManager;
    private LocationListener locationListener;
    private int confettiBursts = 0;
    private View configPairingOverlay;
    private View tapToPayTransitionOverlay;
    private View kioskReloadControlView;
    private Runnable kioskRestartRunnable;
    private boolean kioskRestartTriggered = false;
    private TextView configPairingStateText;
    private long configPairingHoldStartMs = 0L;
    private boolean configPairingHoldTriggered = false;
    private String configPairingOverlayPayload;
    private Bitmap configPairingOverlayQrBitmap;
    private boolean configPairingOverlayAdvertising;
    private final ArrayList<JSONObject> queuedNotificationEvents = new ArrayList<>();
    private JSONObject pendingTapToPayRequest;
    private Runnable loadTimeoutRunnable;
    private boolean webBridgeReady = false;
    private final Runnable natsTelemetryRunnable = new Runnable() {
        @Override
        public void run() {
            publishNatsTelemetry("interval");
            scheduleNatsTelemetry();
        }
    };

    @SuppressLint({"SetJavaScriptEnabled", "AddJavascriptInterface"})
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        settingsStore().appUUID();
        settingsStore().deviceUUID();

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
                cancelLoadTimeout();
                injectBridgeShim();
                injectIdleActivityShim();
                webBridgeReady = true;
                flushQueuedNotificationEvents();
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                if (request != null && request.isForMainFrame()) {
                    String reason = error != null && error.getDescription() != null
                            ? error.getDescription().toString()
                            : "WebView load failed.";
                    applyStartupLoadCommand(startupLoadCoordinator.mainFrameFailed(reason));
                }
            }
        });
        webView.setOnTouchListener((view, event) -> {
            idleTimerBridge.recordActivity();
            handleConfigPairingGesture(event);
            return false;
        });
        continuousScannerController = new ContinuousBarcodeScannerController(this, new ContinuousBarcodeScannerController.Listener() {
            @Override
            public void onScannerEvent(JSONObject event) {
                handleContinuousScannerEvent(event);
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
        portraitCaptureController = new AndroidPortraitCaptureController(this, new AndroidPortraitCaptureController.Listener() {
            @Override
            public void onPortraitResult(JSONObject payload) {
                sendResult(payload);
            }

            @Override
            public void onPortraitError(JSONObject request, String action, String message) {
                sendErrorSafe(request, action, message);
            }
        });
        beaconBridge = new AndroidBeaconBridge(this, this::sendResult);
        beaconAdvertiserBridge = new AndroidBeaconAdvertiserBridge(this, this::sendResult);
        screenStreamBridge = new AndroidScreenStreamBridge(this, this::sendResult);
        sensorBridge = new AndroidSensorBridge(this, this::sendResult);
        notificationBridge = new AndroidNotificationBridge(this);
        settingsBridge = new AndroidSettingsBridge(this);
        natsBridge = new AndroidNatsBridge(
                new AndroidNatsBridge.Host() {
                    @Override
                    public String securityToken() {
                        return configSecurityToken();
                    }

                    @Override
                    public String appUUID() {
                        return configAppUUID();
                    }

                    @Override
                    public AndroidNatsSettings natsSettings() {
                        return settingsStore().natsSettings();
                    }

                    @Override
                    public void persistNatsSettings(AndroidNatsSettings settings) throws JSONException {
                        settingsStore().persistNatsSettings(settings);
                    }

                    @Override
                    public JSONObject executeNatsCommand(JSONObject command) throws JSONException {
                        return MainActivity.this.executeNatsCommand(command);
                    }
                },
                new AndroidNatsEncryptedCredentialStore(this),
                new AndroidNatsClientConnectionDriver()
        );
        printerBridge = new AndroidPrinterBridge(this);
        screenOrientationBridge = new AndroidScreenOrientationBridge(this);
        idleTimerBridge = new AndroidIdleTimerBridge(this);
        nativeStorageBridge = new AndroidNativeStorageBridge(this);
        nativeFilesystemBridge = new AndroidNativeFilesystemBridge(this);
        nativeSQLiteBridge = new AndroidNativeSQLiteBridge(this);
        nfcTagReaderBridge = new AndroidNfcTagReaderBridge(new AndroidNfcTagReaderBridge.Host() {
            @Override
            public Activity activity() {
                return MainActivity.this;
            }

            @Override
            public Context context() {
                return MainActivity.this;
            }

            @Override
            public void sendResult(JSONObject payload) {
                MainActivity.this.sendResult(payload);
            }
        });
        tapToPayBridge = createTapToPayBridge();
        configPairingBridge = new AndroidConfigPairingBridge(new AndroidConfigPairingBridge.Host() {
            @Override
            public Context context() {
                return MainActivity.this;
            }

            @Override
            public void sendResult(JSONObject payload) {
                MainActivity.this.sendResult(payload);
            }

            @Override
            public JSONObject settingsSnapshot() throws JSONException {
                return configSettingsSnapshot();
            }

            @Override
            public JSONObject applySettings(JSONObject values) throws JSONException {
                return applyConfigSettings(values);
            }

            @Override
            public boolean hasValidSecurityToken(String token) {
                String storedToken = configSecurityToken();
                String incomingToken = token != null ? token.trim() : "";
                return !storedToken.isEmpty() && !incomingToken.isEmpty() && storedToken.equals(incomingToken);
            }

            @Override
            public void configureWifi(JSONObject request, AndroidConfigPairingBridge.ResultCallback callback) {
                try {
                    MainActivity.this.configureWifi(request, callback);
                } catch (JSONException error) {
                    try {
                        callback.complete(AndroidWifiBridge.configureErrorResponse(request, error.getMessage()));
                    } catch (JSONException ignored) {
                        // Ignore secondary JSON failure.
                    }
                }
            }

            @Override
            public void reloadConfiguredUrl() {
                reloadConfiguredUrlFromSettings();
            }

            @Override
            public JSONObject deviceSummary() throws JSONException {
                return configDeviceSummary();
            }

            @Override
            public void showPairingOverlay(String payload, Bitmap qrBitmap, boolean advertising) {
                showConfigPairingOverlay(payload, qrBitmap, advertising);
            }

            @Override
            public void setPairingOverlayAdvertising(boolean advertising) {
                setConfigPairingOverlayAdvertising(advertising);
            }

            @Override
            public void hidePairingOverlay() {
                hideConfigPairingOverlay();
            }
        });
        bridgeRouter = createBridgeRouter();
        webView.addJavascriptInterface(new NativeBridge(), "AndroidNativeBridge");
        String startUrl = getIntent() != null && getIntent().getDataString() != null
                ? getIntent().getDataString()
                : null;
        if (startUrl != null) {
            webView.loadUrl(startUrl);
        } else {
            loadConfiguredUrlFromSettings();
        }
        handleNotificationIntent(getIntent());
        startNatsRuntime("appStart");
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        String nextUrl = intent != null ? intent.getDataString() : null;
        if (nextUrl != null && !nextUrl.trim().isEmpty() && webView != null) {
            webView.loadUrl(nextUrl.trim());
        }
        handleNotificationIntent(intent);
    }

    @Override
    protected void onResume() {
        super.onResume();
        startNatsRuntime("activityResume");
    }

    @Override
    public void onConfigurationChanged(android.content.res.Configuration newConfig) {
        super.onConfigurationChanged(newConfig);
        if (configPairingOverlay != null && configPairingOverlayPayload != null && configPairingOverlayQrBitmap != null) {
            showConfigPairingOverlay(configPairingOverlayPayload, configPairingOverlayQrBitmap, configPairingOverlayAdvertising);
        }
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
        if (portraitCaptureController != null) {
            portraitCaptureController.shutdown();
        }
        if (beaconBridge != null) {
            beaconBridge.shutdown();
        }
        if (beaconAdvertiserBridge != null) {
            beaconAdvertiserBridge.shutdown();
        }
        if (screenStreamBridge != null) {
            screenStreamBridge.shutdown();
        }
        if (sensorBridge != null) {
            sensorBridge.shutdown();
        }
        if (configPairingBridge != null) {
            configPairingBridge.shutdown();
        }
        if (nfcTagReaderBridge != null) {
            nfcTagReaderBridge.shutdown();
        }
        loadHandler.removeCallbacks(natsTelemetryRunnable);
        if (natsBridge != null) {
            try {
                natsBridge.disconnect(new JSONObject());
            } catch (JSONException ignored) {
                // Ignore shutdown response failures.
            }
        }
        stopLocationUpdates();
        idleTimerBridge.stop();
        cancelLoadTimeout();
        super.onDestroy();
    }

    @Override
    public android.content.Context context() {
        return this;
    }

    @Override
    public Context applicationContext() {
        return getApplicationContext();
    }

    @Override
    public boolean hasSystemFeature(String featureName) {
        return getPackageManager().hasSystemFeature(featureName);
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

    @Override
    public JSONArray localPrinterDiscoveryCIDRs() {
        return localIPv4CIDRs();
    }

    @Override
    public void runOnMainThread(Runnable runnable) {
        runOnUiThread(runnable);
    }

    @Override
    public boolean bindPrinterService(Intent intent, ServiceConnection connection) {
        return bindService(intent, connection, BIND_AUTO_CREATE);
    }

    @Override
    public void unbindPrinterService(ServiceConnection connection) {
        try {
            unbindService(connection);
        } catch (IllegalArgumentException ignored) {
            // Already unbound.
        }
    }

    @Override
    public List<ResolveInfo> queryIntentServices(Intent intent) {
        return getPackageManager().queryIntentServices(intent, 0);
    }

    @Override
    public String deviceManufacturer() {
        return Build.MANUFACTURER != null ? Build.MANUFACTURER : "";
    }

    @Override
    public String deviceBrand() {
        return Build.BRAND != null ? Build.BRAND : "";
    }

    @Override
    public String deviceModel() {
        return Build.MODEL != null ? Build.MODEL : "";
    }

    @Override
    public int requestedOrientation() {
        return getRequestedOrientation();
    }

    @Override
    public int currentOrientation() {
        return getResources().getConfiguration().orientation;
    }

    @Override
    public void applyRequestedOrientation(int requestedOrientation) {
        setRequestedOrientation(requestedOrientation);
    }

    @Override
    public long currentTimeMillis() {
        return System.currentTimeMillis();
    }

    @Override
    public void scheduleIdleCheck(Runnable runnable, long delayMs) {
        idleHandler.postDelayed(runnable, delayMs);
    }

    @Override
    public void cancelIdleCheck(Runnable runnable) {
        idleHandler.removeCallbacks(runnable);
    }

    private AndroidTapToPayBridge createTapToPayBridge() {
        try {
            Class<?> bridgeClass = Class.forName("com.ilass.swifthtmlwebviewapp.StripeTapToPayBridge");
            Object instance = bridgeClass.getDeclaredConstructor(TapToPayBridgeHost.class).newInstance(this);
            if (instance instanceof AndroidTapToPayBridge) {
                return (AndroidTapToPayBridge) instance;
            }
        } catch (ReflectiveOperationException ignored) {
            // Optional bridge is only packaged by app variants that include it.
        }
        return null;
    }

    private AndroidBridgeRouter createBridgeRouter() {
        AndroidBridgeRouter router = new AndroidBridgeRouter.Builder(this::sendResult)
                .on("launchConfetti", this::launchConfetti)
                .on("takePhoto", this::startPhotoCapture)
                .on("portraitCapture", this::startPortraitCapture)
                .on("scanBarcode", this::startBarcodeScanner)
                .on("scanDocument", this::startDocumentScanner)
                .on("nfcTagRead", nfcTagReaderBridge::startRead)
                .on("tapToPayAvailability", this::sendTapToPayAvailability)
                .on("tapToPayCollect", this::startTapToPayCollect)
                .on("deviceInfoGet", message -> sendResult(deviceInfo(message)))
                .on("screenOrientationGet", message -> sendResult(screenOrientationBridge.get(message)))
                .on("screenOrientationSet", message -> sendResult(screenOrientationBridge.set(message)))
                .on("wifiStatusGet", this::sendWifiStatus)
                .on("wifiConfigure", this::configureWifi)
                .on("screenshotGet", message -> sendResult(screenshotGet(message)))
                .on("geoLocationGet", this::getGeoLocation)
                .on("geoLocationStart", this::startGeoLocation)
                .on("geoLocationStop", message -> sendResult(stopGeoLocation(message)))
                .on("soundPlay", message -> sendResult(playSound(message)))
                .on("notificationPermissionGet", message -> sendResult(notificationBridge.permissionStatus(message)))
                .on("notificationPermissionRequest", this::requestNotificationPermission)
                .on("notificationShow", message -> sendResult(notificationBridge.show(message)))
                .on("notificationSchedule", message -> sendResult(notificationBridge.schedule(message)))
                .on("notificationCancel", message -> sendResult(notificationBridge.cancel(message)))
                .on("notificationCancelAll", message -> sendResult(notificationBridge.cancelAll(message)))
                .on("notificationList", message -> sendResult(notificationBridge.list(message)))
                .on("idleTimerStart", message -> sendResult(idleTimerBridge.start(message)))
                .on("idleTimerStop", message -> sendResult(idleTimerBridge.stop(message)))
                .on("idleTimerReset", message -> sendResult(idleTimerBridge.reset(message)))
                .on("idleActivity", message -> idleTimerBridge.recordActivity())
                .on("screenStreamStart", message -> sendResult(screenStreamBridge.start(message)))
                .on("screenStreamStop", message -> sendResult(screenStreamBridge.stop(message)))
                .on("natsProvision", message -> {
                    JSONObject response = natsBridge.provision(message);
                    sendResult(response);
                    if (response.optBoolean("success", false)) {
                        startNatsRuntime("provisioned");
                    }
                })
                .on("natsStatus", message -> sendResult(natsBridge.status(message)))
                .on("natsConnect", message -> sendResult(natsBridge.connect(message)))
                .on("natsDisconnect", message -> sendResult(natsBridge.disconnect(message)))
                .on("natsPublish", message -> sendResult(natsBridge.publish(message)))
                .on("sensorCapabilitiesGet", message -> sendResult(sensorBridge.capabilities(message)))
                .on("sensorStreamStart", message -> sendResult(sensorBridge.start(message)))
                .on("sensorStreamStop", message -> sendResult(sensorBridge.stop(message)))
                .onAll(this::sendARPositionUnavailable, AndroidBridgeActionCatalog.AR_POSITION_ACTIONS)
                .onAll(this::sendRoomPlanUnavailable, AndroidBridgeActionCatalog.ROOM_PLAN_ACTIONS)
                .onAll(this::sendARGuidedUnavailable, AndroidBridgeActionCatalog.AR_GUIDED_MEASUREMENT_ACTIONS)
                .onAll(this::sendAROverlayUnavailable, AndroidBridgeActionCatalog.AR_OVERLAY_ACTIONS)
                .onAll(this::handleConfigPairingAction, AndroidBridgeActionCatalog.CONFIG_PAIRING_ACTIONS)
                .on("settingsGet", message -> sendResult(settingsGet(message)))
                .on("settingsSet", message -> sendResult(settingsSet(message)))
                .on("storageGet", message -> sendResult(nativeStorageBridge.get(message)))
                .on("storageSet", message -> sendResult(nativeStorageBridge.set(message)))
                .on("storageRemove", message -> sendResult(nativeStorageBridge.remove(message)))
                .on("storageClear", message -> sendResult(nativeStorageBridge.clear(message)))
                .on("filesystemWrite", message -> sendResult(nativeFilesystemBridge.write(message)))
                .on("filesystemRead", message -> sendResult(nativeFilesystemBridge.read(message)))
                .on("filesystemList", message -> sendResult(nativeFilesystemBridge.list(message)))
                .on("filesystemDelete", message -> sendResult(nativeFilesystemBridge.delete(message)))
                .on("sqliteExecute", message -> sendResult(nativeSQLiteBridge.execute(message)))
                .on("sqliteDeleteDatabase", message -> sendResult(nativeSQLiteBridge.deleteDatabase(message)))
                .on("kioskReloadControlSet", message -> sendResult(kioskReloadControlSet(message)))
                .on("reload", message -> sendResult(reload(message)))
                .onAll(this::startContinuousScanner, AndroidBridgeActionCatalog.CONTINUOUS_SCANNER_START_ACTIONS)
                .onAll(this::stopContinuousScanner, AndroidBridgeActionCatalog.CONTINUOUS_SCANNER_STOP_ACTIONS)
                .on("previewBoxLocationUpdate", this::updateContinuousScannerPreviewRect)
                .on("beaconsStart", this::startBeacons)
                .on("beaconsStop", this::stopBeacons)
                .on("beaconAdvertiseStart", this::startBeaconAdvertise)
                .on("beaconAdvertiseStop", this::stopBeaconAdvertise)
                .on("printerHelloWorld", printerBridge::printHelloWorld)
                .on("printerPrint", printerBridge::printGeneric)
                .on("printerEpsonHelloWorld", printerBridge::printEpsonHelloWorld)
                .on("printerDiscover", printerBridge::discoverPrinters)
                .build();
        AndroidBridgeActionCatalog.assertRegisteredActions(router.actions());
        return router;
    }

    public void showTapToPayTransition() {
        runOnUiThread(() -> {
            if (tapToPayTransitionOverlay != null) {
                return;
            }
            FrameLayout overlay = new FrameLayout(this);
            overlay.setBackgroundColor(Color.rgb(2, 6, 12));
            overlay.setClickable(true);
            overlay.setAlpha(0f);

            TextView label = new TextView(this);
            label.setText("Tap to Pay wird gestartet...");
            label.setTextColor(Color.WHITE);
            label.setTextSize(24f);
            label.setGravity(Gravity.CENTER);
            label.setTypeface(label.getTypeface(), Typeface.BOLD);
            int pad = Math.round(28 * getResources().getDisplayMetrics().density);
            label.setPadding(pad, pad, pad, pad);
            overlay.addView(label, new FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    Gravity.CENTER
            ));
            tapToPayTransitionOverlay = overlay;
            addContentView(overlay, new ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
            ));
            overlay.animate().alpha(1f).setDuration(180).start();
        });
    }

    public void hideTapToPayTransition() {
        runOnUiThread(() -> {
            View overlay = tapToPayTransitionOverlay;
            if (overlay == null) {
                return;
            }
            tapToPayTransitionOverlay = null;
            overlay.animate().alpha(0f).setDuration(160).withEndAction(() -> {
                ViewGroup parent = (ViewGroup) overlay.getParent();
                if (parent != null) {
                    parent.removeView(overlay);
                }
            }).start();
        });
    }

    private void injectBridgeShim() {
        webView.evaluateJavascript(AndroidBridgeShimBuilder.bridgeShimScript(), null);
    }

    private void injectIdleActivityShim() {
        webView.evaluateJavascript(AndroidBridgeShimBuilder.idleActivityShimScript(), null);
    }

    public void sendResult(JSONObject payload) {
        String script = AndroidBridgeScriptBuilder.nativeResultScript(payload);
        runOnUiThread(() -> webView.evaluateJavascript(script, null));
    }

    private void handleNotificationIntent(Intent intent) {
        if (intent == null || !intent.getBooleanExtra(AndroidNotificationBridge.EXTRA_TAPPED, false)) {
            return;
        }
        try {
            JSONObject event = notificationBridge.openedEvent(intent);
            if (webBridgeReady) {
                sendResult(event);
            } else {
                queuedNotificationEvents.add(event);
            }
        } catch (JSONException error) {
            sendErrorSafe(null, "notificationOpened", error.getMessage());
        }
    }

    private void flushQueuedNotificationEvents() {
        if (queuedNotificationEvents.isEmpty()) {
            return;
        }
        ArrayList<JSONObject> events = new ArrayList<>(queuedNotificationEvents);
        queuedNotificationEvents.clear();
        for (JSONObject event : events) {
            sendResult(event);
        }
    }

    public class NativeBridge {
        @JavascriptInterface
        public void postMessage(String rawMessage) {
            bridgeRouter.postMessage(rawMessage);
        }
    }

    private void startNatsRuntime(String reason) {
        connectNatsIfConfigured(reason);
        scheduleNatsTelemetry();
        publishNatsTelemetry(reason);
    }

    private void connectNatsIfConfigured(String reason) {
        if (natsBridge != null && !natsBridge.isConnected()) {
            new Thread(() -> natsBridge.connectIfConfigured(reason), "NATS-AutoConnect").start();
        }
    }

    private void scheduleNatsTelemetry() {
        loadHandler.removeCallbacks(natsTelemetryRunnable);
        if (natsBridge == null) {
            return;
        }
        AndroidNatsSettings settings = settingsStore().natsSettings();
        if (!settings.telemetryEnabled) {
            return;
        }
        long intervalMs = Math.max(5000L, settings.telemetryIntervalSeconds * 1000L);
        loadHandler.postDelayed(natsTelemetryRunnable, intervalMs);
    }

    private void publishNatsTelemetry(String reason) {
        if (natsBridge == null) {
            return;
        }
        JSONObject payload;
        try {
            payload = natsTelemetryPayload(reason);
        } catch (JSONException error) {
            // Telemetry is best-effort and must not affect the WebView.
            return;
        }
        new Thread(() -> {
            natsBridge.connectIfConfigured("telemetry-" + (reason != null ? reason : ""));
            if (natsBridge.isConnected()) {
                natsBridge.publishTelemetry(payload);
            }
        }, "NATS-Telemetry").start();
    }

    private JSONObject natsTelemetryPayload(String reason) throws JSONException {
        JSONObject device = deviceInfo(new JSONObject()
                .put("action", "deviceInfoGet")
                .put("source", "natsTelemetry"));
        return new JSONObject()
                .put("type", "natsTelemetry")
                .put("action", "natsTelemetry")
                .put("platform", "android")
                .put("timestamp", java.time.Instant.now().toString())
                .put("reason", reason != null ? reason : "")
                .put("appUUID", configAppUUID())
                .put("deviceName", configDeviceName())
                .put("deviceUUID", configDeviceUUID())
                .put("deviceLocation", configDeviceLocation())
                .put("activityState", "resumed")
                .put("idle", idleTimerBridge.telemetrySnapshot())
                .put("screenStream", screenStreamBridge.telemetrySnapshot())
                .put("nats", natsBridge.statusSnapshot())
                .put("device", device);
    }

    private void launchConfetti(JSONObject message) throws JSONException {
        confettiBursts += 1;
        JSONObject response = AndroidNativeCommandPayload.launchConfettiResponse(
                message,
                confettiBursts,
                "android_overlay"
        );
        runOnUiThread(() -> ConfettiView.attachAndStart(this, null));
        sendResult(response);
    }

    private void sendTapToPayAvailability(JSONObject message) throws JSONException {
        if (tapToPayBridge == null) {
            sendResult(AndroidTapToPayPayload.availabilityUnavailable(message));
            return;
        }
        tapToPayBridge.sendAvailability(message);
    }

    private void startTapToPayCollect(JSONObject message) throws JSONException {
        if (tapToPayBridge == null) {
            sendResult(AndroidTapToPayPayload.collectUnavailable(message));
            return;
        }
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            pendingTapToPayRequest = copyRequest(message);
            requestPermissions(AndroidPermissionPolicy.tapToPayLocationPermissions(), REQUEST_TAP_TO_PAY_LOCATION_PERMISSION);
            return;
        }
        tapToPayBridge.collect(message);
    }

    private void sendRoomPlanUnavailable(JSONObject message) throws JSONException {
        sendResult(AndroidUnavailableBridge.roomPlan(message));
    }

    private void sendARPositionUnavailable(JSONObject message) throws JSONException {
        sendResult(AndroidUnavailableBridge.arPosition(message));
    }

    private void sendARGuidedUnavailable(JSONObject message) throws JSONException {
        sendResult(AndroidUnavailableBridge.arGuided(message));
    }

    private void sendAROverlayUnavailable(JSONObject message) throws JSONException {
        sendResult(AndroidUnavailableBridge.arOverlay(message));
    }

    private void startPortraitCapture(JSONObject message) {
        JSONObject request = copyRequest(message);
        if (portraitCaptureController == null) {
            sendErrorSafe(request, "portraitCapture", "Android portrait capture controller is not available.");
            return;
        }
        if (!portraitCaptureController.hasCameraPermission()) {
            pendingPortraitCaptureRequest = request;
            requestPermissions(AndroidPermissionPolicy.cameraPermissions(), REQUEST_PORTRAIT_CAMERA_PERMISSION);
            return;
        }
        portraitCaptureController.start(request);
    }

    private JSONObject deviceInfo(JSONObject message) throws JSONException {
        AndroidDeviceInfoPayload.Snapshot snapshot = new AndroidDeviceInfoPayload.Snapshot();
        snapshot.name = stringOrEmpty(Build.DEVICE);
        snapshot.appUUID = configAppUUID();
        snapshot.configuredDeviceName = configDeviceName();
        snapshot.configuredDeviceUUID = configDeviceUUID();
        snapshot.configuredDeviceLocation = configDeviceLocation();
        snapshot.osVersion = stringOrEmpty(Build.VERSION.RELEASE);
        snapshot.sdkInt = Build.VERSION.SDK_INT;
        snapshot.manufacturer = stringOrEmpty(Build.MANUFACTURER);
        snapshot.brand = stringOrEmpty(Build.BRAND);
        snapshot.device = stringOrEmpty(Build.DEVICE);
        snapshot.model = stringOrEmpty(Build.MODEL);
        snapshot.product = stringOrEmpty(Build.PRODUCT);
        snapshot.hardware = stringOrEmpty(Build.HARDWARE);
        snapshot.serialNumber = safeSerialNumber();
        snapshot.androidId = Settings.Secure.getString(getContentResolver(), Settings.Secure.ANDROID_ID);
        snapshot.appVersion = appVersionName();
        snapshot.battery = batteryInfo();
        snapshot.screen = screenInfo();
        snapshot.memory = memoryInfo();
        snapshot.network = wifiStatusPayload(hasLocationPermission());
        snapshot.cameras = cameraInfo();
        snapshot.sensors = sensorList();
        snapshot.capabilities = deviceCapabilities();
        if (natsBridge != null) {
            snapshot.nats = natsBridge.statusSnapshot();
        }
        return AndroidDeviceInfoPayload.response(message, snapshot);
    }

    private JSONObject deviceCapabilities() throws JSONException {
        boolean beaconAdvertiseSupported = AndroidBeaconAdvertiserBridge.isSupported(this);
        return AndroidDeviceCapabilities.build(
                AndroidNfcTagReaderBridge.isAvailable(this),
                AndroidNfcTagReaderBridge.isEnabled(this),
                tapToPayBridge != null,
                beaconAdvertiseSupported
        );
    }

    private void requestNotificationPermission(JSONObject message) throws JSONException {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU
                || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            sendResult(notificationBridge.permissionRequestResult(message, true));
            return;
        }
        pendingNotificationPermissionRequest = copyRequest(message);
        requestPermissions(AndroidPermissionPolicy.notificationPermissions(Build.VERSION.SDK_INT), REQUEST_NOTIFICATION_PERMISSION);
    }

    private void sendWifiStatus(JSONObject message) throws JSONException {
        JSONObject request = copyRequest(message);
        if (!hasLocationPermission()) {
            pendingWifiStatusRequest = request;
            requestPermissions(AndroidPermissionPolicy.locationPermissions(), REQUEST_WIFI_STATUS_PERMISSION);
            return;
        }
        sendResult(wifiStatusGet(request));
    }

    private JSONObject wifiStatusGet(JSONObject message) throws JSONException {
        return AndroidWifiBridge.statusResponse(message, wifiStatusPayload(true));
    }

    private void configureWifi(JSONObject message) throws JSONException {
        configureWifi(message, this::sendResult);
    }

    private void configureWifi(JSONObject message, AndroidConfigPairingBridge.ResultCallback callback) throws JSONException {
        JSONObject originalRequest = copyRequest(message);
        String persistedServerUrl = persistServerUrlFromRequest(originalRequest);
        AndroidWifiBridge.ConfigureRequest wifiRequest = AndroidWifiBridge.configureRequest(originalRequest, persistedServerUrl);
        JSONObject request = wifiRequest.request;
        if (wifiRequest.ssid.isEmpty()) {
            callback.complete(AndroidWifiBridge.missingSSIDResponse(request));
            return;
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            WifiNetworkSuggestion.Builder builder = new WifiNetworkSuggestion.Builder().setSsid(wifiRequest.ssid);
            if (!wifiRequest.passphrase.isEmpty()) {
                builder.setWpa2Passphrase(wifiRequest.passphrase);
            }
            ArrayList<WifiNetworkSuggestion> suggestions = new ArrayList<>();
            suggestions.add(builder.build());
            Intent intent = new Intent(Settings.ACTION_WIFI_ADD_NETWORKS);
            intent.putParcelableArrayListExtra(Settings.EXTRA_WIFI_NETWORK_LIST, suggestions);
            pendingWifiRequest = request;
            pendingWifiConfigCallback = callback;
            startActivityForResult(intent, REQUEST_WIFI_ADD_NETWORK);
            return;
        }

        WifiManager wifiManager = (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        if (wifiManager == null) {
            callback.complete(AndroidWifiBridge.serviceUnavailableResponse(request));
            return;
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            WifiNetworkSuggestion.Builder builder = new WifiNetworkSuggestion.Builder().setSsid(wifiRequest.ssid);
            if (!wifiRequest.passphrase.isEmpty()) {
                builder.setWpa2Passphrase(wifiRequest.passphrase);
            }
            int status = wifiManager.addNetworkSuggestions(Arrays.asList(builder.build()));
            callback.complete(AndroidWifiBridge.networkSuggestionResponse(
                    request,
                    status,
                    status == WifiManager.STATUS_NETWORK_SUGGESTIONS_SUCCESS
            ));
            return;
        }

        WifiConfiguration configuration = new WifiConfiguration();
        configuration.SSID = AndroidWifiBridge.quoteWifiValue(wifiRequest.ssid);
        if (wifiRequest.passphrase.isEmpty()) {
            configuration.allowedKeyManagement.set(WifiConfiguration.KeyMgmt.NONE);
        } else {
            configuration.preSharedKey = AndroidWifiBridge.quoteWifiValue(wifiRequest.passphrase);
        }
        int networkId = wifiManager.addNetwork(configuration);
        boolean enabled = networkId >= 0 && wifiManager.enableNetwork(networkId, true);
        callback.complete(AndroidWifiBridge.legacyConfigurationResponse(request, networkId, enabled));
    }

    private String persistServerUrlFromRequest(JSONObject request) throws JSONException {
        String serverUrl = AndroidRecoveryConfigParser.serverUrlFromPayload(request);
        if (serverUrl.isEmpty()) {
            return "";
        }

        JSONObject settings = new JSONObject();
        settings.put("serverURL", serverUrl);
        return applyConfigSettings(settings).optString("serverURL", serverUrl);
    }

    private JSONObject screenshotGet(JSONObject message) throws JSONException {
        AndroidScreenshotPayload.Request request = AndroidScreenshotPayload.request(message);
        Bitmap bitmap = captureRootBitmap();
        Bitmap output = scaleBitmapIfNeeded(bitmap, request.maxWidth);
        JSONObject response = AndroidScreenshotPayload.response(
                message,
                output.getWidth(),
                output.getHeight(),
                bitmapToDataUrl(output, Bitmap.CompressFormat.JPEG, request.quality)
        );
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
            requestPermissions(AndroidPermissionPolicy.locationPermissions(), REQUEST_LOCATION_PERMISSION);
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
            requestPermissions(AndroidPermissionPolicy.locationPermissions(), REQUEST_LOCATION_PERMISSION);
            return;
        }
        sendResult(startLocationUpdates(request));
    }

    private JSONObject stopGeoLocation(JSONObject message) throws JSONException {
        stopLocationUpdates();
        return AndroidLocationPayload.stopResponse(message);
    }

    private JSONObject playSound(JSONObject message) throws JSONException {
        AndroidSoundPayload.Request sound = AndroidSoundPayload.request(message);
        new Thread(() -> playTone(sound.frequencyHz, sound.durationMs, sound.volume), "NativeSoundTone").start();
        return AndroidSoundPayload.response(message, sound);
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

    private String stringOrEmpty(String value) {
        return value != null ? value : "";
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
        if (battery == null) {
            return new JSONObject();
        }
        int level = battery.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
        int scale = battery.getIntExtra(BatteryManager.EXTRA_SCALE, -1);
        int plugged = battery.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0);
        int status = battery.getIntExtra(BatteryManager.EXTRA_STATUS, -1);
        return AndroidDeviceInfoPayload.battery(level, scale, plugged, status);
    }

    private JSONObject screenInfo() throws JSONException {
        DisplayMetrics metrics = new DisplayMetrics();
        WindowManager windowManager = (WindowManager) getSystemService(WINDOW_SERVICE);
        if (windowManager != null) {
            windowManager.getDefaultDisplay().getRealMetrics(metrics);
        } else {
            metrics = getResources().getDisplayMetrics();
        }
        return AndroidDeviceInfoPayload.screen(
                metrics.widthPixels,
                metrics.heightPixels,
                metrics.density,
                metrics.densityDpi,
                metrics.scaledDensity
        );
    }

    private JSONObject memoryInfo() throws JSONException {
        ActivityManager manager = (ActivityManager) getSystemService(ACTIVITY_SERVICE);
        ActivityManager.MemoryInfo memoryInfo = new ActivityManager.MemoryInfo();
        if (manager != null) {
            manager.getMemoryInfo(memoryInfo);
        }
        return AndroidDeviceInfoPayload.memory(
                memoryInfo.totalMem,
                memoryInfo.availMem,
                memoryInfo.lowMemory,
                memoryInfo.threshold
        );
    }

    private JSONObject wifiStatusPayload(boolean hasWifiDetailsPermission) throws JSONException {
        AndroidWifiBridge.StatusSnapshot snapshot = new AndroidWifiBridge.StatusSnapshot();
        snapshot.cidrs = localIPv4CIDRs();
        snapshot.ipAddresses = localIPAddresses();
        snapshot.hasWifiDetailsPermission = hasWifiDetailsPermission;
        WifiManager wifiManager = (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        if (wifiManager == null) {
            snapshot.wifiServiceAvailable = false;
            return AndroidWifiBridge.statusPayload(snapshot);
        }

        snapshot.wifiEnabled = wifiManager.isWifiEnabled();
        try {
            android.net.wifi.WifiInfo info = wifiManager.getConnectionInfo();
            snapshot.wifiIpAddresses = wifiIPAddresses(info);
            if (info == null) {
                snapshot.connectionInfoAvailable = false;
                return AndroidWifiBridge.statusPayload(snapshot);
            }

            snapshot.connectionInfoAvailable = true;
            snapshot.ssid = info.getSSID();
            snapshot.bssid = info.getBSSID();
            snapshot.rssi = info.getRssi();
            snapshot.linkSpeedMbps = info.getLinkSpeed();
            snapshot.ipAddress = ipv4FromInt(info.getIpAddress());
            snapshot.securityTypeRawValue = wifiSecurityTypeRawValue(info);
            snapshot.securityType = wifiSecurityTypeName(snapshot.securityTypeRawValue);
        } catch (Exception error) {
            snapshot.connectionInfoAvailable = false;
            snapshot.wifiIpAddresses = new JSONArray();
            snapshot.unavailableReason = error.getMessage() != null ? error.getMessage() : "Wi-Fi status lookup failed.";
        }
        return AndroidWifiBridge.statusPayload(snapshot);
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
                Integer lensFacing = characteristics.get(CameraCharacteristics.LENS_FACING);
                cameras.put(AndroidDeviceInfoPayload.camera(id, lensFacing));
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
            sensors.put(AndroidDeviceInfoPayload.sensor(
                    sensor.getName(),
                    sensor.getVendor(),
                    sensor.getType(),
                    sensor.getVersion(),
                    sensor.getMaximumRange(),
                    sensor.getResolution(),
                    sensor.getPower()
            ));
        }
        return sensors;
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
            return AndroidLocationPayload.errorResponse(request, "geoLocationStart", "Location service is not available.");
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
            return AndroidLocationPayload.errorResponse(request, "geoLocationStart", "Location permission was denied.");
        }

        Location last = lastKnownLocation();
        return AndroidLocationPayload.startResponse(
                request,
                intervalMs,
                minDistanceM,
                last != null ? locationObject(last) : null
        );
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
        return AndroidLocationPayload.response(request, action, locationObject(location));
    }

    private JSONObject locationObject(Location location) throws JSONException {
        return AndroidLocationPayload.locationObject(
                location.getLatitude(),
                location.getLongitude(),
                location.hasAccuracy() ? location.getAccuracy() : null,
                location.hasAltitude() ? location.getAltitude() : null,
                location.hasSpeed() ? location.getSpeed() : null,
                location.hasBearing() ? location.getBearing() : null,
                location.getProvider(),
                location.getTime()
        );
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

    private int clamp(int value, int min, int max) {
        return Math.max(min, Math.min(max, value));
    }

    private void startContinuousScanner(JSONObject message) throws JSONException {
        JSONObject request = copyRequest(message);
        if (!continuousScannerController.hasCameraPermission()) {
            pendingContinuousScanRequest = request;
            requestPermissions(AndroidPermissionPolicy.cameraPermissions(), REQUEST_CONTINUOUS_CAMERA_PERMISSION);
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

    private void handleContinuousScannerEvent(JSONObject event) {
        if (!"configPairing".equals(event.optString("purpose", "")) && !"configPairing".equals(event.optString("mode", ""))) {
            sendResult(event);
            return;
        }

        JSONObject request = continuousConfigPairingRequest(event);
        String code = event.optString("code", "").trim();
        try {
            AndroidBarcodeConfigHandler.Result configResult = AndroidBarcodeConfigHandler.evaluate(
                    code,
                    true,
                    configSecurityToken()
            );
            if (configResult.kind == AndroidBarcodeConfigHandler.Kind.CONFIG_CHANGE) {
                hideConfigPairingOverlay();
                sendResult(AndroidBarcodeResponseBuilder.configChanged(request, applyConfigSettings(configResult.settings)));
                if (configResult.hasWifiRequest()) {
                    configureWifi(configResult.wifiRequest, result -> {
                        sendResult(result);
                        reloadConfiguredUrlFromSettings();
                    });
                } else {
                    reloadConfiguredUrlFromSettings();
                }
                return;
            }
            if (configResult.kind == AndroidBarcodeConfigHandler.Kind.RECOVERY_SERVER_URL) {
                hideConfigPairingOverlay();
                JSONObject settings = applyConfigSettings(configResult.settings);
                sendResult(AndroidBarcodeResponseBuilder.configChanged(request, settings));
                loadHandler.postDelayed(this::reloadConfiguredUrlFromSettings, 350L);
                return;
            }
            sendResult(AndroidContinuousScannerConfig.errorResponse(request, request.optString("action", "continuousScanStart"), recoveryInvalidQRMessage()));
        } catch (JSONException error) {
            try {
                sendResult(AndroidContinuousScannerConfig.errorResponse(request, request.optString("action", "continuousScanStart"), error.getMessage()));
            } catch (JSONException ignored) {
                // Ignore secondary JSON failure.
            }
        }
    }

    private JSONObject continuousConfigPairingRequest(JSONObject event) {
        JSONObject request = new JSONObject();
        try {
            request.put("action", event.optString("sourceAction", "continuousScanStart"));
            request.put("purpose", "configPairing");
            request.put("source", "configPairing");
        } catch (JSONException ignored) {
            // Object is locally constructed with simple strings.
        }
        return request;
    }

    private void stopContinuousScannerAfterConfig() {
        try {
            continuousScannerController.stop(new JSONObject().put("action", "continuousScanStop"));
        } catch (JSONException ignored) {
            // Overlay cleanup is best-effort after a successful config scan.
        }
    }

    private void sendContinuousScannerError(String message) {
        try {
            sendResult(AndroidContinuousScannerConfig.errorResponse(null, "continuousScanStart", message));
        } catch (JSONException ignored) {
            // Ignore secondary JSON failure.
        }
    }

    private void sendContinuousScannerClosedByUser() {
        try {
            sendResult(AndroidContinuousScannerConfig.closedByUserResponse(null));
        } catch (JSONException ignored) {
            // Ignore secondary JSON failure.
        }
    }

    private void startBeacons(JSONObject message) throws JSONException {
        JSONObject request = copyRequest(message);
        if (!beaconBridge.hasRequiredPermissions()) {
            pendingBeaconStartRequest = request;
            requestPermissions(AndroidPermissionPolicy.beaconScanPermissions(Build.VERSION.SDK_INT), REQUEST_BEACON_PERMISSION);
            return;
        }
        sendResult(beaconBridge.start(request));
    }

    private void stopBeacons(JSONObject message) throws JSONException {
        pendingBeaconStartRequest = null;
        sendResult(beaconBridge.stop(copyRequest(message)));
    }

    private void startBeaconAdvertise(JSONObject message) throws JSONException {
        JSONObject request = copyRequest(message);
        if (!beaconAdvertiserBridge.hasRequiredPermissions()) {
            pendingBeaconAdvertiseStartRequest = request;
            requestPermissions(AndroidPermissionPolicy.beaconAdvertisePermissions(Build.VERSION.SDK_INT), REQUEST_BEACON_ADVERTISE_PERMISSION);
            return;
        }
        sendResult(beaconAdvertiserBridge.start(request));
    }

    private void stopBeaconAdvertise(JSONObject message) throws JSONException {
        pendingBeaconAdvertiseStartRequest = null;
        sendResult(beaconAdvertiserBridge.stop(copyRequest(message)));
    }

    private void handleConfigPairingAction(JSONObject message) throws JSONException {
        JSONObject request = copyRequest(message);
        String action = request.optString("action", "");
        if (!hasConfigPairingPermissions(action)) {
            pendingConfigPairingRequest = request;
            pendingConfigPairingAction = action;
            requestPermissions(AndroidPermissionPolicy.configPairingPermissions(action, Build.VERSION.SDK_INT), REQUEST_CONFIG_PAIRING_PERMISSION);
            return;
        }

        sendResult(dispatchConfigPairingAction(request));
    }

    private JSONObject dispatchConfigPairingAction(JSONObject request) throws JSONException {
        String action = request.optString("action", "");
        switch (action) {
            case "configPairingShow":
                return configPairingBridge.startTargetSession(request);
            case "configPairingStop":
                return configPairingBridge.stopTargetSession(request);
            case "configPairingConnect":
                return configPairingBridge.connect(request);
            case "configPairingDisconnect":
                return configPairingBridge.disconnect(request);
            case "configPairingSend":
                return configPairingBridge.send(request);
            case "configDeviceScanStart":
            case "configDeviceScanStop":
            case "configDeviceConnect":
            case "configDeviceDisconnect":
            case "configDeviceSend":
                return AndroidConfigPairingProtocol.errorResponse(
                        request,
                        action,
                        "Persistent ESP device management is not available on Android yet."
                );
            default:
                return AndroidConfigPairingProtocol.unknownActionResponse(request);
        }
    }

    private boolean hasConfigPairingPermissions(String action) {
        for (String permission : AndroidPermissionPolicy.configPairingPermissions(action, Build.VERSION.SDK_INT)) {
            if (checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) {
                return false;
            }
        }
        return true;
    }

    private SharedPreferences configPrefs() {
        return getSharedPreferences(AndroidSettingsStore.PREFS_NAME, MODE_PRIVATE);
    }

    private AndroidSettingsStore settingsStore() {
        return new AndroidSettingsStore(
                new SharedPreferencesSettingsStore(configPrefs()),
                defaultServerUrl(),
                defaultSecurityToken(),
                defaultBeaconUUID()
        );
    }

    private String configuredStartUrl() {
        return settingsStore().configuredStartUrl(DEFAULT_URL);
    }

    private String defaultServerUrl() {
        return manifestDefaultValue(META_DEFAULT_SERVER_URL, DEFAULT_LOCAL_SERVER_URL);
    }

    private String defaultSecurityToken() {
        return manifestDefaultValue(META_DEFAULT_SECURITY_TOKEN, DEFAULT_SECURITY_TOKEN);
    }

    private String defaultBeaconUUID() {
        return manifestDefaultValue(META_DEFAULT_BEACON_UUID, DEFAULT_BEACON_UUID);
    }

    private String recoveryShortMark() {
        return manifestDefaultValue(META_RECOVERY_SHORT_MARK, DEFAULT_RECOVERY_SHORT_MARK);
    }

    private String recoveryTitle() {
        return manifestDefaultValue(META_RECOVERY_TITLE, DEFAULT_RECOVERY_TITLE);
    }

    private String recoveryBody() {
        return manifestDefaultValue(META_RECOVERY_BODY, DEFAULT_RECOVERY_BODY);
    }

    private String recoverySuccessMessage() {
        return manifestDefaultValue(META_RECOVERY_SUCCESS_MESSAGE, DEFAULT_RECOVERY_SUCCESS_MESSAGE);
    }

    private String recoveryInvalidQRMessage() {
        return manifestDefaultValue(META_RECOVERY_INVALID_QR_MESSAGE, DEFAULT_RECOVERY_INVALID_QR_MESSAGE);
    }

    private String manifestDefaultValue(String key, String fallback) {
        try {
            ApplicationInfo info = getPackageManager().getApplicationInfo(getPackageName(), PackageManager.GET_META_DATA);
            Bundle metaData = info != null ? info.metaData : null;
            if (metaData != null) {
                return nonEmpty(metaData.getString(key), fallback);
            }
        } catch (PackageManager.NameNotFoundException ignored) {
            // Fall back to the wrapper default.
        }
        return fallback;
    }

    private ArrayList<String> configuredStartUrlCandidates() {
        return settingsStore().startUrlCandidates(DEFAULT_URL);
    }

    private boolean isLocalConfiguredUrl(String value) {
        return StartupUrlResolver.isLocalConfiguredUrl(value, DEFAULT_URL);
    }

    private void reloadConfiguredUrlFromSettings() {
        runOnUiThread(this::loadConfiguredUrlFromSettings);
    }

    private void loadConfiguredUrlFromSettings() {
        applyStartupLoadCommand(startupLoadCoordinator.start(
                configuredStartUrlCandidates(),
                settingsStore().highAvailabilityEnabled()
        ));
    }

    private void applyStartupLoadCommand(AndroidStartupLoadCoordinator.Command command) {
        if (command == null || command.kind == AndroidStartupLoadCoordinator.Command.Kind.NONE) {
            return;
        }
        cancelLoadTimeout();
        if (command.kind == AndroidStartupLoadCoordinator.Command.Kind.LOAD_URL) {
            if (webView == null) {
                return;
            }
            webView.loadUrl(command.url);
            scheduleLoadTimeout(command);
            return;
        }

        showRecoveryPage(command);
    }

    private void scheduleLoadTimeout(AndroidStartupLoadCoordinator.Command command) {
        if (!command.scheduleTimeout) {
            return;
        }
        long timeoutMs = settingsStore().highAvailabilityTimeoutMs();
        loadTimeoutRunnable = () -> applyStartupLoadCommand(startupLoadCoordinator.timeout());
        loadHandler.postDelayed(loadTimeoutRunnable, timeoutMs);
    }

    private void cancelLoadTimeout() {
        if (loadTimeoutRunnable != null) {
            loadHandler.removeCallbacks(loadTimeoutRunnable);
            loadTimeoutRunnable = null;
        }
    }

    private void showRecoveryPage(AndroidStartupLoadCoordinator.Command command) {
        if (webView == null) {
            return;
        }
        webBridgeReady = true;
        AndroidRecoveryPageBuilder.Config config = new AndroidRecoveryPageBuilder.Config.Builder()
                .reason(command.reason)
                .candidates(command.candidates)
                .shortMark(recoveryShortMark())
                .title(recoveryTitle())
                .body(recoveryBody())
                .successMessage(recoverySuccessMessage())
                .invalidQRMessage(recoveryInvalidQRMessage())
                .build();
        webView.loadDataWithBaseURL(
                AndroidRecoveryPageBuilder.BASE_URL,
                AndroidRecoveryPageBuilder.html(config),
                "text/html",
                "UTF-8",
                null
        );
    }

    public String configSecurityToken() {
        return settingsStore().securityToken();
    }

    private String configDeviceName() {
        return settingsStore().deviceName();
    }

    private String configAppUUID() {
        return settingsStore().appUUID();
    }

    private String configDeviceUUID() {
        return settingsStore().deviceUUID();
    }

    private String configDeviceLocation() {
        return settingsStore().deviceLocation();
    }

    public JSONObject configSettingsSnapshot() throws JSONException {
        JSONObject snapshot = settingsStore().snapshotPayload();
        if (natsBridge != null) {
            snapshot.put("nats", natsBridge.statusSnapshot());
        }
        return snapshot;
    }

    public JSONObject applyConfigSettings(JSONObject values) throws JSONException {
        return settingsStore().apply(values);
    }

    private JSONObject settingsGet(JSONObject message) throws JSONException {
        return settingsBridge.getResponse(message);
    }

    private JSONObject settingsSet(JSONObject message) throws JSONException {
        return settingsBridge.setResponse(message);
    }

    private JSONObject reload(JSONObject message) throws JSONException {
        JSONObject response = AndroidNativeCommandPayload.reloadResponse(message);
        loadHandler.postDelayed(this::reloadConfiguredUrlFromSettings, 120L);
        return response;
    }

    private JSONObject executeNatsCommand(JSONObject command) throws JSONException {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            return executeNatsCommandOnMain(command);
        }
        CountDownLatch latch = new CountDownLatch(1);
        AtomicReference<JSONObject> result = new AtomicReference<>();
        AtomicReference<Exception> error = new AtomicReference<>();
        runOnUiThread(() -> {
            try {
                result.set(executeNatsCommandOnMain(command));
            } catch (Exception commandError) {
                error.set(commandError);
            } finally {
                latch.countDown();
            }
        });
        try {
            if (!latch.await(15, TimeUnit.SECONDS)) {
                return BridgeResponse.error(command, command.optString("action", "natsCommand"), "NATS command timed out.");
            }
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
            return BridgeResponse.error(command, command.optString("action", "natsCommand"), "NATS command was interrupted.");
        }
        if (error.get() instanceof JSONException) {
            throw (JSONException) error.get();
        }
        if (error.get() != null) {
            return BridgeResponse.error(command, command.optString("action", "natsCommand"), error.get().getMessage());
        }
        return result.get();
    }

    private JSONObject executeNatsCommandOnMain(JSONObject command) throws JSONException {
        JSONObject message = copyRequest(command);
        String action = message.optString("action", "").trim();
        message.put("action", action);
        switch (action) {
            case "natsStatus":
                return natsBridge.status(message);
            case "deviceInfoGet":
                return deviceInfo(message);
            case "settingsGet":
                return settingsGet(message);
            case "settingsSet":
                return natsSettingsSet(message);
            case "screenshotGet":
                if (!message.has("maxWidth")) {
                    message.put("maxWidth", 720);
                }
                if (!message.has("quality")) {
                    message.put("quality", 65);
                }
                return screenshotGet(message);
            case "qrScanImage":
                return natsQrScanImageResponse(message);
            case "screenStreamStart":
                JSONObject natsStreamRequest = natsScreenStreamRequest(message);
                return screenStreamBridge.start(natsStreamRequest, (subject, payload) -> natsBridge.publishData(subject, payload));
            case "screenStreamStop":
                return screenStreamBridge.stop(message);
            case "reload":
                return reload(message);
            default:
                return BridgeResponse.error(message, action.isEmpty() ? "natsCommand" : action, "NATS command is not allowed: " + action);
        }
    }

    private JSONObject natsQrScanImageResponse(JSONObject request) throws JSONException {
        JSONObject response = AndroidQrImageScanner.response(request);
        response.put("workerAppUUID", configAppUUID());
        response.put("completedAt", java.time.Instant.now().toString());
        for (String key : new String[]{"jobId", "scanJobId", "taskId", "distributionId"}) {
            String value = request.optString(key, "").trim();
            if (!value.isEmpty()) {
                response.put(key, value);
            }
        }
        return response;
    }

    private JSONObject natsScreenStreamRequest(JSONObject command) throws JSONException {
        JSONObject request = new JSONObject(command.toString());
        String appUUID = configAppUUID();
        String prefix = settingsStore().natsSettings().devicePrefix(appUUID) + ".";
        if (request.optString("transport", "").trim().isEmpty()) {
            request.put("transport", "nats");
        }
        if (request.optString("subject", "").trim().isEmpty()) {
            request.put("subject", prefix + "screen.frames");
        }
        if (request.optString("metaSubject", "").trim().isEmpty()) {
            request.put("metaSubject", prefix + "screen.meta");
        }
        if (request.optString("eventSubject", "").trim().isEmpty()) {
            request.put("eventSubject", prefix + "screen.events");
        }
        return request;
    }

    private JSONObject natsSettingsSet(JSONObject message) throws JSONException {
        JSONObject values = message.optJSONObject("settings");
        JSONObject snapshot = applyConfigSettings(values != null ? values : message);
        JSONObject response = BridgeResponse.base(message, "settingsSet");
        response.put("success", true);
        response.put("settings", snapshot);
        return response;
    }

    private JSONObject kioskReloadControlSet(JSONObject message) throws JSONException {
        boolean enabled = message.optBoolean("enabled", message.optBoolean("visible", false));
        float opacity = (float) Math.max(0.02, Math.min(1.0, message.optDouble("opacity", 0.10)));
        double longPressSeconds = Math.max(0.5, Math.min(10.0, message.optDouble("longPressSeconds", 2.0)));
        runOnUiThread(() -> setKioskReloadControlVisible(enabled, opacity, longPressSeconds));
        JSONObject response = BridgeResponse.base(message, "kioskReloadControlSet");
        response.put("success", true);
        response.put("enabled", enabled);
        response.put("opacity", opacity);
        response.put("longPressSeconds", longPressSeconds);
        return response;
    }

    private void setKioskReloadControlVisible(boolean enabled, float opacity, double longPressSeconds) {
        if (!enabled) {
            if (kioskReloadControlView != null) {
                ViewGroup parent = (ViewGroup) kioskReloadControlView.getParent();
                if (parent != null) {
                    parent.removeView(kioskReloadControlView);
                }
                kioskReloadControlView = null;
            }
            return;
        }

        if (kioskReloadControlView == null) {
            TextView button = new TextView(this);
            button.setText("R");
            button.setTextColor(Color.WHITE);
            button.setTextSize(18);
            button.setTypeface(Typeface.DEFAULT_BOLD);
            button.setGravity(Gravity.CENTER);
            button.setContentDescription("Reload");
            GradientDrawable background = new GradientDrawable();
            background.setShape(GradientDrawable.OVAL);
            background.setColor(Color.BLACK);
            button.setBackground(background);
            int size = dp(40);
            FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(size, size);
            params.gravity = Gravity.START | Gravity.CENTER_VERTICAL;
            params.leftMargin = dp(2);
            addContentView(button, params);
            kioskReloadControlView = button;
        }

        kioskReloadControlView.setAlpha(opacity);
        kioskReloadControlView.setOnTouchListener((view, event) -> {
            switch (event.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    kioskRestartTriggered = false;
                    if (kioskRestartRunnable != null) {
                        loadHandler.removeCallbacks(kioskRestartRunnable);
                    }
                    kioskRestartRunnable = () -> {
                        kioskRestartTriggered = true;
                        performKioskRestart();
                    };
                    loadHandler.postDelayed(kioskRestartRunnable, (long) (longPressSeconds * 1000));
                    view.setPressed(true);
                    return true;
                case MotionEvent.ACTION_UP:
                    if (kioskRestartRunnable != null) {
                        loadHandler.removeCallbacks(kioskRestartRunnable);
                    }
                    view.setPressed(false);
                    if (!kioskRestartTriggered) {
                        reloadConfiguredUrlFromSettings();
                    }
                    return true;
                case MotionEvent.ACTION_CANCEL:
                    if (kioskRestartRunnable != null) {
                        loadHandler.removeCallbacks(kioskRestartRunnable);
                    }
                    view.setPressed(false);
                    return true;
                default:
                    return true;
            }
        });
    }

    private void performKioskRestart() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            finishAndRemoveTask();
        } else {
            finishAffinity();
        }
        loadHandler.postDelayed(() -> {
            android.os.Process.killProcess(android.os.Process.myPid());
            System.exit(0);
        }, 120L);
    }

    private static final class SharedPreferencesSettingsStore implements AndroidSettingsStore.Preferences {
        private final SharedPreferences preferences;

        SharedPreferencesSettingsStore(SharedPreferences preferences) {
            this.preferences = preferences;
        }

        @Override
        public String getString(String key, String fallback) {
            return preferences.getString(key, fallback);
        }

        @Override
        public boolean getBoolean(String key, boolean fallback) {
            return preferences.getBoolean(key, fallback);
        }

        @Override
        public int getInt(String key, int fallback) {
            return preferences.getInt(key, fallback);
        }

        @Override
        public Editor edit() {
            SharedPreferences.Editor editor = preferences.edit();
            return new Editor() {
                @Override
                public Editor putString(String key, String value) {
                    editor.putString(key, value);
                    return this;
                }

                @Override
                public Editor putBoolean(String key, boolean value) {
                    editor.putBoolean(key, value);
                    return this;
                }

                @Override
                public Editor putInt(String key, int value) {
                    editor.putInt(key, value);
                    return this;
                }

                @Override
                public void apply() {
                    editor.apply();
                }
            };
        }
    }

    private JSONObject configDeviceSummary() throws JSONException {
        AndroidDeviceInfoPayload.DeviceSummary summary = new AndroidDeviceInfoPayload.DeviceSummary();
        summary.manufacturer = stringOrEmpty(Build.MANUFACTURER);
        summary.model = stringOrEmpty(Build.MODEL);
        summary.device = stringOrEmpty(Build.DEVICE);
        summary.osVersion = stringOrEmpty(Build.VERSION.RELEASE);
        summary.sdkInt = Build.VERSION.SDK_INT;
        summary.appVersion = appVersionName();
        summary.wifi = wifiStatusPayload(hasLocationPermission());
        return AndroidDeviceInfoPayload.configPairingDeviceSummary(summary);
    }

    private void showConfigPairingOverlay(String payload, Bitmap qrBitmap, boolean advertising) {
        runOnUiThread(() -> {
            configPairingOverlayPayload = payload;
            configPairingOverlayQrBitmap = qrBitmap;
            configPairingOverlayAdvertising = advertising;
            hideConfigPairingOverlay();
            AndroidConfigPairingLayout.Spec layout = AndroidConfigPairingLayout.from(
                    getResources().getDisplayMetrics(),
                    getResources().getConfiguration().orientation
            );
            int cardPadding = dp(layout.cardPaddingDp);
            int qrSize = dp(layout.qrSizeDp);
            int scannerHeight = dp(layout.scannerHeightDp);
            int containerPadding = dp(layout.containerPaddingDp);
            int verticalGap = dp(layout.verticalGapDp);

            LinearLayout card = new LinearLayout(this);
            card.setOrientation(LinearLayout.VERTICAL);
            card.setGravity(Gravity.CENTER_HORIZONTAL);
            card.setPadding(cardPadding, cardPadding, cardPadding, cardPadding);
            GradientDrawable cardBackground = new GradientDrawable();
            cardBackground.setColor(Color.rgb(23, 23, 27));
            cardBackground.setCornerRadius(dp(24));
            cardBackground.setStroke(dp(1), Color.argb(50, 255, 255, 255));
            card.setBackground(cardBackground);

            TextView title = new TextView(this);
            title.setText("Config Pairing");
            title.setTextColor(Color.WHITE);
            title.setTextSize(layout.titleTextSizeSp);
            title.setTypeface(Typeface.DEFAULT_BOLD);
            title.setGravity(Gravity.CENTER);
            card.addView(title, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

            ImageView qrView = new ImageView(this);
            qrView.setImageBitmap(qrBitmap);
            qrView.setBackgroundColor(Color.WHITE);
            qrView.setPadding(dp(layout.twoColumn ? 8 : 12), dp(layout.twoColumn ? 8 : 12), dp(layout.twoColumn ? 8 : 12), dp(layout.twoColumn ? 8 : 12));

            FrameLayout scannerSlot = new FrameLayout(this);
            GradientDrawable scannerBackground = new GradientDrawable();
            scannerBackground.setColor(Color.BLACK);
            scannerBackground.setCornerRadius(dp(14));
            scannerBackground.setStroke(dp(1), Color.argb(120, 79, 211, 138));
            scannerSlot.setBackground(scannerBackground);

            configPairingStateText = new TextView(this);
            configPairingStateText.setText(advertising ? "BLE active" : "BLE starting");
            configPairingStateText.setTextColor(Color.argb(220, 255, 255, 255));
            configPairingStateText.setTextSize(15);
            configPairingStateText.setTypeface(Typeface.DEFAULT_BOLD);
            configPairingStateText.setGravity(Gravity.CENTER);

            TextView payloadView = new TextView(this);
            payloadView.setText(payload);
            payloadView.setTextColor(Color.argb(185, 255, 255, 255));
            payloadView.setTextSize(10);
            payloadView.setGravity(Gravity.CENTER);
            payloadView.setTypeface(Typeface.MONOSPACE);
            payloadView.setMaxLines(layout.payloadMaxLines);
            payloadView.setPadding(0, dp(layout.twoColumn ? 4 : 10), 0, dp(layout.twoColumn ? 4 : 10));

            LinearLayout controls = new LinearLayout(this);
            controls.setOrientation(LinearLayout.HORIZONTAL);
            controls.setGravity(Gravity.CENTER);
            controls.setWeightSum(2f);

            ImageButton reloadButton = configPairingIconButton(android.R.drawable.ic_popup_sync, "Reload");
            reloadButton.setOnClickListener(view -> {
                try {
                    sendResult(configPairingBridge.stopTargetSession(
                            AndroidConfigPairingProtocol.internalRequest("configPairingStop", "")
                    ));
                    reloadConfiguredUrlFromSettings();
                } catch (JSONException ignored) {
                    // Ignore secondary JSON failure.
                }
            });
            LinearLayout.LayoutParams reloadParams = new LinearLayout.LayoutParams(0, dp(48), 1f);
            reloadParams.setMargins(0, 0, dp(8), 0);
            controls.addView(reloadButton, reloadParams);

            ImageButton closeButton = configPairingIconButton(android.R.drawable.ic_menu_close_clear_cancel, "Close");
            closeButton.setOnClickListener(view -> {
                try {
                    sendResult(configPairingBridge.stopTargetSession(
                            AndroidConfigPairingProtocol.internalRequest("configPairingStop", "")
                    ));
                } catch (JSONException ignored) {
                    // Ignore secondary JSON failure.
                }
            });
            LinearLayout.LayoutParams closeParams = new LinearLayout.LayoutParams(0, dp(48), 1f);
            closeParams.setMargins(dp(8), 0, 0, 0);
            controls.addView(closeButton, closeParams);

            if (layout.twoColumn) {
                LinearLayout contentRow = new LinearLayout(this);
                contentRow.setOrientation(LinearLayout.HORIZONTAL);
                contentRow.setGravity(Gravity.CENTER);

                LinearLayout leftColumn = new LinearLayout(this);
                leftColumn.setOrientation(LinearLayout.VERTICAL);
                leftColumn.setGravity(Gravity.CENTER_HORIZONTAL);
                LinearLayout.LayoutParams qrParams = new LinearLayout.LayoutParams(qrSize, qrSize);
                qrParams.setMargins(0, verticalGap, 0, verticalGap);
                leftColumn.addView(qrView, qrParams);
                leftColumn.addView(configPairingStateText, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
                leftColumn.addView(payloadView, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

                LinearLayout rightColumn = new LinearLayout(this);
                rightColumn.setOrientation(LinearLayout.VERTICAL);
                rightColumn.setGravity(Gravity.CENTER_VERTICAL);
                LinearLayout.LayoutParams scannerParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, scannerHeight);
                scannerParams.setMargins(0, verticalGap, 0, verticalGap);
                rightColumn.addView(scannerSlot, scannerParams);
                rightColumn.addView(controls, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(layout.controlsHeightDp)));

                LinearLayout.LayoutParams leftParams = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 0.36f);
                leftParams.setMargins(0, 0, dp(12), 0);
                contentRow.addView(leftColumn, leftParams);
                LinearLayout.LayoutParams rightParams = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 0.64f);
                rightParams.setMargins(dp(12), 0, 0, 0);
                contentRow.addView(rightColumn, rightParams);
                card.addView(contentRow, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
            } else {
                LinearLayout.LayoutParams qrParams = new LinearLayout.LayoutParams(qrSize, qrSize);
                qrParams.setMargins(0, verticalGap, 0, verticalGap);
                card.addView(qrView, qrParams);
                LinearLayout.LayoutParams scannerParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, scannerHeight);
                scannerParams.setMargins(0, 0, 0, verticalGap);
                card.addView(scannerSlot, scannerParams);
                card.addView(configPairingStateText, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
                card.addView(payloadView, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
                card.addView(controls, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(layout.controlsHeightDp)));
            }

            ScrollView scrollView = new ScrollView(this);
            scrollView.setFillViewport(true);
            LinearLayout container = new LinearLayout(this);
            container.setGravity(layout.twoColumn ? Gravity.CENTER : Gravity.CENTER_HORIZONTAL);
            container.setPadding(containerPadding, containerPadding, containerPadding, containerPadding);
            container.addView(card, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
            scrollView.addView(container, new ScrollView.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
            scrollView.setBackgroundColor(Color.argb(180, 0, 0, 0));
            configPairingOverlay = scrollView;
            addContentView(scrollView, new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
            scannerSlot.post(() -> startConfigPairingOverlayScanner(scannerSlot));
        });
    }

    private void startConfigPairingOverlayScanner(View scannerSlot) {
        if (continuousScannerController == null || !continuousScannerController.hasCameraPermission()) {
            return;
        }
        try {
            JSONObject request = new JSONObject()
                    .put("action", "continuousScanStart")
                    .put("purpose", "configPairing")
                    .put("source", "configPairing")
                    .put("camera", "front")
                    .put("types", new JSONArray().put("qr"))
                    .put("repeatDelaySeconds", 1)
                    .put("closeButton", false)
                    .put("showFlipButton", true);
            continuousScannerController.startInHost(request, scannerSlot);
        } catch (JSONException error) {
            sendContinuousScannerError(error.getMessage());
        }
    }

    private ImageButton configPairingIconButton(int iconResource, String contentDescription) {
        ImageButton button = new ImageButton(this);
        button.setImageResource(iconResource);
        button.setContentDescription(contentDescription);
        button.setColorFilter(Color.WHITE);
        button.setPadding(dp(12), dp(10), dp(12), dp(10));
        GradientDrawable background = new GradientDrawable();
        background.setColor(Color.rgb(10, 132, 255));
        background.setCornerRadius(dp(12));
        button.setBackground(background);
        return button;
    }

    private void setConfigPairingOverlayAdvertising(boolean advertising) {
        runOnUiThread(() -> {
            configPairingOverlayAdvertising = advertising;
            if (configPairingStateText != null) {
                configPairingStateText.setText(advertising ? "BLE active" : "BLE starting");
            }
        });
    }

    private void hideConfigPairingOverlay() {
        runOnUiThread(() -> {
            try {
                continuousScannerController.stop(new JSONObject().put("action", "continuousScanStop"));
            } catch (JSONException ignored) {
                // Ignore local cleanup failure while removing the overlay.
            }
            if (configPairingOverlay != null) {
                ViewGroup parent = (ViewGroup) configPairingOverlay.getParent();
                if (parent != null) {
                    parent.removeView(configPairingOverlay);
                }
            }
            configPairingOverlay = null;
            configPairingStateText = null;
        });
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private void handleConfigPairingGesture(MotionEvent event) {
        if (configPairingOverlay != null) {
            return;
        }
        int action = event.getActionMasked();
        if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL || action == MotionEvent.ACTION_POINTER_UP) {
            configPairingHoldStartMs = 0L;
            configPairingHoldTriggered = false;
            return;
        }

        if (event.getPointerCount() < 2 || !isTwoFingerHoldInCenter(event)) {
            configPairingHoldStartMs = 0L;
            configPairingHoldTriggered = false;
            return;
        }

        long now = System.currentTimeMillis();
        if (configPairingHoldStartMs == 0L) {
            configPairingHoldStartMs = now;
        }
        if (!configPairingHoldTriggered && now - configPairingHoldStartMs >= 1500L) {
            configPairingHoldTriggered = true;
            try {
                handleConfigPairingAction(AndroidConfigPairingProtocol.internalRequest("configPairingShow", "twoFingerHold"));
            } catch (JSONException error) {
                sendErrorSafe(null, "configPairingShow", error.getMessage());
            }
        }
    }

    private boolean isTwoFingerHoldInCenter(MotionEvent event) {
        if (event.getPointerCount() < 2) {
            return false;
        }
        float centerX = (event.getX(0) + event.getX(1)) / 2f;
        float centerY = (event.getY(0) + event.getY(1)) / 2f;
        float left = webView.getWidth() * 0.25f;
        float right = webView.getWidth() * 0.75f;
        float top = webView.getHeight() * 0.25f;
        float bottom = webView.getHeight() * 0.75f;
        return centerX >= left && centerX <= right && centerY >= top && centerY <= bottom;
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

    private JSONObject copyRequest(JSONObject message) {
        try {
            return new JSONObject(message != null ? message.toString() : "{}");
        } catch (JSONException ignored) {
            return new JSONObject();
        }
    }

    private void startPhotoCapture(JSONObject message) throws JSONException {
        pendingRequest = message;
        pendingAction = "takePhoto";
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(AndroidPermissionPolicy.cameraPermissions(), REQUEST_CAMERA_PERMISSION);
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
        GmsBarcodeScannerOptions.Builder builder = new GmsBarcodeScannerOptions.Builder()
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
                );
        if (message.optBoolean("autoZoom", false)) {
            builder.enableAutoZoom();
        }
        GmsBarcodeScannerOptions options = builder.build();
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
        if (requestCode == REQUEST_PORTRAIT_CAMERA_PERMISSION) {
            JSONObject request = pendingPortraitCaptureRequest;
            pendingPortraitCaptureRequest = null;
            if (allPermissionsGranted(grantResults) && request != null && portraitCaptureController != null) {
                portraitCaptureController.start(request);
            } else {
                sendErrorSafe(request, "portraitCapture", "Camera permission was denied.");
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
        if (requestCode == REQUEST_BEACON_ADVERTISE_PERMISSION) {
            if (allPermissionsGranted(grantResults) && pendingBeaconAdvertiseStartRequest != null) {
                try {
                    sendResult(beaconAdvertiserBridge.start(pendingBeaconAdvertiseStartRequest));
                } catch (JSONException error) {
                    sendErrorSafe(pendingBeaconAdvertiseStartRequest, "beaconAdvertiseStart", error.getMessage());
                } finally {
                    pendingBeaconAdvertiseStartRequest = null;
                }
            } else {
                sendErrorSafe(pendingBeaconAdvertiseStartRequest, "beaconAdvertiseStart", "Bluetooth advertise permission is required for iBeacon advertising.");
                pendingBeaconAdvertiseStartRequest = null;
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
        if (requestCode == REQUEST_TAP_TO_PAY_LOCATION_PERMISSION) {
            JSONObject request = pendingTapToPayRequest;
            pendingTapToPayRequest = null;
            if (tapToPayBridge == null) {
                sendErrorSafe(request, "tapToPayCollect", "Android Tap to Pay bridge is not included in this wrapper build.");
            } else if (allPermissionsGranted(grantResults) && request != null) {
                try {
                    tapToPayBridge.collect(request);
                } catch (JSONException error) {
                    sendErrorSafe(request, "tapToPayCollect", error.getMessage());
                }
            } else {
                sendErrorSafe(request, "tapToPayCollect", "Location permission was denied. Stripe Tap to Pay requires location access.");
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
                    sendResult(AndroidWifiBridge.statusResponse(request, wifiStatusPayload(false)));
                } catch (JSONException error) {
                    sendErrorSafe(request, "wifiStatusGet", error.getMessage());
                }
            }
            return;
        }
        if (requestCode == REQUEST_CONFIG_PAIRING_PERMISSION) {
            JSONObject request = pendingConfigPairingRequest;
            String action = pendingConfigPairingAction;
            pendingConfigPairingRequest = null;
            pendingConfigPairingAction = null;
            if (allPermissionsGranted(grantResults) && request != null) {
                try {
                    sendResult(dispatchConfigPairingAction(request));
                } catch (JSONException error) {
                    sendErrorSafe(request, action, error.getMessage());
                }
            } else {
                sendErrorSafe(request, action, "Bluetooth permissions are required for config pairing.");
            }
            return;
        }
        if (requestCode == REQUEST_NOTIFICATION_PERMISSION) {
            JSONObject request = pendingNotificationPermissionRequest;
            pendingNotificationPermissionRequest = null;
            if (request != null) {
                try {
                    boolean granted = grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED;
                    sendResult(notificationBridge.permissionRequestResult(request, granted));
                } catch (JSONException error) {
                    sendErrorSafe(request, "notificationPermissionRequest", error.getMessage());
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
        AndroidConfigPairingBridge.ResultCallback callback = pendingWifiConfigCallback;
        pendingWifiRequest = null;
        pendingWifiConfigCallback = null;
        try {
            JSONObject response = AndroidWifiBridge.addNetworksResultResponse(request, resultCode == RESULT_OK);
            if (callback != null) {
                callback.complete(response);
            } else {
                sendResult(response);
            }
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
            String outputType = pendingRequest.optString("outputType", "png").toLowerCase();
            if ("pdf".equals(outputType) && result != null && result.getPdf() != null) {
                JSONObject response = AndroidCaptureResponseBuilder.documentPdf(
                        pendingRequest,
                        result.getPdf().getPageCount(),
                        uriToDataUrl(result.getPdf().getUri(), "application/pdf")
                );
                sendResult(response);
            } else {
                JSONArray images = new JSONArray();
                List<GmsDocumentScanningResult.Page> pages = result != null ? result.getPages() : null;
                if (pages != null) {
                    for (GmsDocumentScanningResult.Page page : pages) {
                        images.put(uriToDataUrl(page.getImageUri(), "image/jpeg"));
                    }
                }
                JSONObject response = AndroidCaptureResponseBuilder.documentImages(
                        pendingRequest,
                        images
                );
                sendResult(response);
            }
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
        String format = AndroidCaptureResponseBuilder.photoFormat(pendingRequest, backgroundRemoved);
        boolean wantsPng = "png".equals(format);
        String imageData = bitmapToDataUrl(bitmap, wantsPng ? Bitmap.CompressFormat.PNG : Bitmap.CompressFormat.JPEG, wantsPng ? 100 : 88);
        JSONObject response = AndroidCaptureResponseBuilder.photo(pendingRequest, format, imageData, backgroundRemoved);
        sendResult(response);
    }

    private void sendBarcodeResult(Barcode barcode) {
        try {
            String code = barcode.getRawValue() != null ? barcode.getRawValue() : "";
            boolean recoverySource = pendingRequest != null && "recovery".equals(pendingRequest.optString("source", ""));
            AndroidBarcodeConfigHandler.Result configResult = AndroidBarcodeConfigHandler.evaluate(
                    code,
                    recoverySource,
                    configSecurityToken()
            );
            if (configResult.kind == AndroidBarcodeConfigHandler.Kind.CONFIG_CHANGE) {
                sendResult(AndroidBarcodeResponseBuilder.configChanged(pendingRequest, applyConfigSettings(configResult.settings)));
                if (configResult.hasWifiRequest()) {
                    configureWifi(configResult.wifiRequest, result -> {
                        sendResult(result);
                        reloadConfiguredUrlFromSettings();
                    });
                } else {
                    reloadConfiguredUrlFromSettings();
                }
                return;
            }
            if (configResult.kind == AndroidBarcodeConfigHandler.Kind.RECOVERY_SERVER_URL) {
                applyConfigSettings(configResult.settings);
                sendResult(AndroidBarcodeResponseBuilder.recoveryApplied(
                        pendingRequest,
                        code,
                        barcode.getFormat(),
                        configResult.serverUrl
                ));
                loadHandler.postDelayed(this::reloadConfiguredUrlFromSettings, 350L);
                return;
            }
            sendResult(AndroidBarcodeResponseBuilder.success(pendingRequest, code, barcode.getFormat()));
        } catch (JSONException error) {
            sendErrorSafe(pendingRequest, "scanBarcode", error.getMessage());
        } finally {
            clearPendingAction();
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

    public void sendErrorSafe(JSONObject source, String action, String error) {
        try {
            sendError(source, action, error);
        } catch (JSONException ignored) {
            // Ignore secondary JSON failure.
        }
    }

    public void sendError(JSONObject source, String action, String error) throws JSONException {
        sendResult(AndroidHostBridgePayload.errorResponse(source, action, error));
    }

    private String nonEmpty(String value, String fallback) {
        if (value == null) {
            return fallback;
        }
        String trimmed = value.trim();
        return trimmed.isEmpty() ? fallback : trimmed;
    }

    public JSONObject baseResponse(JSONObject message, String action) throws JSONException {
        return AndroidHostBridgePayload.baseResponse(message, action);
    }
}
