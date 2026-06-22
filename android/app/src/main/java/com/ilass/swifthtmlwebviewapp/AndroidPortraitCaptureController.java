package com.ilass.swifthtmlwebviewapp;

import android.Manifest;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.media.Image;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.GridLayout;
import android.widget.ImageButton;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;

import androidx.activity.ComponentActivity;
import androidx.camera.core.Camera;
import androidx.camera.core.CameraSelector;
import androidx.camera.core.ExperimentalGetImage;
import androidx.camera.core.FocusMeteringAction;
import androidx.camera.core.ImageAnalysis;
import androidx.camera.core.ImageCapture;
import androidx.camera.core.ImageCaptureException;
import androidx.camera.core.ImageProxy;
import androidx.camera.core.MeteringPoint;
import androidx.camera.core.MeteringPointFactory;
import androidx.camera.core.Preview;
import androidx.camera.core.SurfaceOrientedMeteringPointFactory;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.camera.view.PreviewView;
import androidx.core.content.ContextCompat;
import androidx.exifinterface.media.ExifInterface;

import com.google.common.util.concurrent.ListenableFuture;
import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.face.Face;
import com.google.mlkit.vision.face.FaceDetection;
import com.google.mlkit.vision.face.FaceDetector;
import com.google.mlkit.vision.face.FaceDetectorOptions;
import com.google.mlkit.vision.segmentation.Segmentation;
import com.google.mlkit.vision.segmentation.Segmenter;
import com.google.mlkit.vision.segmentation.selfie.SelfieSegmenterOptions;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

final class AndroidPortraitCaptureController {
    interface Listener {
        void onPortraitResult(JSONObject payload);
        void onPortraitError(JSONObject request, String action, String message);
    }

    private static final int STATE_IDLE = 0;
    private static final int STATE_READY = 1;
    private static final int STATE_COUNTING_DOWN = 2;
    private static final int STATE_BURST_CAPTURING = 3;
    private static final int STATE_SELECTING = 4;
    private static final int STATE_PROCESSING = 5;
    private static final long FACE_MISS_GRACE_MS = 650;

    private static final class Variant {
        final Bitmap bitmap;
        final int faceCount;

        Variant(Bitmap bitmap, int faceCount) {
            this.bitmap = bitmap;
            this.faceCount = faceCount;
        }
    }

    private final ComponentActivity activity;
    private final Listener listener;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService cameraExecutor = Executors.newSingleThreadExecutor();
    private final ExecutorService analysisExecutor = Executors.newSingleThreadExecutor();

    private AndroidPortraitCaptureRequest request;
    private FrameLayout overlay;
    private PreviewView previewView;
    private TextView statusLabel;
    private TextView countdownLabel;
    private ImageButton captureButton;
    private ImageButton cancelButton;
    private FrameLayout selectionOverlay;
    private FrameLayout processingOverlay;
    private GridLayout selectionGrid;
    private LinearLayout selectionContent;
    private ImageButton retakeButton;
    private ImageButton useButton;
    private ProcessCameraProvider cameraProvider;
    private ImageCapture imageCapture;
    private ImageAnalysis imageAnalysis;
    private FaceDetector faceDetector;
    private int state = STATE_IDLE;
    private int latestFaceCount = 0;
    private long latestRequiredFaceSeenAtMs = 0;
    private long countdownRemainingMs = 0;
    private long countdownTargetMs = 0;
    private final ArrayList<Runnable> scheduledCaptureCallbacks = new ArrayList<>();
    private final ArrayList<Variant> variants = new ArrayList<>();
    private int selectedIndex = 0;
    private int pendingCaptures = 0;

    private final Runnable countdownRunnable = new Runnable() {
        @Override
        public void run() {
            tickCountdown();
        }
    };

    AndroidPortraitCaptureController(ComponentActivity activity, Listener listener) {
        this.activity = activity;
        this.listener = listener;
    }

