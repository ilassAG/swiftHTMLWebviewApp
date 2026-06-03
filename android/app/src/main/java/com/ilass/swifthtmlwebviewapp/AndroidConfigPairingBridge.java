package com.ilass.swifthtmlwebviewapp;

import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCallback;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothGattDescriptor;
import android.bluetooth.BluetoothGattServer;
import android.bluetooth.BluetoothGattServerCallback;
import android.bluetooth.BluetoothGattService;
import android.bluetooth.BluetoothManager;
import android.bluetooth.BluetoothProfile;
import android.bluetooth.le.AdvertiseCallback;
import android.bluetooth.le.AdvertiseData;
import android.bluetooth.le.AdvertiseSettings;
import android.bluetooth.le.BluetoothLeAdvertiser;
import android.bluetooth.le.BluetoothLeScanner;
import android.bluetooth.le.ScanCallback;
import android.bluetooth.le.ScanFilter;
import android.bluetooth.le.ScanResult;
import android.bluetooth.le.ScanSettings;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.os.Build;
import android.os.ParcelUuid;
import android.util.Base64;

import com.google.zxing.BarcodeFormat;
import com.google.zxing.WriterException;
import com.google.zxing.common.BitMatrix;
import com.google.zxing.qrcode.QRCodeWriter;

import org.json.JSONException;
import org.json.JSONObject;

import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;

final class AndroidConfigPairingBridge {
    interface ResultCallback {
        void complete(JSONObject result);
    }

    interface Host {
        Context context();
        void sendResult(JSONObject payload);
        JSONObject settingsSnapshot() throws JSONException;
        JSONObject applySettings(JSONObject values) throws JSONException;
        boolean hasValidSecurityToken(String token);
        void configureWifi(JSONObject request, ResultCallback callback);
        void reloadConfiguredUrl();
        JSONObject deviceSummary() throws JSONException;
        void showPairingOverlay(String payload, Bitmap qrBitmap, boolean advertising);
        void setPairingOverlayAdvertising(boolean advertising);
        void hidePairingOverlay();
    }

    private static final UUID SERVICE_UUID = UUID.fromString("6D8E0F22-9C2D-4E8E-A7D7-2B1D49F48A01");
    private static final UUID COMMAND_UUID = UUID.fromString("6D8E0F22-9C2D-4E8E-A7D7-2B1D49F48A02");
    private static final UUID RESPONSE_UUID = UUID.fromString("6D8E0F22-9C2D-4E8E-A7D7-2B1D49F48A03");
    private static final UUID CLIENT_CONFIG_UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");
    private static final long SESSION_LIFETIME_MS = 300000L;

    private final Host host;
    private final SecureRandom secureRandom = new SecureRandom();
    private BluetoothGattServer gattServer;
    private BluetoothGattCharacteristic responseCharacteristic;
    private BluetoothLeAdvertiser advertiser;
    private final Set<BluetoothDevice> subscribedDevices = new HashSet<>();

    private BluetoothLeScanner scanner;
    private BluetoothGatt centralGatt;
    private BluetoothGattCharacteristic centralCommandCharacteristic;
    private PairingTarget pairingTarget;

    private String sessionId = "";
    private String sessionSecret = "";
    private long sessionExpiresAtMs = 0L;

    AndroidConfigPairingBridge(Host host) {
        this.host = host;
    }

    JSONObject startTargetSession(JSONObject request) throws JSONException {
        BluetoothAdapter adapter = bluetoothAdapter();
        if (adapter == null || !adapter.isEnabled()) {
            return errorResponse(request, "configPairingShow", "Bluetooth is not enabled or not available.");
        }

        sessionId = UUID.randomUUID().toString();
        sessionSecret = randomBase64Url(18);
        sessionExpiresAtMs = System.currentTimeMillis() + SESSION_LIFETIME_MS;
        String payload = pairingPayload(sessionId, sessionSecret, sessionExpiresAtMs);

        Bitmap qrBitmap;
        try {
            qrBitmap = qrBitmap(payload, 720);
        } catch (WriterException error) {
            return errorResponse(request, "configPairingShow", "Could not generate config pairing QR code.");
        }

        host.showPairingOverlay(payload, qrBitmap, false);
        startGattServer();
        startAdvertising();

        JSONObject response = baseResponse(request, "configPairingShow");
        response.put("success", true);
        response.put("payload", payload);
        response.put("expiresAt", sessionExpiresAtMs / 1000L);
        response.put("transport", "ble-gatt");
        response.put("serviceUUID", SERVICE_UUID.toString());
        return response;
    }

