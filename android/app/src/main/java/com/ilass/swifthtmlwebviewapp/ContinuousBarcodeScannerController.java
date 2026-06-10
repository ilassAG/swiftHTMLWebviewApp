package com.ilass.swifthtmlwebviewapp;

import android.Manifest;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.media.Image;
import android.os.Build;
import android.os.Looper;
import android.util.DisplayMetrics;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.ImageButton;

import androidx.activity.ComponentActivity;
import androidx.camera.core.CameraSelector;
import androidx.camera.core.ExperimentalGetImage;
import androidx.camera.core.ImageAnalysis;
import androidx.camera.core.ImageProxy;
import androidx.camera.core.Preview;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.camera.view.PreviewView;
import androidx.core.content.ContextCompat;

import com.google.common.util.concurrent.ListenableFuture;
import com.google.mlkit.vision.barcode.BarcodeScanner;
import com.google.mlkit.vision.barcode.BarcodeScanning;
import com.google.mlkit.vision.barcode.BarcodeScannerOptions;
import com.google.mlkit.vision.barcode.common.Barcode;
import com.google.mlkit.vision.common.InputImage;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

final class ContinuousBarcodeScannerController {
    interface Listener {
        void onScannerEvent(JSONObject event);
        void onScannerError(String message);
        void onScannerClosedByUser();
    }

    private final ComponentActivity activity;
    private final Listener listener;
    private final ExecutorService analysisExecutor = Executors.newSingleThreadExecutor();
    private final Map<String, Long> lastSeenByCode = new HashMap<>();

    private FrameLayout overlay;
    private PreviewView previewView;
    private ImageButton closeButton;
    private ProcessCameraProvider cameraProvider;
    private BarcodeScanner barcodeScanner;
    private ScannerConfig currentConfig;
    private int scannerGeneration = 0;

    ContinuousBarcodeScannerController(ComponentActivity activity, Listener listener) {
        this.activity = activity;
        this.listener = listener;
    }

    boolean hasCameraPermission() {
        return ContextCompat.checkSelfPermission(activity, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED;
    }

    JSONObject start(JSONObject request) throws JSONException {
        currentConfig = ScannerConfig.from(request);
        lastSeenByCode.clear();
        scannerGeneration += 1;
        int generation = scannerGeneration;
        runOnMainThread(() -> {
            try {
                ensureOverlay();
                if (currentConfig != null && generation == scannerGeneration) {
                    if (closeButton != null) {
                        closeButton.setVisibility(currentConfig.showCloseButton ? View.VISIBLE : View.GONE);
                    }
                    applyPreviewRect(currentConfig.rect);
                    bindCamera(generation);
                }
            } catch (Exception error) {
                listener.onScannerError("Continuous scanner failed: " + error.getMessage());
                stopInternal();
            }
        });
        return currentConfig.response(request, currentConfig.action, true);
    }

    JSONObject updatePreviewRect(JSONObject request) throws JSONException {
        if (currentConfig == null) {
            JSONObject response = baseResponse(request, request.optString("action", "previewBoxLocationUpdate"));
            response.put("success", false);
            response.put("error", "No continuous scanner is running.");
            return response;
        }

        RectPercent rect = RectPercent.from(request.optJSONObject("previewRect"), currentConfig.rect);
        currentConfig.rect = rect;
        runOnMainThread(() -> applyPreviewRect(rect));

        JSONObject response = baseResponse(request, request.optString("action", "previewBoxLocationUpdate"));
        response.put("success", true);
        response.put("previewRect", rect.toJson());
        return response;
    }

    JSONObject stop(JSONObject request) throws JSONException {
        runOnMainThread(this::stopInternal);
        JSONObject response = baseResponse(request, request.optString("action", "continuousScanStop"));
        response.put("success", true);
        return response;
    }

    void shutdown() {
        runOnMainThread(this::stopInternal);
        analysisExecutor.shutdownNow();
    }

    private void ensureOverlay() {
        if (overlay != null) {
            return;
        }

        overlay = new FrameLayout(activity);
        overlay.setClipToOutline(true);
        GradientDrawable overlayBackground = new GradientDrawable();
        overlayBackground.setColor(Color.BLACK);
        overlayBackground.setStroke(dp(2), Color.rgb(79, 211, 138));
        overlay.setBackground(overlayBackground);
        overlay.setPadding(dp(2), dp(2), dp(2), dp(2));

        previewView = new PreviewView(activity);
        previewView.setImplementationMode(PreviewView.ImplementationMode.COMPATIBLE);
        overlay.addView(previewView, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
        ));

        closeButton = new ImageButton(activity);
        closeButton.setImageResource(android.R.drawable.ic_menu_close_clear_cancel);
        closeButton.setBackgroundColor(Color.TRANSPARENT);
        closeButton.setColorFilter(Color.WHITE);
        closeButton.setOnClickListener(view -> {
            runOnMainThread(this::stopInternal);
            listener.onScannerClosedByUser();
        });
        FrameLayout.LayoutParams closeParams = new FrameLayout.LayoutParams(dp(28), dp(28));
        closeParams.gravity = Gravity.TOP | Gravity.RIGHT;
        overlay.addView(closeButton, closeParams);

        activity.addContentView(overlay, new FrameLayout.LayoutParams(dp(220), dp(180)));
    }