    boolean hasCameraPermission() {
        return ContextCompat.checkSelfPermission(activity, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED;
    }

    void start(JSONObject message) {
        if (!hasCameraPermission()) {
            listener.onPortraitError(message, "portraitCapture", "Camera permission is required.");
            return;
        }
        stopInternal(false);
        request = AndroidPortraitCaptureRequest.from(message);
        state = STATE_READY;
        latestFaceCount = 0;
        latestRequiredFaceSeenAtMs = 0;
        countdownRemainingMs = 0;
        variants.clear();
        selectedIndex = 0;
        mainHandler.post(() -> {
            ensureOverlay();
            bindCamera();
            updateStatus();
        });
    }

    void shutdown() {
        stopInternal(false);
        cameraExecutor.shutdownNow();
        analysisExecutor.shutdownNow();
    }

    private void ensureOverlay() {
        overlay = new FrameLayout(activity);
        overlay.setBackgroundColor(Color.BLACK);
        overlay.setClickable(true);

        previewView = new PreviewView(activity);
        previewView.setImplementationMode(PreviewView.ImplementationMode.COMPATIBLE);
        previewView.setScaleType(PreviewView.ScaleType.FILL_CENTER);
        overlay.addView(previewView, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
        ));

        cancelButton = iconButton(android.R.drawable.ic_menu_close_clear_cancel, Color.TRANSPARENT, Color.WHITE);
        cancelButton.setOnClickListener(view -> cancel());
        FrameLayout.LayoutParams cancelParams = new FrameLayout.LayoutParams(dp(48), dp(48));
        cancelParams.gravity = Gravity.TOP | Gravity.RIGHT;
        cancelParams.topMargin = dp(14);
        cancelParams.rightMargin = dp(16);
        overlay.addView(cancelButton, cancelParams);

        LinearLayout bottom = new LinearLayout(activity);
        bottom.setOrientation(LinearLayout.VERTICAL);
        bottom.setGravity(Gravity.CENTER);
        bottom.setPadding(dp(20), dp(12), dp(20), dp(22));

        statusLabel = new TextView(activity);
        statusLabel.setTextColor(Color.YELLOW);
        statusLabel.setTextSize(26f);
        statusLabel.setTypeface(Typeface.MONOSPACE, Typeface.BOLD);
        statusLabel.setGravity(Gravity.CENTER);
        bottom.addView(statusLabel, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
        ));

