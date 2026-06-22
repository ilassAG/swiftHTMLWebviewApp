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
import androidx.camera.core.Camera;
import androidx.camera.core.CameraSelector;
import androidx.camera.core.ExperimentalGetImage;
import androidx.camera.core.FocusMeteringAction;
import androidx.camera.core.ImageAnalysis;
import androidx.camera.core.ImageProxy;
import androidx.camera.core.MeteringPoint;
import androidx.camera.core.MeteringPointFactory;
import androidx.camera.core.Preview;
import androidx.camera.core.SurfaceOrientedMeteringPointFactory;
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

import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

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
    private ImageButton flipButton;
    private ViewGroup hostedParent;
    private ProcessCameraProvider cameraProvider;
    private BarcodeScanner barcodeScanner;
    private AndroidContinuousScannerConfig currentConfig;
    private int scannerGeneration = 0;

    ContinuousBarcodeScannerController(ComponentActivity activity, Listener listener) {
        this.activity = activity;
        this.listener = listener;
    }

    boolean hasCameraPermission() {
        return ContextCompat.checkSelfPermission(activity, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED;
    }

    JSONObject start(JSONObject request) throws JSONException {
        currentConfig = AndroidContinuousScannerConfig.from(request);
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
                    if (flipButton != null) {
                        flipButton.setVisibility(currentConfig.showFlipButton ? View.VISIBLE : View.GONE);
                    }
                    applyPreviewRect(currentConfig.rect);
                    bindCameraAfterLayout(generation);
                }
            } catch (Exception error) {
                listener.onScannerError("Continuous scanner failed: " + error.getMessage());
                stopInternal();
            }
        });
        return currentConfig.response(request, currentConfig.action, true);
    }

    JSONObject startInHost(JSONObject request, View hostView) throws JSONException {
        currentConfig = AndroidContinuousScannerConfig.from(request);
        lastSeenByCode.clear();
        scannerGeneration += 1;
        int generation = scannerGeneration;
        runOnMainThread(() -> {
            try {
                ensureHostedOverlay(hostView);
                if (currentConfig != null && generation == scannerGeneration) {
                    if (closeButton != null) {
                        closeButton.setVisibility(currentConfig.showCloseButton ? View.VISIBLE : View.GONE);
                    }
                    if (flipButton != null) {
                        flipButton.setVisibility(currentConfig.showFlipButton ? View.VISIBLE : View.GONE);
                    }
                    bindCameraAfterLayout(generation);
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
            JSONObject response = AndroidContinuousScannerConfig.baseResponse(request, request.optString("action", "previewBoxLocationUpdate"));
            response.put("success", false);
            response.put("error", "No continuous scanner is running.");
            return response;
        }

        AndroidContinuousScannerConfig.RectPercent rect = AndroidContinuousScannerConfig.RectPercent.from(request.optJSONObject("previewRect"), currentConfig.rect);
        currentConfig.rect = rect;
        runOnMainThread(() -> applyPreviewRect(rect));

        JSONObject response = AndroidContinuousScannerConfig.baseResponse(request, request.optString("action", "previewBoxLocationUpdate"));
        response.put("success", true);
        response.put("previewRect", rect.toJson());
        return response;
    }

    JSONObject stop(JSONObject request) throws JSONException {
        runOnMainThread(this::stopInternal);
        return AndroidContinuousScannerConfig.stopResponse(request);
    }

    void shutdown() {
        runOnMainThread(this::stopInternal);
        analysisExecutor.shutdownNow();
    }

    private void ensureOverlay() {
        if (overlay != null) {
            return;
        }

        createOverlay();
        hostedParent = null;
        activity.addContentView(overlay, new FrameLayout.LayoutParams(dp(220), dp(180)));
    }

    private void ensureHostedOverlay(View hostView) {
        if (!(hostView instanceof ViewGroup)) {
            ensureOverlay();
            applyHostFrame(hostView);
            return;
        }

        ViewGroup host = (ViewGroup) hostView;
        if (overlay != null && overlay.getParent() == host) {
            hostedParent = host;
            return;
        }

        removeOverlayFromParent();
        createOverlay();
        hostedParent = host;
        host.addView(overlay, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
        ));
        overlay.bringToFront();
    }

    private void createOverlay() {
        overlay = new FrameLayout(activity);
        overlay.setClipToOutline(true);
        GradientDrawable overlayBackground = new GradientDrawable();
        overlayBackground.setColor(Color.BLACK);
        overlayBackground.setStroke(dp(2), Color.rgb(79, 211, 138));
        overlay.setBackground(overlayBackground);
        overlay.setPadding(dp(2), dp(2), dp(2), dp(2));

        previewView = new PreviewView(activity);
        previewView.setImplementationMode(PreviewView.ImplementationMode.COMPATIBLE);
        previewView.setScaleType(PreviewView.ScaleType.FILL_CENTER);
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

        flipButton = new ImageButton(activity);
        flipButton.setImageResource(android.R.drawable.ic_menu_camera);
        flipButton.setColorFilter(Color.WHITE);
        GradientDrawable flipBackground = new GradientDrawable();
        flipBackground.setShape(GradientDrawable.OVAL);
        flipBackground.setColor(Color.argb(190, 0, 0, 0));
        flipButton.setBackground(flipBackground);
        flipButton.setOnClickListener(view -> toggleCamera());
        FrameLayout.LayoutParams flipParams = new FrameLayout.LayoutParams(dp(52), dp(44));
        flipParams.gravity = Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL;
        flipParams.bottomMargin = dp(8);
        overlay.addView(flipButton, flipParams);
    }

    private void toggleCamera() {
        AndroidContinuousScannerConfig config = currentConfig;
        if (config == null) {
            return;
        }
        config.camera = "front".equals(config.camera) ? "back" : "front";
        lastSeenByCode.clear();
        scannerGeneration += 1;
        bindCameraAfterLayout(scannerGeneration);
    }

    private void applyPreviewRect(AndroidContinuousScannerConfig.RectPercent rect) {
        if (overlay == null) {
            return;
        }
        if (hostedParent != null) {
            ViewGroup.LayoutParams currentParams = overlay.getLayoutParams();
            if (!(currentParams instanceof FrameLayout.LayoutParams)
                    || currentParams.width != ViewGroup.LayoutParams.MATCH_PARENT
                    || currentParams.height != ViewGroup.LayoutParams.MATCH_PARENT) {
                overlay.setLayoutParams(new FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT
                ));
            }
            overlay.bringToFront();
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

    private void applyHostFrame(View hostView) {
        if (overlay == null || hostView == null) {
            return;
        }
        View contentRoot = activity.findViewById(android.R.id.content);
        int[] hostLocation = new int[2];
        int[] rootLocation = new int[2];
        hostView.getLocationInWindow(hostLocation);
        if (contentRoot != null) {
            contentRoot.getLocationInWindow(rootLocation);
        }
        int width = Math.max(hostView.getWidth(), dp(72));
        int height = Math.max(hostView.getHeight(), dp(72));
        FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(width, height);
        params.leftMargin = Math.max(hostLocation[0] - rootLocation[0], 0);
        params.topMargin = Math.max(hostLocation[1] - rootLocation[1], 0);
        params.gravity = Gravity.TOP | Gravity.LEFT;
        overlay.setLayoutParams(params);
        overlay.bringToFront();
    }

    private void bindCamera(int generation) {
        ListenableFuture<ProcessCameraProvider> cameraProviderFuture = ProcessCameraProvider.getInstance(activity);
        cameraProviderFuture.addListener(() -> {
            try {
                PreviewView activePreviewView = previewView;
                AndroidContinuousScannerConfig activeConfig = currentConfig;
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
                Camera camera = cameraProvider.bindToLifecycle(activity, selector, preview, analysis);
                configureCameraForScanning(camera, activePreviewView);
            } catch (Exception error) {
                listener.onScannerError("Continuous scanner failed: " + error.getMessage());
                stopInternal();
            }
        }, ContextCompat.getMainExecutor(activity));
    }

    private void bindCameraAfterLayout(int generation) {
        PreviewView activePreviewView = previewView;
        if (activePreviewView == null) {
            return;
        }
        activePreviewView.post(() -> bindCamera(generation));
    }

    private void configureCameraForScanning(Camera camera, PreviewView activePreviewView) {
        if (camera == null || activePreviewView == null) {
            return;
        }
        try {
            camera.getCameraControl().setLinearZoom(0f);
        } catch (Exception ignored) {
            // Some vendor camera stacks reject zoom changes while the surface settles.
        }

        activePreviewView.postDelayed(() -> {
            try {
                int width = Math.max(activePreviewView.getWidth(), 1);
                int height = Math.max(activePreviewView.getHeight(), 1);
                MeteringPointFactory factory = new SurfaceOrientedMeteringPointFactory(width, height);
                MeteringPoint center = factory.createPoint(width / 2f, height / 2f);
                FocusMeteringAction action = new FocusMeteringAction.Builder(
                        center,
                        FocusMeteringAction.FLAG_AF | FocusMeteringAction.FLAG_AE
                )
                        .setAutoCancelDuration(3, TimeUnit.SECONDS)
                        .build();
                camera.getCameraControl().startFocusAndMetering(action);
            } catch (Exception ignored) {
                // Focus metering is best effort; scanning still works when unavailable.
            }
        }, 250);
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
        AndroidContinuousScannerConfig config = currentConfig;
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
                listener.onScannerEvent(AndroidContinuousScannerEventBuilder.event(config, code, barcode, now));
            } catch (org.json.JSONException error) {
                listener.onScannerError("Barcode event could not be encoded: " + error.getMessage());
            }
        }
    }

    private BarcodeScannerOptions scannerOptions(JSONArray types) {
        int[] formats = AndroidContinuousScannerConfig.barcodeFormats(types);
        BarcodeScannerOptions.Builder builder = new BarcodeScannerOptions.Builder();
        if (formats.length > 0) {
            int first = formats[0];
            int[] rest = new int[formats.length - 1];
            System.arraycopy(formats, 1, rest, 0, rest.length);
            builder.setBarcodeFormats(first, rest);
        }
        return builder.build();
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
            removeOverlayFromParent();
            overlay = null;
            previewView = null;
            closeButton = null;
            flipButton = null;
            hostedParent = null;
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

    private void removeOverlayFromParent() {
        if (overlay == null) {
            return;
        }
        ViewGroup parent = (ViewGroup) overlay.getParent();
        if (parent != null) {
            parent.removeView(overlay);
        }
    }

}