    private void applyPreviewRect(RectPercent rect) {
        if (overlay == null) {
            return;
        }

        DisplayMetrics metrics = activity.getResources().getDisplayMetrics();
        int screenWidth = metrics.widthPixels;
        int screenHeight = metrics.heightPixels;
        int width = Math.max((int) (screenWidth * rect.width), dp(72));
        int height = Math.max((int) (screenHeight * rect.height), dp(72));
        int left = Math.min(Math.max((int) (screenWidth * rect.left), 0), Math.max(screenWidth - width, 0));
        int top = Math.min(Math.max((int) (screenHeight * rect.top), 0), Math.max(screenHeight - height, 0));

        FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(width, height);
        params.leftMargin = left;
        params.topMargin = top;
        params.gravity = Gravity.TOP | Gravity.LEFT;
        overlay.setLayoutParams(params);
        overlay.bringToFront();
    }

    private void bindCamera(int generation) {
        ListenableFuture<ProcessCameraProvider> cameraProviderFuture = ProcessCameraProvider.getInstance(activity);
        cameraProviderFuture.addListener(() -> {
            try {
                PreviewView activePreviewView = previewView;
                ScannerConfig activeConfig = currentConfig;
                if (activePreviewView == null || activeConfig == null || generation != scannerGeneration) {
                    return;
                }

                cameraProvider = cameraProviderFuture.get();
                Preview preview = new Preview.Builder().build();
                preview.setSurfaceProvider(activePreviewView.getSurfaceProvider());

                if (barcodeScanner != null) {
                    barcodeScanner.close();
                }
                barcodeScanner = BarcodeScanning.getClient(scannerOptions(activeConfig.types));
                ImageAnalysis analysis = new ImageAnalysis.Builder()
                        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                        .build();
                analysis.setAnalyzer(analysisExecutor, this::analyzeImage);

                CameraSelector selector = new CameraSelector.Builder()
                        .requireLensFacing("front".equals(activeConfig.camera)
                                ? CameraSelector.LENS_FACING_FRONT
                                : CameraSelector.LENS_FACING_BACK)
                        .build();

                cameraProvider.unbindAll();
                cameraProvider.bindToLifecycle(activity, selector, preview, analysis);
            } catch (Exception error) {
                listener.onScannerError("Continuous scanner failed: " + error.getMessage());
                stopInternal();
            }
        }, ContextCompat.getMainExecutor(activity));
    }

    @ExperimentalGetImage
    private void analyzeImage(ImageProxy imageProxy) {
        Image image = imageProxy.getImage();
        if (image == null || barcodeScanner == null || currentConfig == null) {
            imageProxy.close();
            return;
        }

        InputImage inputImage = InputImage.fromMediaImage(image, imageProxy.getImageInfo().getRotationDegrees());
        barcodeScanner.process(inputImage)
                .addOnSuccessListener(this::handleBarcodes)
                .addOnFailureListener(error -> listener.onScannerError("Barcode analysis failed: " + error.getMessage()))
                .addOnCompleteListener(task -> imageProxy.close());
    }