        countdownLabel = new TextView(activity);
        countdownLabel.setTextColor(Color.WHITE);
        countdownLabel.setTextSize(68f);
        countdownLabel.setTypeface(Typeface.MONOSPACE, Typeface.BOLD);
        countdownLabel.setGravity(Gravity.CENTER);
        bottom.addView(countdownLabel, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
        ));

        captureButton = iconButton(android.R.drawable.ic_menu_camera, Color.WHITE, Color.BLACK);
        captureButton.setOnClickListener(view -> startCountdown());
        bottom.addView(captureButton, new LinearLayout.LayoutParams(dp(104), dp(64)));

        FrameLayout.LayoutParams bottomParams = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
        );
        bottomParams.gravity = Gravity.BOTTOM;
        overlay.addView(bottom, bottomParams);

        configureSelectionOverlay();

        activity.addContentView(overlay, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
        ));
    }

    private void configureSelectionOverlay() {
        selectionOverlay = new FrameLayout(activity);
        selectionOverlay.setBackgroundColor(Color.argb(230, 0, 0, 0));
        selectionOverlay.setVisibility(View.GONE);

        selectionContent = new LinearLayout(activity);
        selectionContent.setOrientation(LinearLayout.VERTICAL);
        selectionContent.setGravity(Gravity.CENTER);
        selectionContent.setPadding(dp(18), dp(18), dp(18), dp(18));

        selectionGrid = new GridLayout(activity);
        selectionGrid.setUseDefaultMargins(true);
        selectionContent.addView(selectionGrid);

        LinearLayout actions = new LinearLayout(activity);
        actions.setOrientation(LinearLayout.HORIZONTAL);
        actions.setGravity(Gravity.CENTER);
        actions.setPadding(0, dp(14), 0, 0);

        retakeButton = iconButton(android.R.drawable.ic_menu_revert, Color.argb(40, 255, 255, 255), Color.WHITE);
        retakeButton.setOnClickListener(view -> retake());
        actions.addView(retakeButton, new LinearLayout.LayoutParams(dp(96), dp(56)));

        useButton = iconButton(R.drawable.ic_thumb_up, Color.rgb(76, 217, 100), Color.WHITE);
        useButton.setOnClickListener(view -> useSelected());
        LinearLayout.LayoutParams useParams = new LinearLayout.LayoutParams(dp(96), dp(56));
        useParams.leftMargin = dp(14);
        actions.addView(useButton, useParams);

        selectionContent.addView(actions);
        selectionOverlay.addView(selectionContent, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
        ));
        processingOverlay = new FrameLayout(activity);
        processingOverlay.setBackgroundColor(Color.argb(150, 0, 0, 0));
        processingOverlay.setClickable(true);
        processingOverlay.setVisibility(View.GONE);
        ProgressBar spinner = new ProgressBar(activity);
        spinner.setIndeterminate(true);
        processingOverlay.addView(spinner, new FrameLayout.LayoutParams(dp(56), dp(56), Gravity.CENTER));
        selectionOverlay.addView(processingOverlay, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
        ));
        overlay.addView(selectionOverlay, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
        ));
    }

    private void bindCamera() {
        ListenableFuture<ProcessCameraProvider> providerFuture = ProcessCameraProvider.getInstance(activity);
        providerFuture.addListener(() -> {
            try {
                cameraProvider = providerFuture.get();
                Preview preview = new Preview.Builder().build();
                preview.setSurfaceProvider(previewView.getSurfaceProvider());

                imageCapture = new ImageCapture.Builder()
                        .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                        .setTargetRotation(currentDisplayRotation())
                        .build();

                imageAnalysis = new ImageAnalysis.Builder()
                        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                        .setTargetRotation(currentDisplayRotation())
                        .build();
                imageAnalysis.setAnalyzer(analysisExecutor, this::analyzeImage);

                faceDetector = FaceDetection.getClient(new FaceDetectorOptions.Builder()
                        .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_ACCURATE)
                        .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL)
                        .enableTracking()
                        .build());

                CameraSelector selector = new CameraSelector.Builder()
                        .requireLensFacing("front".equals(request.camera)
                                ? CameraSelector.LENS_FACING_FRONT
                                : CameraSelector.LENS_FACING_BACK)
                        .build();

                cameraProvider.unbindAll();
                Camera camera = cameraProvider.bindToLifecycle(activity, selector, preview, imageCapture, imageAnalysis);
                configureFocus(camera);
            } catch (Exception error) {
                listener.onPortraitError(request.source, request.action, "Portrait camera failed: " + error.getMessage());
                stopInternal(false);
            }
        }, ContextCompat.getMainExecutor(activity));
    }

    private void configureFocus(Camera camera) {
        previewView.postDelayed(() -> {
            try {
                int width = Math.max(previewView.getWidth(), 1);
                int height = Math.max(previewView.getHeight(), 1);
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
                // Best effort only; capture still works without metering support.
            }
        }, 250);
    }

    @ExperimentalGetImage
    private void analyzeImage(ImageProxy imageProxy) {
        Image image = imageProxy.getImage();
        FaceDetector detector = faceDetector;
        AndroidPortraitCaptureRequest activeRequest = request;
        if (image == null || detector == null || activeRequest == null || state == STATE_IDLE || state == STATE_SELECTING || state == STATE_PROCESSING) {
            imageProxy.close();
            return;
        }
        updateCaptureRotation();
        int rotation = imageProxy.getImageInfo().getRotationDegrees();
        InputImage inputImage = InputImage.fromMediaImage(image, rotation);
        int imageWidth = inputImage.getWidth();
        int imageHeight = inputImage.getHeight();
        detector.process(inputImage)
                .addOnSuccessListener(faces -> handleFaceCount(AndroidPortraitFacePolicy.statusFaceCount(faces, imageWidth, imageHeight)))
                .addOnCompleteListener(task -> imageProxy.close());
    }

    private void handleFaceCount(int count) {
        mainHandler.post(() -> {
            if (state == STATE_IDLE || state == STATE_SELECTING || state == STATE_PROCESSING || request == null) {
                return;
            }
            int smoothedCount = smoothedFaceCount(count);
            int previous = latestFaceCount;
            latestFaceCount = smoothedCount;
            if (state == STATE_COUNTING_DOWN && previous != smoothedCount) {
                resetCountdownForFaceMismatch();
                if (latestFaceCount == request.requiredFaces) {
                    resumeCountdownIfNeeded();
                }
                return;
            }
            updateStatus();
            resumeCountdownIfNeeded();
        });
    }

    private int smoothedFaceCount(int detectedCount) {
        AndroidPortraitCaptureRequest activeRequest = request;
        if (activeRequest == null) {
            return detectedCount;
        }
        long now = System.currentTimeMillis();
        if (detectedCount == activeRequest.requiredFaces) {
            latestRequiredFaceSeenAtMs = now;
            return detectedCount;
        }
        if (detectedCount == 0
                && latestFaceCount == activeRequest.requiredFaces
                && now - latestRequiredFaceSeenAtMs <= FACE_MISS_GRACE_MS) {
            return activeRequest.requiredFaces;
        }
        return detectedCount;
    }

    private void startCountdown() {
        if (request == null || state != STATE_READY || latestFaceCount != request.requiredFaces) {
            return;
        }
        variants.clear();
        selectedIndex = 0;
        countdownRemainingMs = request.countdownMs;
        countdownTargetMs = System.currentTimeMillis() + countdownRemainingMs;
        state = STATE_COUNTING_DOWN;
        captureButton.setEnabled(false);
        captureButton.setAlpha(0.48f);
        tickCountdown();
    }

    private void tickCountdown() {
        if (request == null || state != STATE_COUNTING_DOWN) {
            return;
        }
        if (latestFaceCount != request.requiredFaces) {
            resetCountdownForFaceMismatch();
            return;
        }
        long remaining = Math.max(0, countdownTargetMs - System.currentTimeMillis());
        countdownRemainingMs = remaining;
        countdownLabel.setText(remaining > 0 ? String.valueOf((int) Math.ceil(remaining / 1000.0)) : "0");
        if (remaining <= request.preCaptureLeadMs()) {
            mainHandler.removeCallbacks(countdownRunnable);
            beginBurstCapture();
            return;
        }
        mainHandler.postDelayed(countdownRunnable, 50);
    }

    private void resetCountdownForFaceMismatch() {
        mainHandler.removeCallbacks(countdownRunnable);
        state = STATE_READY;
        latestRequiredFaceSeenAtMs = 0;
        countdownRemainingMs = request != null ? request.countdownMs : 0;
        countdownTargetMs = 0;
        countdownLabel.setText("");
        updateStatus();
    }

    private void resumeCountdownIfNeeded() {
        if (request == null
                || state != STATE_READY
                || countdownRemainingMs <= 0
                || latestFaceCount != request.requiredFaces
                || selectionOverlay.getVisibility() == View.VISIBLE) {
            return;
        }
        state = STATE_COUNTING_DOWN;
        countdownTargetMs = System.currentTimeMillis() + countdownRemainingMs;
        captureButton.setEnabled(false);
        captureButton.setAlpha(0.48f);
        tickCountdown();
    }

    private void beginBurstCapture() {
        if (request == null || latestFaceCount != request.requiredFaces) {
            resetCountdownForFaceMismatch();
            return;
        }
        state = STATE_BURST_CAPTURING;
        countdownLabel.setText("0");
        updateStatus();
        long[] offsets = request.captureOffsetsMs();
        pendingCaptures = offsets.length;
        for (int index = 0; index < offsets.length; index += 1) {
            final int expectedIndex = index;
            Runnable callback = () -> captureVariant(expectedIndex);
            scheduledCaptureCallbacks.add(callback);
            mainHandler.postDelayed(callback, Math.max(0, offsets[index]));
        }
    }

    private void captureVariant(int expectedIndex) {
        if (request == null || imageCapture == null || state != STATE_BURST_CAPTURING) {
            return;
        }
        if (latestFaceCount != request.requiredFaces) {
            resetAfterInvalidBurst();
            return;
        }
        try {
            File output = File.createTempFile("portrait-", ".jpg", activity.getCacheDir());
            ImageCapture.OutputFileOptions options = new ImageCapture.OutputFileOptions.Builder(output).build();
            imageCapture.takePicture(options, cameraExecutor, new ImageCapture.OnImageSavedCallback() {
                @Override
                public void onImageSaved(ImageCapture.OutputFileResults outputFileResults) {
                    Bitmap bitmap = decodeCapturedBitmap(output);
                    output.delete();
                    mainHandler.post(() -> handleCapturedBitmap(bitmap));
                }

                @Override
                public void onError(ImageCaptureException exception) {
                    output.delete();
                    mainHandler.post(() -> {
                        listener.onPortraitError(request.source, request.action, "Portrait capture failed: " + exception.getMessage());
                        stopInternal(false);
                    });
                }
            });
        } catch (Exception error) {
            listener.onPortraitError(request.source, request.action, "Portrait capture failed: " + error.getMessage());
            stopInternal(false);
        }
    }

    private Bitmap decodeCapturedBitmap(File file) {
        Bitmap bitmap = BitmapFactory.decodeFile(file.getAbsolutePath());
        if (bitmap == null) {
            return null;
        }
        int rotation = 0;
        try {
            ExifInterface exif = new ExifInterface(file.getAbsolutePath());
            int orientation = exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL);
            if (orientation == ExifInterface.ORIENTATION_ROTATE_90) {
                rotation = 90;
            } else if (orientation == ExifInterface.ORIENTATION_ROTATE_180) {
                rotation = 180;
            } else if (orientation == ExifInterface.ORIENTATION_ROTATE_270) {
                rotation = 270;
            }
        } catch (Exception ignored) {
            rotation = 0;
        }
        return AndroidPortraitImageProcessor.rotateAndMirror(bitmap, rotation, request != null && request.mirrorOutput);
    }

    private void handleCapturedBitmap(Bitmap bitmap) {
        if (request == null || state != STATE_BURST_CAPTURING) {
            return;
        }
        if (bitmap == null) {
            listener.onPortraitError(request.source, request.action, "Portrait capture returned no image.");
            stopInternal(false);
            return;
        }
        variants.add(new Variant(AndroidPortraitImageProcessor.copyToArgb(bitmap), latestFaceCount));
        pendingCaptures = Math.max(0, pendingCaptures - 1);
        if (variants.size() >= request.variationCount || pendingCaptures == 0) {
            showSelection();
        }
    }

    private void resetAfterInvalidBurst() {
        cancelScheduledCaptures();
        variants.clear();
        pendingCaptures = 0;
        state = STATE_READY;
        latestRequiredFaceSeenAtMs = 0;
        countdownRemainingMs = request != null ? request.countdownMs : 0;
        countdownTargetMs = 0;
        countdownLabel.setText("");
        updateStatus();
    }

    private void showSelection() {
        cancelScheduledCaptures();
        state = STATE_SELECTING;
        selectedIndex = request.defaultSelectedIndex();
        countdownLabel.setText("");
        setProcessing(false);
        updateSelectionGrid();
        selectionOverlay.setVisibility(View.VISIBLE);
    }

    private void updateSelectionGrid() {
        selectionGrid.removeAllViews();
        int count = Math.max(1, variants.size());
        boolean landscape = activity.getResources().getDisplayMetrics().widthPixels > activity.getResources().getDisplayMetrics().heightPixels;
        int columns = landscape ? Math.min(count, 4) : Math.min(count, 2);
        selectionGrid.setColumnCount(columns);
        int screenWidth = activity.getResources().getDisplayMetrics().widthPixels;
        int screenHeight = activity.getResources().getDisplayMetrics().heightPixels;
        int availableWidth = screenWidth - dp(48);
        int availableHeight = screenHeight - dp(140);
        int rows = (int) Math.ceil(count / (double) columns);
        int size = Math.max(dp(72), Math.min(landscape ? dp(132) : dp(210), Math.min(availableWidth / columns - dp(12), availableHeight / Math.max(1, rows) - dp(12))));
        for (int i = 0; i < variants.size(); i += 1) {
            ImageButton button = iconButton(0, Color.TRANSPARENT, Color.WHITE);
            button.setImageBitmap(variants.get(i).bitmap);
            button.clearColorFilter();
            button.setScaleType(ImageButton.ScaleType.CENTER_CROP);
            button.setBackground(selectionBorder(i == selectedIndex));
            final int index = i;
            button.setOnClickListener(view -> {
                selectedIndex = index;
                updateSelectionGrid();
            });
            selectionGrid.addView(button, new ViewGroup.LayoutParams(size, size));
        }
    }

    private void retake() {
        setProcessing(false);
        selectionOverlay.setVisibility(View.GONE);
        variants.clear();
        selectedIndex = 0;
        countdownRemainingMs = 0;
        state = STATE_READY;
        updateStatus();
    }

    private void useSelected() {
        if (request == null || state != STATE_SELECTING || variants.isEmpty() || selectedIndex < 0 || selectedIndex >= variants.size()) {
            return;
        }
        state = STATE_PROCESSING;
        setProcessing(true);
        Variant selected = variants.get(selectedIndex);
        processSelectedVariant(selected);
    }

    private void setProcessing(boolean processing) {
        if (processingOverlay != null) {
            processingOverlay.setVisibility(processing ? View.VISIBLE : View.GONE);
        }
        if (retakeButton != null) {
            retakeButton.setEnabled(!processing);
            retakeButton.setAlpha(processing ? 0.4f : 1f);
        }
        if (useButton != null) {
            useButton.setEnabled(!processing);
            useButton.setAlpha(processing ? 0.4f : 1f);
        }
        if (selectionGrid != null) {
            selectionGrid.setEnabled(!processing);
        }
    }

    private void processSelectedVariant(Variant selected) {
        AndroidPortraitCaptureRequest activeRequest = request;
        Bitmap source = selected.bitmap;
        FaceDetector detector = FaceDetection.getClient(new FaceDetectorOptions.Builder()
                .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_ACCURATE)
                .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL)
                .build());
        detector.process(InputImage.fromBitmap(source, 0))
                .addOnSuccessListener(faces -> {
                    Bitmap processed = activeRequest.faceCenteredCrop
                            ? AndroidPortraitImageProcessor.squareFaceCenteredCrop(source, faces)
                            : source;
                    detector.close();
                    if (activeRequest.removeBackground) {
                        removeBackgroundAndFinish(processed, selected.faceCount);
                    } else {
                        finishWithBitmap(processed, false, selected.faceCount);
                    }
                })
                .addOnFailureListener(error -> {
                    detector.close();
                    if (activeRequest.removeBackground) {
                        removeBackgroundAndFinish(source, selected.faceCount);
                    } else {
                        finishWithBitmap(source, false, selected.faceCount);
                    }
                });
    }

    private void removeBackgroundAndFinish(Bitmap source, int detectedFaces) {
        AndroidPortraitCaptureRequest activeRequest = request;
        SelfieSegmenterOptions options = new SelfieSegmenterOptions.Builder()
                .setDetectorMode(SelfieSegmenterOptions.SINGLE_IMAGE_MODE)
                .build();
        Segmenter segmenter = Segmentation.getClient(options);
        segmenter.process(InputImage.fromBitmap(source, 0))
                .addOnSuccessListener(mask -> {
                    Bitmap composited = AndroidPortraitImageProcessor.applySegmentationMask(source, mask, activeRequest);
                    segmenter.close();
                    finishWithBitmap(composited, true, detectedFaces);
                })
                .addOnFailureListener(error -> {
                    segmenter.close();
                    listener.onPortraitError(activeRequest.source, activeRequest.action, "Background removal failed: " + error.getMessage());
                    stopInternal(false);
                });
    }

    private void finishWithBitmap(Bitmap bitmap, boolean backgroundRemoved, int detectedFaces) {
        try {
            String format = request.responseFormat(backgroundRemoved);
            String dataUrl = AndroidPortraitImageProcessor.dataUrl(bitmap, format);
            JSONObject response = AndroidCaptureResponseBuilder.portrait(
                    request,
                    format,
                    dataUrl,
                    backgroundRemoved,
                    selectedIndex,
                    variants.size(),
                    detectedFaces
            );
            listener.onPortraitResult(response);
        } catch (JSONException error) {
            listener.onPortraitError(request.source, request.action, error.getMessage());
        } finally {
            stopInternal(false);
        }
    }

    private void cancel() {
        if (request != null) {
            listener.onPortraitError(request.source, request.action, "Portrait capture was cancelled.");
        }
        stopInternal(false);
    }

    private void stopInternal(boolean keepOverlay) {
        mainHandler.removeCallbacks(countdownRunnable);
        cancelScheduledCaptures();
        state = STATE_IDLE;
        pendingCaptures = 0;
        latestFaceCount = 0;
        latestRequiredFaceSeenAtMs = 0;
        countdownRemainingMs = 0;
        countdownTargetMs = 0;
        variants.clear();
        if (faceDetector != null) {
            faceDetector.close();
            faceDetector = null;
        }
        if (cameraProvider != null) {
            try {
                cameraProvider.unbindAll();
            } catch (Exception ignored) {
                // Ignore camera shutdown races.
            }
            cameraProvider = null;
        }
        imageAnalysis = null;
        if (!keepOverlay && overlay != null) {
            ViewGroup parent = (ViewGroup) overlay.getParent();
            if (parent != null) {
                parent.removeView(overlay);
            }
            overlay = null;
            previewView = null;
            selectionOverlay = null;
            processingOverlay = null;
        }
        request = null;
    }

    private void cancelScheduledCaptures() {
        for (Runnable callback : scheduledCaptureCallbacks) {
            mainHandler.removeCallbacks(callback);
        }
        scheduledCaptureCallbacks.clear();
    }

    private void updateStatus() {
        if (request == null || statusLabel == null || captureButton == null) {
            return;
        }
        boolean valid = latestFaceCount == request.requiredFaces;
        statusLabel.setText(latestFaceCount + "/" + request.requiredFaces);
        statusLabel.setTextColor(valid ? Color.rgb(76, 217, 100) : Color.rgb(255, 204, 0));
        boolean enabled = valid && state == STATE_READY && selectionOverlay.getVisibility() != View.VISIBLE;
        captureButton.setEnabled(enabled);
        captureButton.setAlpha(enabled ? 1f : 0.48f);
    }

    private ImageButton iconButton(int imageResource, int backgroundColor, int tintColor) {
        ImageButton button = new ImageButton(activity);
        if (imageResource != 0) {
            button.setImageResource(imageResource);
            button.setColorFilter(tintColor);
        }
        button.setBackground(roundedBackground(backgroundColor, dp(16), 0, 0));
        button.setPadding(dp(12), dp(12), dp(12), dp(12));
        return button;
    }

    private void updateCaptureRotation() {
        int rotation = currentDisplayRotation();
        if (imageCapture != null) {
            imageCapture.setTargetRotation(rotation);
        }
        if (imageAnalysis != null) {
            imageAnalysis.setTargetRotation(rotation);
        }
    }

    private int currentDisplayRotation() {
        return activity.getWindowManager().getDefaultDisplay().getRotation();
    }

    private GradientDrawable roundedBackground(int color, int radius, int strokeColor, int strokeWidth) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(color);
        drawable.setCornerRadius(radius);
        if (strokeWidth > 0) {
            drawable.setStroke(strokeWidth, strokeColor);
        }
        return drawable;
    }

    private GradientDrawable selectionBorder(boolean selected) {
        return roundedBackground(Color.TRANSPARENT, dp(12), selected ? Color.WHITE : Color.argb(90, 255, 255, 255), selected ? dp(4) : dp(1));
    }

    private int dp(int value) {
        return Math.round(value * activity.getResources().getDisplayMetrics().density);
    }
}
