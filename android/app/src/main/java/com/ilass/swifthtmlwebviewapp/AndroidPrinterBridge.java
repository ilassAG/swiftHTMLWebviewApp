package com.ilass.swifthtmlwebviewapp;

import android.content.ComponentName;
import android.content.Intent;
import android.content.ServiceConnection;
import android.content.pm.ResolveInfo;
import android.os.IBinder;
import android.os.RemoteException;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;

import woyou.aidlservice.jiuiv5.ICallback;
import woyou.aidlservice.jiuiv5.IWoyouService;

final class AndroidPrinterBridge {
    private static final String PRINTERCORE_CLASS_NAME = "com.ilass.printercore.Printercore";
    private static final String SUNMI_SERVICE_ACTION = "woyou.aidlservice.jiuiv5.IWoyouService";
    private static final String SUNMI_SERVICE_PACKAGE = "woyou.aidlservice.jiuiv5";

    interface Host {
        JSONObject baseResponse(JSONObject request, String action) throws JSONException;

        void sendResult(JSONObject payload);

        void sendErrorSafe(JSONObject request, String action, String error);

        JSONArray localPrinterDiscoveryCIDRs();

        void runOnMainThread(Runnable runnable);

        boolean bindPrinterService(Intent intent, ServiceConnection connection);

        void unbindPrinterService(ServiceConnection connection);

        List<ResolveInfo> queryIntentServices(Intent intent);

        String deviceManufacturer();

        String deviceBrand();

        String deviceModel();
    }

    private final Host host;

    AndroidPrinterBridge(Host host) {
        this.host = host;
    }

    void printHelloWorld(JSONObject message) {
        JSONObject request = copyRequest(message);
        String kind = AndroidPrinterPayload.selectedPrinterKind(request);
        if ("sunmi_internal".equals(kind)) {
            printSunmiHelloWorld(request);
            return;
        }
        if ("epson_epos_xml".equals(kind)) {
            printEpsonHelloWorld(request, "printerHelloWorld");
            return;
        }
        if ("escpos_raw".equals(kind)) {
            host.sendErrorSafe(request, "printerHelloWorld", "Raw ESC/POS printing is not implemented in this demo build yet.");
            return;
        }
        host.sendErrorSafe(request, "printerHelloWorld", "Unsupported printer kind: " + kind);
    }

    void printGeneric(JSONObject message) {
        JSONObject request = copyRequest(message);
        String kind = AndroidPrinterPayload.selectedPrinterKind(request);
        if ("sunmi_internal".equals(kind)) {
            printSunmiGeneric(request);
            return;
        }
        if ("epson_epos_xml".equals(kind)) {
            host.sendErrorSafe(request, "printerPrint", "Generic print payloads with QR are implemented for Sunmi internal printers in this build.");
            return;
        }
        if ("escpos_raw".equals(kind)) {
            host.sendErrorSafe(request, "printerPrint", "Raw ESC/POS passthrough is not implemented in this wrapper build yet.");
            return;
        }
        host.sendErrorSafe(request, "printerPrint", "Unsupported printer kind: " + kind);
    }

    void printEpsonHelloWorld(JSONObject message) {
        printEpsonHelloWorld(message, "printerEpsonHelloWorld");
    }

    private void printEpsonHelloWorld(JSONObject message, String responseAction) {
        JSONObject request = copyRequest(message);
        new Thread(() -> {
            try {
                AndroidPrinterPayload.EpsonHelloWorldRequest printRequest =
                        AndroidPrinterPayload.epsonHelloWorldRequest(request);
                String coreJson = printercorePrintEpsonHelloWorld(
                        printRequest.hostAddress,
                        printRequest.devid,
                        printRequest.timeoutMs,
                        printRequest.title,
                        printRequest.subtitle,
                        printRequest.body
                );
                JSONObject coreResponse = new JSONObject(coreJson);
                JSONObject response = AndroidPrinterPayload.epsonJobResponse(
                        request,
                        responseAction,
                        coreResponse,
                        printRequest.hostAddress,
                        printRequest.devid,
                        AndroidPrinterPayload.selectedPrinterLabel(request, "Epson ePOS-Print"),
                        printercoreCoreVersion()
                );
                host.sendResult(response);
            } catch (ClassNotFoundException error) {
                sendPrintercoreUnavailable(request, responseAction, "epson_epos_xml");
            } catch (Exception error) {
                host.sendErrorSafe(request, responseAction, "Printer request failed: " + reflectionMessage(error));
            }
        }, "PrintercoreEpsonPrint").start();
    }