    private void handleBarcodes(java.util.List<Barcode> barcodes) {
        ScannerConfig config = currentConfig;
        if (config == null) {
            return;
        }

        long now = System.currentTimeMillis();
        for (Barcode barcode : barcodes) {
            String code = barcode.getRawValue();
            if (code == null || code.trim().isEmpty()) {
                continue;
            }

            Long lastSeen = lastSeenByCode.get(code);
            if (lastSeen != null && now - lastSeen < config.repeatDelayMs) {
                continue;
            }
            lastSeenByCode.put(code, now);

            try {
                JSONObject event = new JSONObject();
                event.put("platform", "android");
                event.put("action", "login".equals(config.mode) ? "barcodeLogin" : "barcodeData");
                event.put("sourceAction", config.action);
                event.put("mode", config.mode);
                event.put("camera", config.camera);
                event.put("code", code);
                event.put("format", displayFormat(barcode.getFormat()));
                event.put("timestamp", timestamp(now));
                listener.onScannerEvent(event);
            } catch (JSONException error) {
                listener.onScannerError("Barcode event could not be encoded: " + error.getMessage());
            }
        }
    }

    private BarcodeScannerOptions scannerOptions(JSONArray types) {
        int[] formats = barcodeFormats(types);
        BarcodeScannerOptions.Builder builder = new BarcodeScannerOptions.Builder();
        if (formats.length > 0) {
            int first = formats[0];
            int[] rest = new int[formats.length - 1];
            System.arraycopy(formats, 1, rest, 0, rest.length);
            builder.setBarcodeFormats(first, rest);
        }
        return builder.build();
    }

    private int[] barcodeFormats(JSONArray types) {
        if (types == null || types.length() == 0) {
            return new int[]{
                    Barcode.FORMAT_QR_CODE,
                    Barcode.FORMAT_EAN_13,
                    Barcode.FORMAT_EAN_8,
                    Barcode.FORMAT_CODE_128,
                    Barcode.FORMAT_DATA_MATRIX
            };
        }

        java.util.ArrayList<Integer> formats = new java.util.ArrayList<>();
        for (int i = 0; i < types.length(); i += 1) {
            int format = barcodeFormat(types.optString(i, ""));
            if (format != 0 && !formats.contains(format)) {
                formats.add(format);
            }
        }

        int[] result = new int[formats.size()];
        for (int i = 0; i < formats.size(); i += 1) {
            result[i] = formats.get(i);
        }
        return result;
    }

    private int barcodeFormat(String value) {
        switch (value.toLowerCase(Locale.US)) {
            case "qr": return Barcode.FORMAT_QR_CODE;
            case "ean13": return Barcode.FORMAT_EAN_13;
            case "ean8": return Barcode.FORMAT_EAN_8;
            case "code128": return Barcode.FORMAT_CODE_128;
            case "code39": return Barcode.FORMAT_CODE_39;
            case "code93": return Barcode.FORMAT_CODE_93;
            case "datamatrix": return Barcode.FORMAT_DATA_MATRIX;
            case "aztec": return Barcode.FORMAT_AZTEC;
            case "pdf417": return Barcode.FORMAT_PDF417;
            case "upca": return Barcode.FORMAT_UPC_A;
            case "upce": return Barcode.FORMAT_UPC_E;
            case "itf":
            case "itf14":
            case "interleaved2of5": return Barcode.FORMAT_ITF;
            default: return 0;
        }
    }

    private void stopInternal() {
        scannerGeneration += 1;
        if (cameraProvider != null) {
            cameraProvider.unbindAll();
            cameraProvider = null;
        }
        if (barcodeScanner != null) {
            barcodeScanner.close();
            barcodeScanner = null;
        }
        if (overlay != null) {
            ViewGroup parent = (ViewGroup) overlay.getParent();
            if (parent != null) {
                parent.removeView(overlay);
            }
            overlay = null;
            previewView = null;
            closeButton = null;
        }
        currentConfig = null;
        lastSeenByCode.clear();
    }