    JSONObject stopTargetSession(JSONObject request) throws JSONException {
        stopTargetSession();
        JSONObject response = baseResponse(request, "configPairingStop");
        response.put("success", true);
        return response;
    }

    JSONObject connect(JSONObject request) throws JSONException {
        String payload = request.optString("payload", request.optString("pairingPayload", request.optString("code", ""))).trim();
        PairingTarget target = PairingTarget.parse(payload);
        if (target == null) {
            return errorResponse(request, "configPairingConnect", "Invalid config pairing payload.");
        }
        BluetoothAdapter adapter = bluetoothAdapter();
        if (adapter == null || !adapter.isEnabled()) {
            return errorResponse(request, "configPairingConnect", "Bluetooth is not enabled or not available.");
        }

        disconnectCentral();
        pairingTarget = target;
        scanner = adapter.getBluetoothLeScanner();
        if (scanner == null) {
            return errorResponse(request, "configPairingConnect", "BLE scanner is not available.");
        }

        ScanFilter filter = new ScanFilter.Builder().setServiceUuid(new ParcelUuid(target.serviceUuid)).build();
        ScanSettings settings = new ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .build();
        scanner.startScan(singleton(filter), settings, scanCallback);

        JSONObject response = baseResponse(request, "configPairingConnect");
        response.put("success", true);
        response.put("state", "scanning");
        response.put("serviceUUID", target.serviceUuid.toString());
        response.put("targetName", target.name);
        return response;
    }

    JSONObject disconnect(JSONObject request) throws JSONException {
        disconnectCentral();
        JSONObject response = baseResponse(request, "configPairingDisconnect");
        response.put("success", true);
        return response;
    }

    JSONObject send(JSONObject request) throws JSONException {
        if (pairingTarget == null || centralGatt == null || centralCommandCharacteristic == null) {
            return errorResponse(request, "configPairingSend", "Config pairing is not ready yet.");
        }

        JSONObject command = new JSONObject();
        command.put("sessionId", pairingTarget.sessionId);
        command.put("secret", pairingTarget.secret);
        command.put("requestId", nonEmpty(request.optString("requestId", ""), UUID.randomUUID().toString()));
        command.put("command", nonEmpty(request.optString("command", request.optString("configCommand", "")), "statusGet"));
        if (!request.optString("token", request.optString("securityToken", "")).trim().isEmpty()) {
            command.put("token", request.optString("token", request.optString("securityToken", "")).trim());
        }
        if (request.has("settings")) {
            command.put("settings", request.getJSONObject("settings"));
        }
        if (!request.optString("ssid", "").trim().isEmpty()) {
            command.put("ssid", request.optString("ssid").trim());
        }
        if (!request.optString("passphrase", request.optString("password", "")).trim().isEmpty()) {
            command.put("passphrase", request.optString("passphrase", request.optString("password", "")).trim());
        }
        if (request.has("joinOnce")) {
            command.put("joinOnce", request.optBoolean("joinOnce"));
        }

        byte[] data = command.toString().getBytes(StandardCharsets.UTF_8);
        if (data.length > 512) {
            return errorResponse(request, "configPairingSend", "Config command is too large for one BLE write.");
        }

        centralCommandCharacteristic.setValue(data);
        boolean started = centralGatt.writeCharacteristic(centralCommandCharacteristic);

        JSONObject response = baseResponse(request, "configPairingSend");
        response.put("success", started);
        response.put("state", started ? "sent" : "writeFailed");
        response.put("bytes", data.length);
        response.put("command", command.optString("command"));
        if (!started) {
            response.put("error", "Android rejected the BLE characteristic write.");
        }
        return response;
    }

    void shutdown() {
        stopTargetSession();
        disconnectCentral();
    }

    private void stopTargetSession() {
        if (advertiser != null) {
            try {
                advertiser.stopAdvertising(advertiseCallback);
            } catch (Exception ignored) {
                // Already stopped.
            }
        }
        if (gattServer != null) {
            gattServer.close();
        }
        advertiser = null;
        gattServer = null;
        responseCharacteristic = null;
        subscribedDevices.clear();
        sessionId = "";
        sessionSecret = "";
        sessionExpiresAtMs = 0L;
        host.hidePairingOverlay();
    }