    private void printSunmiHelloWorld(JSONObject message) {
        JSONObject request = copyRequest(message);
        new Thread(() -> {
            try {
                SunmiPrintOutcome outcome = runSunmiPrintJob(request);
                JSONObject response = AndroidPrinterPayload.sunmiJobResponse(
                        request,
                        "printerHelloWorld",
                        outcome.success,
                        outcome.message,
                        AndroidPrinterPayload.selectedPrinterLabel(request, "Sunmi interner Drucker"),
                        host.deviceModel(),
                        outcome.serviceVersion,
                        outcome.printerModal,
                        outcome.printerVersion
                );
                host.sendResult(response);
            } catch (Exception error) {
                host.sendErrorSafe(request, "printerHelloWorld", "Sunmi printer request failed: " + error.getMessage());
            }
        }, "SunmiInternalPrint").start();
    }

    private void printSunmiGeneric(JSONObject message) {
        JSONObject request = copyRequest(message);
        new Thread(() -> {
            try {
                SunmiPrintOutcome outcome = runSunmiPrintJob(request, true);
                JSONObject response = AndroidPrinterPayload.sunmiJobResponse(
                        request,
                        "printerPrint",
                        outcome.success,
                        outcome.message,
                        AndroidPrinterPayload.selectedPrinterLabel(request, "Sunmi interner Drucker"),
                        host.deviceModel(),
                        outcome.serviceVersion,
                        outcome.printerModal,
                        outcome.printerVersion
                );
                host.sendResult(response);
            } catch (Exception error) {
                host.sendErrorSafe(request, "printerPrint", "Sunmi printer request failed: " + error.getMessage());
            }
        }, "SunmiGenericPrint").start();
    }

    private SunmiPrintOutcome runSunmiPrintJob(JSONObject request) {
        return runSunmiPrintJob(request, false);
    }

