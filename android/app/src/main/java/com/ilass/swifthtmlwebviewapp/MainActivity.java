package com.ilass.swifthtmlwebviewapp;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.Intent;
import android.content.IntentSender;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.provider.MediaStore;
import android.util.Base64;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

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
import com.ilass.printercore.Printercore;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.util.List;

public class MainActivity extends Activity implements ConfettiView.ActivityHost {
    private static final String DEFAULT_URL = "file:///android_asset/index.html";
    private static final int REQUEST_CAMERA_PERMISSION = 2001;
    private static final int REQUEST_IMAGE_CAPTURE = 2002;
    private static final int REQUEST_DOCUMENT_SCAN = 2003;

    private WebView webView;
    private JSONObject pendingRequest;
    private String pendingAction;
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
                    case "printerEpsonHelloWorld":
                        printEpsonHelloWorld(message);
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

    private void printEpsonHelloWorld(JSONObject message) {
        JSONObject request = new JSONObject();
        try {
            request = new JSONObject(message != null ? message.toString() : "{}");
        } catch (JSONException ignored) {
            // Fall back to an empty request below.
        }

        final JSONObject printRequest = request;
        new Thread(() -> {
            try {
                String host = nonEmpty(printRequest.optString("host", "10.10.10.131"), "10.10.10.131");
                String devid = nonEmpty(printRequest.optString("devid", "local_printer"), "local_printer");
                long timeoutMs = printRequest.optLong("timeoutMs", 20000L);
                String title = nonEmpty(printRequest.optString("title", "Hallo Welt"), "Hallo Welt");
                String subtitle = nonEmpty(printRequest.optString("subtitle", "swiftHTMLWebviewApp"), "swiftHTMLWebviewApp");
                String body = nonEmpty(printRequest.optString("body", "Android bridge test"), "Android bridge test");

                String coreJson = Printercore.printEpsonHelloWorld(host, devid, timeoutMs, title, subtitle, body);
                JSONObject coreResponse = new JSONObject(coreJson);
                JSONObject response = baseResponse(printRequest, "printerEpsonHelloWorld");
                copyFields(coreResponse, response);
                response.put("host", host);
                response.put("devid", devid);
                response.put("goCoreVersion", Printercore.coreVersion());
                if (!coreResponse.optBoolean("success", false) && !response.has("error")) {
                    response.put("error", nonEmpty(coreResponse.optString("message", ""), "Printer returned an unsuccessful response."));
                }
                sendResult(response);
            } catch (Exception error) {
                sendErrorSafe(printRequest, "printerEpsonHelloWorld", "Printer request failed: " + error.getMessage());
            }
        }, "PrintercoreEpsonPrint").start();
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
        }
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