    private void runOnMainThread(Runnable runnable) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            runnable.run();
            return;
        }
        activity.runOnUiThread(runnable);
    }

    private int dp(int value) {
        return Math.round(value * activity.getResources().getDisplayMetrics().density);
    }

    private static JSONObject baseResponse(JSONObject request, String action) throws JSONException {
        JSONObject response = new JSONObject();
        response.put("platform", "android");
        response.put("action", action);
        if (request != null && request.has("requestId")) {
            response.put("requestId", request.optString("requestId"));
        }
        return response;
    }

    private static String displayFormat(int format) {
        switch (format) {
            case Barcode.FORMAT_QR_CODE: return "qr";
            case Barcode.FORMAT_EAN_13: return "ean13";
            case Barcode.FORMAT_EAN_8: return "ean8";
            case Barcode.FORMAT_CODE_128: return "code128";
            case Barcode.FORMAT_CODE_39: return "code39";
            case Barcode.FORMAT_CODE_93: return "code93";
            case Barcode.FORMAT_DATA_MATRIX: return "datamatrix";
            case Barcode.FORMAT_AZTEC: return "aztec";
            case Barcode.FORMAT_PDF417: return "pdf417";
            case Barcode.FORMAT_UPC_A: return "upca";
            case Barcode.FORMAT_UPC_E: return "upce";
            case Barcode.FORMAT_ITF: return "itf";
            default: return "unknown";
        }
    }

    private static String timestamp(long timeMs) {
        return new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", Locale.US).format(new Date(timeMs));
    }

    private static final class ScannerConfig {
        final String action;
        final String mode;
        final String camera;
        final JSONArray types;
        final long repeatDelayMs;
        final boolean showCloseButton;
        RectPercent rect;

        private ScannerConfig(String action, String mode, String camera, JSONArray types, long repeatDelayMs, RectPercent rect, boolean showCloseButton) {
            this.action = action;
            this.mode = mode;
            this.camera = camera;
            this.types = types;
            this.repeatDelayMs = repeatDelayMs;
            this.rect = rect;
            this.showCloseButton = showCloseButton;
        }

        static ScannerConfig from(JSONObject request) {
            String action = request.optString("action", "continuousScanStart");
            String mode = nonEmpty(request.optString("mode", ""), "loginScanStart".equals(action) ? "login" : "data");
            String camera = nonEmpty(request.optString("camera", ""), "loginScanStart".equals(action) ? "front" : "back");
            JSONArray types = request.optJSONArray("types");
            double repeatDelaySeconds = request.has("repeatDelaySeconds")
                    ? request.optDouble("repeatDelaySeconds", 1.5)
                    : request.optDouble("repeatDelay", 1.5);
            long repeatDelayMs = Math.max(100L, Math.round(repeatDelaySeconds * 1000.0));
            RectPercent rect = RectPercent.from(request.optJSONObject("previewRect"), RectPercent.defaults());
            boolean showCloseButton = request.optBoolean("showCloseButton", request.optBoolean("closeButton", true));
            return new ScannerConfig(action, mode, camera, types, repeatDelayMs, rect, showCloseButton);
        }

        JSONObject response(JSONObject request, String action, boolean success) throws JSONException {
            JSONObject response = baseResponse(request, action);
            response.put("success", success);
            response.put("mode", mode);
            response.put("camera", camera);
            response.put("repeatDelaySeconds", repeatDelayMs / 1000.0);
            response.put("previewRect", rect.toJson());
            response.put("showCloseButton", showCloseButton);
            response.put("provider", "android_camerax_mlkit");
            if (types != null) {
                response.put("types", types);
            }
            return response;
        }

        private static String nonEmpty(String value, String fallback) {
            String trimmed = value == null ? "" : value.trim();
            return trimmed.isEmpty() ? fallback : trimmed;
        }
    }

    private static final class RectPercent {
        final double top;
        final double left;
        final double width;
        final double height;

        private RectPercent(double top, double left, double width, double height) {
            this.top = top;
            this.left = left;
            this.width = width;
            this.height = height;
        }

        static RectPercent defaults() {
            return new RectPercent(0.18, 0.10, 0.80, 0.36);
        }

        static RectPercent from(JSONObject json, RectPercent fallback) {
            if (json == null) {
                return fallback;
            }
            double width = clamp(sizeValue(json, "width", fallback.width), 0.1, 1.0);
            double height = clamp(sizeValue(json, "height", fallback.height), 0.1, 1.0);
            double left = clamp(positionValue(json, "left", "x", fallback.left), 0.0, 1.0 - width);
            double top = clamp(positionValue(json, "top", "y", fallback.top), 0.0, 1.0 - height);
            return new RectPercent(top, left, width, height);
        }

        JSONObject toJson() throws JSONException {
            JSONObject json = new JSONObject();
            json.put("top", top);
            json.put("left", left);
            json.put("width", width);
            json.put("height", height);
            return json;
        }

        private static double positionValue(JSONObject json, String key, String alias, double fallback) {
            if (json.has(key)) {
                return normalize(json.optDouble(key, fallback));
            }
            return normalize(json.optDouble(alias, fallback));
        }

        private static double sizeValue(JSONObject json, String key, double fallback) {
            return normalize(json.optDouble(key, fallback));
        }

        private static double normalize(double value) {
            return value > 1.0 ? value / 100.0 : value;
        }

        private static double clamp(double value, double min, double max) {
            return Math.max(min, Math.min(max, value));
        }
    }
}