    private SunmiPrintOutcome runSunmiPrintJob(JSONObject request, boolean genericPayload) {
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

        Intent intent = new Intent(SUNMI_SERVICE_ACTION);
        intent.setPackage(SUNMI_SERVICE_PACKAGE);
        host.runOnMainThread(() -> {
            boolean bound = host.bindPrinterService(intent, connection);
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
            if (genericPayload) {
                return submitSunmiGenericPrintJob(service, request);
            }
            return submitSunmiPrintJob(service, request);
        } catch (InterruptedException error) {
            Thread.currentThread().interrupt();
            return SunmiPrintOutcome.failure("Interrupted while binding Sunmi printer service.");
        } finally {
            if (bindStarted.get()) {
                host.runOnMainThread(() -> host.unbindPrinterService(connection));
            }
        }
    }

    private SunmiPrintOutcome submitSunmiPrintJob(IWoyouService service, JSONObject request) {
        ICallback callback = emptyCallback();

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

    private SunmiPrintOutcome submitSunmiGenericPrintJob(IWoyouService service, JSONObject request) {
        ICallback callback = emptyCallback();

        try {
            String title = nonEmpty(request.optString("title", ""), "Print Job");
            String subtitle = nonEmpty(request.optString("subtitle", ""), "");
            String body = nonEmpty(request.optString("body", ""), "");
            String qr = nonEmpty(request.optString("qr", ""), "");
            int qrSize = Math.max(1, Math.min(16, request.optInt("qrSize", 9)));
            JSONArray lines = request.optJSONArray("lines");

            SunmiPrintOutcome outcome = SunmiPrintOutcome.success("Sunmi print job submitted.");
            outcome.serviceVersion = nonEmpty(service.getServiceVersion(), "");
            outcome.printerModal = nonEmpty(service.getPrinterModal(), "");
            outcome.printerVersion = nonEmpty(service.getPrinterVersion(), "");

            service.printerInit(callback);
            service.setAlignment(1, callback);
            service.printTextWithFont(title + "\n", null, 38f, callback);
            if (!qr.isEmpty()) {
                service.lineWrap(1, callback);
                service.sendRAWData(escposQrCode(qr, qrSize), callback);
                service.lineWrap(1, callback);
            }
            if (!subtitle.isEmpty()) {
                service.printTextWithFont(subtitle + "\n", null, 24f, callback);
            }
            service.lineWrap(1, callback);
            service.setAlignment(0, callback);
            if (lines != null && lines.length() > 0) {
                for (int i = 0; i < lines.length(); i += 1) {
                    String line = lines.optString(i, "");
                    if (!line.trim().isEmpty()) {
                        service.printTextWithFont(line + "\n", null, 23f, callback);
                    }
                }
            } else if (!body.isEmpty()) {
                service.printTextWithFont(body + "\n", null, 23f, callback);
            }
            service.lineWrap(3, callback);
            if (request.optBoolean("beep", false)) {
                service.sendRAWData(new byte[]{0x1B, 0x42, 0x03, 0x02}, callback);
            }
            if (request.optBoolean("cut", false)) {
                service.sendRAWData(new byte[]{0x1D, 0x56, 0x42, 0x00}, callback);
            }
            return outcome;
        } catch (RemoteException error) {
            return SunmiPrintOutcome.failure("Sunmi printer failed: " + error.getMessage());
        }
    }

    private ICallback emptyCallback() {
        return new ICallback.Stub() {
            @Override
            public void onRunResult(boolean isSuccess) {
                // Binder submission is synchronous enough for bridge responses.
            }

            @Override
            public void onReturnString(String result) {
                // Not needed for print payload responses.
            }

            @Override
            public void onRaiseException(int code, String msg) {
                // Sunmi reports detailed printer state asynchronously.
            }

            @Override
            public void onPrintResult(int code, String msg) {
                // Submission success is enough for this wrapper bridge.
            }
        };
    }

    void discoverPrinters(JSONObject message) {
        JSONObject request = copyRequest(message);
        new Thread(() -> {
            try {
                JSONObject response;
                try {
                    JSONObject discoveryOptions = AndroidPrinterPayload.discoveryOptions(
                            request,
                            host.localPrinterDiscoveryCIDRs()
                    );
                    String coreJson = printercoreDiscoverPrinters(discoveryOptions.toString());
                    JSONObject coreResponse = new JSONObject(coreJson);
                    response = AndroidPrinterPayload.discoveryResponse(request, coreResponse, printercoreCoreVersion());
                } catch (ClassNotFoundException error) {
                    response = AndroidPrinterPayload.discoveryUnavailableResponse(request, printercoreCoreVersionFallback());
                }
                AndroidPrinterPayload.appendSunmiInternalPrinter(
                        response,
                        isSunmiInternalPrinterAvailable(),
                        host.deviceModel(),
                        SUNMI_SERVICE_PACKAGE
                );
                host.sendResult(response);
            } catch (Exception error) {
                host.sendErrorSafe(request, "printerDiscover", "Printer discovery failed: " + reflectionMessage(error));
            }
        }, "PrintercoreDiscovery").start();
    }

    private String printercoreCoreVersion() throws Exception {
        Method method = printercoreClass().getMethod("coreVersion");
        return (String) method.invoke(null);
    }

    private String printercoreCoreVersionFallback() {
        try {
            return printercoreCoreVersion();
        } catch (Exception ignored) {
            return "unlinked";
        }
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
            JSONObject response = AndroidPrinterPayload.printercoreUnavailableResponse(request, action, printerKind);
            host.sendResult(response);
        } catch (JSONException error) {
            host.sendErrorSafe(request, action, AndroidPrinterPayload.PRINTERCORE_UNLINKED_MESSAGE);
        }
    }

    private boolean isSunmiInternalPrinterAvailable() {
        boolean looksLikeSunmiDevice = containsIgnoreCase(host.deviceManufacturer(), "sunmi")
                || containsIgnoreCase(host.deviceBrand(), "sunmi")
                || containsIgnoreCase(host.deviceModel(), "sunmi")
                || containsIgnoreCase(host.deviceModel(), "v2s");

        Intent serviceIntent = new Intent(SUNMI_SERVICE_ACTION);
        serviceIntent.setPackage(SUNMI_SERVICE_PACKAGE);
        List<ResolveInfo> services = host.queryIntentServices(serviceIntent);
        return looksLikeSunmiDevice && services != null && !services.isEmpty();
    }

    private static boolean containsIgnoreCase(String haystack, String needle) {
        return haystack != null && needle != null && haystack.toLowerCase(Locale.US).contains(needle.toLowerCase(Locale.US));
    }

    static JSONObject copyRequest(JSONObject message) {
        try {
            return new JSONObject(message != null ? message.toString() : "{}");
        } catch (JSONException ignored) {
            return new JSONObject();
        }
    }

    private static String reflectionMessage(Exception error) {
        Throwable cause = error instanceof InvocationTargetException && error.getCause() != null
                ? error.getCause()
                : error;
        String message = cause.getMessage();
        return message != null && !message.trim().isEmpty() ? message : cause.getClass().getSimpleName();
    }

    private byte[] escposQrCode(String value, int moduleSize) {
        byte[] data = value.getBytes(StandardCharsets.UTF_8);
        int storeLength = data.length + 3;
        int pL = storeLength & 0xff;
        int pH = (storeLength >> 8) & 0xff;
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        writeRaw(out, new byte[]{0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00});
        writeRaw(out, new byte[]{0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, (byte) moduleSize});
        writeRaw(out, new byte[]{0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x30});
        writeRaw(out, new byte[]{0x1D, 0x28, 0x6B, (byte) pL, (byte) pH, 0x31, 0x50, 0x30});
        writeRaw(out, data);
        writeRaw(out, new byte[]{0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30});
        return out.toByteArray();
    }

    private void writeRaw(ByteArrayOutputStream out, byte[] bytes) {
        out.write(bytes, 0, bytes.length);
    }

    private static String nonEmpty(String value, String fallback) {
        String trimmed = value != null ? value.trim() : "";
        return trimmed.isEmpty() ? fallback : trimmed;
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
}