    private void startGattServer() {
        BluetoothManager manager = bluetoothManager();
        if (manager == null) {
            emitEvent("target", "gattUnavailable", false, "Bluetooth manager is unavailable.");
            return;
        }
        if (gattServer != null) {
            gattServer.close();
        }

        gattServer = manager.openGattServer(host.context(), gattServerCallback);
        if (gattServer == null) {
            emitEvent("target", "gattUnavailable", false, "Could not open GATT server.");
            return;
        }

        BluetoothGattService service = new BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY);
        BluetoothGattCharacteristic commandCharacteristic = new BluetoothGattCharacteristic(
                COMMAND_UUID,
                BluetoothGattCharacteristic.PROPERTY_WRITE | BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
                BluetoothGattCharacteristic.PERMISSION_WRITE
        );
        responseCharacteristic = new BluetoothGattCharacteristic(
                RESPONSE_UUID,
                BluetoothGattCharacteristic.PROPERTY_NOTIFY | BluetoothGattCharacteristic.PROPERTY_READ,
                BluetoothGattCharacteristic.PERMISSION_READ
        );
        responseCharacteristic.addDescriptor(new BluetoothGattDescriptor(
                CLIENT_CONFIG_UUID,
                BluetoothGattDescriptor.PERMISSION_READ | BluetoothGattDescriptor.PERMISSION_WRITE
        ));
        service.addCharacteristic(commandCharacteristic);
        service.addCharacteristic(responseCharacteristic);
        gattServer.addService(service);
    }

    private void startAdvertising() {
        BluetoothAdapter adapter = bluetoothAdapter();
        if (adapter == null) {
            emitEvent("target", "advertisingFailed", false, "Bluetooth adapter is unavailable.");
            return;
        }
        advertiser = adapter.getBluetoothLeAdvertiser();
        if (advertiser == null) {
            emitEvent("target", "advertisingFailed", false, "BLE advertising is not supported on this device.");
            return;
        }

        AdvertiseSettings settings = new AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
                .setConnectable(true)
                .build();
        AdvertiseData data = new AdvertiseData.Builder()
                .setIncludeDeviceName(false)
                .addServiceUuid(new ParcelUuid(SERVICE_UUID))
                .build();
        advertiser.startAdvertising(settings, data, advertiseCallback);
    }

    private void handleTargetCommand(BluetoothDevice device, byte[] value) {
        JSONObject command;
        try {
            command = new JSONObject(new String(value, StandardCharsets.UTF_8));
        } catch (JSONException error) {
            notifyResponse(device, errorPayload("unknown", "", "Invalid JSON command."));
            return;
        }

        String commandName = nonEmpty(command.optString("command", ""), "statusGet");
        if (!commandIsPaired(command)) {
            notifyResponse(device, errorPayload(commandName, command.optString("requestId", ""), "Invalid or expired config pairing session."));
            return;
        }

        try {
            switch (commandName) {
                case "statusGet": {
                    JSONObject response = responsePayload(commandName, command.optString("requestId", ""));
                    response.put("success", true);
                    response.put("settings", host.settingsSnapshot());
                    response.put("deviceInfo", host.deviceSummary());
                    notifyResponse(device, response);
                    break;
                }
                case "settingsGet": {
                    JSONObject response = responsePayload(commandName, command.optString("requestId", ""));
                    response.put("success", true);
                    response.put("settings", host.settingsSnapshot());
                    notifyResponse(device, response);
                    break;
                }
                case "settingsSet": {
                    if (!host.hasValidSecurityToken(command.optString("token", command.optString("securityToken", "")))) {
                        notifyResponse(device, errorPayload(commandName, command.optString("requestId", ""), "securityToken is required for settingsSet."));
                        break;
                    }
                    JSONObject values = command.optJSONObject("settings");
                    JSONObject snapshot = host.applySettings(values != null ? values : command);
                    host.reloadConfiguredUrl();
                    JSONObject response = responsePayload(commandName, command.optString("requestId", ""));
                    response.put("success", true);
                    response.put("settings", snapshot);
                    notifyResponse(device, response);
                    break;
                }
                case "wifiConfigure": {
                    if (!host.hasValidSecurityToken(command.optString("token", command.optString("securityToken", "")))) {
                        notifyResponse(device, errorPayload(commandName, command.optString("requestId", ""), "securityToken is required for wifiConfigure."));
                        break;
                    }
                    command.put("action", "wifiConfigure");
                    host.configureWifi(command, result -> {
                        try {
                            JSONObject response = responsePayload(commandName, command.optString("requestId", ""));
                            response.put("success", result.optBoolean("success", false));
                            response.put("wifiResult", result);
                            notifyResponse(device, response);
                        } catch (JSONException error) {
                            notifyResponse(device, errorPayload(commandName, command.optString("requestId", ""), error.getMessage()));
                        }
                    });
                    break;
                }
                case "reload": {
                    if (!host.hasValidSecurityToken(command.optString("token", command.optString("securityToken", "")))) {
                        notifyResponse(device, errorPayload(commandName, command.optString("requestId", ""), "securityToken is required for reload."));
                        break;
                    }
                    host.reloadConfiguredUrl();
                    JSONObject response = responsePayload(commandName, command.optString("requestId", ""));
                    response.put("success", true);
                    notifyResponse(device, response);
                    break;
                }
                default:
                    notifyResponse(device, errorPayload(commandName, command.optString("requestId", ""), "Unknown config command: " + commandName + "."));
            }
        } catch (JSONException error) {
            notifyResponse(device, errorPayload(commandName, command.optString("requestId", ""), error.getMessage()));
        }
    }

    private boolean commandIsPaired(JSONObject command) {
        return System.currentTimeMillis() <= sessionExpiresAtMs
                && sessionId.equals(command.optString("sessionId", command.optString("id", "")))
                && sessionSecret.equals(command.optString("secret", ""));
    }

    private void notifyResponse(BluetoothDevice device, JSONObject response) {
        host.sendResult(response);
        if (gattServer == null || responseCharacteristic == null || device == null) {
            return;
        }
        byte[] data = response.toString().getBytes(StandardCharsets.UTF_8);
        if (data.length > 512) {
            try {
                response = errorPayload(response.optString("command", "unknown"), response.optString("requestId", ""), "Config response is too large for BLE notification.");
                data = response.toString().getBytes(StandardCharsets.UTF_8);
            } catch (Exception ignored) {
                return;
            }
        }
        responseCharacteristic.setValue(data);
        gattServer.notifyCharacteristicChanged(device, responseCharacteristic, false);
    }

    private JSONObject responsePayload(String command, String requestId) throws JSONException {
        JSONObject response = new JSONObject();
        response.put("action", "configPairingResponse");
        response.put("platform", "android");
        response.put("role", "target");
        response.put("command", command);
        response.put("requestId", nonEmpty(requestId, UUID.randomUUID().toString()));
        response.put("sessionId", sessionId);
        return response;
    }

    private JSONObject errorPayload(String command, String requestId, String error) {
        JSONObject response = new JSONObject();
        try {
            response.put("action", "configPairingResponse");
            response.put("platform", "android");
            response.put("role", "target");
            response.put("command", command);
            response.put("requestId", nonEmpty(requestId, UUID.randomUUID().toString()));
            response.put("success", false);
            response.put("error", error != null ? error : "Unknown config pairing error.");
        } catch (JSONException ignored) {
            // Return the partially built response.
        }
        return response;
    }

    private void disconnectCentral() {
        if (scanner != null) {
            try {
                scanner.stopScan(scanCallback);
            } catch (Exception ignored) {
                // Already stopped.
            }
        }
        if (centralGatt != null) {
            centralGatt.disconnect();
            centralGatt.close();
        }
        scanner = null;
        centralGatt = null;
        centralCommandCharacteristic = null;
        pairingTarget = null;
    }

    private final BluetoothGattServerCallback gattServerCallback = new BluetoothGattServerCallback() {
        @Override
        public void onConnectionStateChange(BluetoothDevice device, int status, int newState) {
            emitEvent("target", newState == BluetoothProfile.STATE_CONNECTED ? "connected" : "disconnected", status == BluetoothGatt.GATT_SUCCESS, null);
            if (newState != BluetoothProfile.STATE_CONNECTED) {
                subscribedDevices.remove(device);
            }
        }

        @Override
        public void onCharacteristicWriteRequest(BluetoothDevice device, int requestId, BluetoothGattCharacteristic characteristic, boolean preparedWrite, boolean responseNeeded, int offset, byte[] value) {
            if (COMMAND_UUID.equals(characteristic.getUuid()) && value != null) {
                handleTargetCommand(device, value);
            }
            if (responseNeeded && gattServer != null) {
                gattServer.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, null);
            }
        }

        @Override
        public void onCharacteristicReadRequest(BluetoothDevice device, int requestId, int offset, BluetoothGattCharacteristic characteristic) {
            if (gattServer == null || !RESPONSE_UUID.equals(characteristic.getUuid())) {
                return;
            }
            byte[] value = characteristic.getValue() != null ? characteristic.getValue() : new byte[0];
            gattServer.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value);
        }

        @Override
        public void onDescriptorWriteRequest(BluetoothDevice device, int requestId, BluetoothGattDescriptor descriptor, boolean preparedWrite, boolean responseNeeded, int offset, byte[] value) {
            if (CLIENT_CONFIG_UUID.equals(descriptor.getUuid())) {
                subscribedDevices.add(device);
            }
            if (responseNeeded && gattServer != null) {
                gattServer.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, null);
            }
        }
    };

    private final AdvertiseCallback advertiseCallback = new AdvertiseCallback() {
        @Override
        public void onStartSuccess(AdvertiseSettings settingsInEffect) {
            host.setPairingOverlayAdvertising(true);
            emitEvent("target", "advertising", true, null);
        }

        @Override
        public void onStartFailure(int errorCode) {
            host.setPairingOverlayAdvertising(false);
            emitEvent("target", "advertisingFailed", false, "BLE advertising failed with code " + errorCode + ".");
        }
    };

    private final ScanCallback scanCallback = new ScanCallback() {
        @Override
        public void onScanResult(int callbackType, ScanResult result) {
            if (scanner != null) {
                scanner.stopScan(this);
            }
            BluetoothDevice device = result.getDevice();
            emitEvent("configurator", "discovered", true, device != null ? device.getAddress() : "");
            centralGatt = device.connectGatt(host.context(), false, gattCallback);
        }

        @Override
        public void onScanFailed(int errorCode) {
            emitEvent("configurator", "scanFailed", false, "BLE scan failed with code " + errorCode + ".");
        }
    };

    private final BluetoothGattCallback gattCallback = new BluetoothGattCallback() {
        @Override
        public void onConnectionStateChange(BluetoothGatt gatt, int status, int newState) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                centralGatt = gatt;
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    gatt.requestMtu(512);
                }
                gatt.discoverServices();
                emitEvent("configurator", "connected", status == BluetoothGatt.GATT_SUCCESS, null);
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                emitEvent("configurator", "disconnected", status == BluetoothGatt.GATT_SUCCESS, null);
                centralCommandCharacteristic = null;
            }
        }

        @Override
        public void onServicesDiscovered(BluetoothGatt gatt, int status) {
            BluetoothGattService service = gatt.getService(pairingTarget != null ? pairingTarget.serviceUuid : SERVICE_UUID);
            if (service == null) {
                emitEvent("configurator", "serviceMissing", false, "Config service was not found.");
                return;
            }
            centralCommandCharacteristic = service.getCharacteristic(COMMAND_UUID);
            BluetoothGattCharacteristic response = service.getCharacteristic(RESPONSE_UUID);
            if (response != null) {
                gatt.setCharacteristicNotification(response, true);
                BluetoothGattDescriptor descriptor = response.getDescriptor(CLIENT_CONFIG_UUID);
                if (descriptor != null) {
                    descriptor.setValue(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE);
                    gatt.writeDescriptor(descriptor);
                }
            }
            emitEvent("configurator", "ready", centralCommandCharacteristic != null, centralCommandCharacteristic == null ? "Command characteristic missing." : null);
        }

        @Override
        public void onCharacteristicChanged(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic) {
            if (!RESPONSE_UUID.equals(characteristic.getUuid())) {
                return;
            }
            try {
                JSONObject response = new JSONObject(new String(characteristic.getValue(), StandardCharsets.UTF_8));
                host.sendResult(response);
            } catch (JSONException error) {
                emitEvent("configurator", "responseParseFailed", false, error.getMessage());
            }
        }

        @Override
        public void onCharacteristicWrite(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic, int status) {
            if (status != BluetoothGatt.GATT_SUCCESS) {
                emitEvent("configurator", "writeFailed", false, "BLE write failed with status " + status + ".");
            }
        }
    };

    private void emitEvent(String role, String event, boolean success, String error) {
        try {
            JSONObject payload = new JSONObject();
            payload.put("action", "configPairingEvent");
            payload.put("platform", "android");
            payload.put("role", role);
            payload.put("event", event);
            payload.put("success", success);
            if (error != null && !error.isEmpty()) {
                payload.put("error", error);
            }
            host.sendResult(payload);
        } catch (JSONException ignored) {
            // Ignore secondary JSON failure.
        }
    }

    private BluetoothManager bluetoothManager() {
        return (BluetoothManager) host.context().getSystemService(Context.BLUETOOTH_SERVICE);
    }

    private BluetoothAdapter bluetoothAdapter() {
        BluetoothManager manager = bluetoothManager();
        return manager != null ? manager.getAdapter() : null;
    }

    private String pairingPayload(String id, String secret, long expiresAtMs) {
        String name = Build.MODEL != null ? Build.MODEL : "Android";
        return "swifthtml-config://pair"
                + "?v=1"
                + "&id=" + id
                + "&secret=" + secret
                + "&service=" + SERVICE_UUID
                + "&expires=" + (expiresAtMs / 1000L)
                + "&name=" + urlEncodeMinimal(name);
    }

    private Bitmap qrBitmap(String text, int size) throws WriterException {
        BitMatrix matrix = new QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, size, size);
        Bitmap bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888);
        for (int y = 0; y < size; y += 1) {
            for (int x = 0; x < size; x += 1) {
                bitmap.setPixel(x, y, matrix.get(x, y) ? Color.BLACK : Color.WHITE);
            }
        }
        return bitmap;
    }

    private String randomBase64Url(int byteCount) {
        byte[] bytes = new byte[byteCount];
        secureRandom.nextBytes(bytes);
        return Base64.encodeToString(bytes, Base64.NO_WRAP)
                .replace('+', '-')
                .replace('/', '_')
                .replace("=", "");
    }

    private JSONObject baseResponse(JSONObject request, String action) throws JSONException {
        JSONObject response = new JSONObject();
        response.put("platform", "android");
        response.put("action", action);
        if (request != null && request.has("requestId")) {
            response.put("requestId", request.optString("requestId"));
        }
        return response;
    }

    private JSONObject errorResponse(JSONObject request, String action, String error) throws JSONException {
        JSONObject response = baseResponse(request, action);
        response.put("success", false);
        response.put("error", error);
        return response;
    }

    private String randomId() {
        return UUID.randomUUID().toString();
    }

    private String nonEmpty(String value, String fallback) {
        String trimmed = value != null ? value.trim() : "";
        return trimmed.isEmpty() ? fallback : trimmed;
    }

    private List<ScanFilter> singleton(ScanFilter filter) {
        ArrayList<ScanFilter> filters = new ArrayList<>();
        filters.add(filter);
        return filters;
    }

    private String urlEncodeMinimal(String value) {
        return value == null ? "" : value.replace(" ", "%20");
    }

    private static final class PairingTarget {
        final String sessionId;
        final String secret;
        final UUID serviceUuid;
        final String name;

        private PairingTarget(String sessionId, String secret, UUID serviceUuid, String name) {
            this.sessionId = sessionId;
            this.secret = secret;
            this.serviceUuid = serviceUuid;
            this.name = name;
        }

        static PairingTarget parse(String payload) {
            if (payload == null || !payload.startsWith("swifthtml-config://pair")) {
                return null;
            }
            String query = "";
            int index = payload.indexOf('?');
            if (index >= 0 && index + 1 < payload.length()) {
                query = payload.substring(index + 1);
            }
            JSONObject values = new JSONObject();
            for (String part : query.split("&")) {
                int separator = part.indexOf('=');
                if (separator <= 0) {
                    continue;
                }
                try {
                    String key = URLDecoder.decode(part.substring(0, separator), "UTF-8");
                    String value = URLDecoder.decode(part.substring(separator + 1), "UTF-8");
                    values.put(key, value);
                } catch (Exception ignored) {
                    // Skip malformed query parts.
                }
            }
            String id = values.optString("id", "");
            String secret = values.optString("secret", "");
            if (id.isEmpty() || secret.isEmpty()) {
                return null;
            }
            UUID serviceUuid = SERVICE_UUID;
            try {
                serviceUuid = UUID.fromString(values.optString("service", SERVICE_UUID.toString()).toUpperCase(Locale.US));
            } catch (Exception ignored) {
                // Use default service UUID.
            }
            return new PairingTarget(id, secret, serviceUuid, values.optString("name", ""));
        }
    }
}
