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
import android.os.Handler;
import android.os.Looper;
import android.os.ParcelUuid;
import android.util.Base64;

import com.google.zxing.BarcodeFormat;
import com.google.zxing.WriterException;
import com.google.zxing.common.BitMatrix;
import com.google.zxing.qrcode.QRCodeWriter;

import org.json.JSONException;
import org.json.JSONObject;

import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
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

    private static final UUID SERVICE_UUID = AndroidConfigPairingProtocol.SERVICE_UUID;
    private static final UUID COMMAND_UUID = AndroidConfigPairingProtocol.COMMAND_UUID;
    private static final UUID RESPONSE_UUID = AndroidConfigPairingProtocol.RESPONSE_UUID;
    private static final UUID CLIENT_CONFIG_UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");
    private static final long SESSION_LIFETIME_MS = 300000L;
    private static final int SINGLE_NOTIFICATION_LIMIT = 160;
    private static final int CHUNK_PAYLOAD_SIZE = AndroidConfigPairingProtocol.CHUNK_PAYLOAD_SIZE;

    private final Host host;
    private final SecureRandom secureRandom = new SecureRandom();
    private final Handler handler = new Handler(Looper.getMainLooper());
    private BluetoothGattServer gattServer;
    private BluetoothGattCharacteristic responseCharacteristic;
    private BluetoothLeAdvertiser advertiser;
    private final Set<BluetoothDevice> subscribedDevices = new HashSet<>();
    private final Map<String, AndroidConfigPairingProtocol.ChunkAccumulator> targetInboundChunks = new HashMap<>();
    private final Map<String, AndroidConfigPairingProtocol.ChunkAccumulator> centralInboundChunks = new HashMap<>();
    private final ArrayList<byte[]> centralWriteQueue = new ArrayList<>();
    private BluetoothDevice targetDevice;

    private BluetoothLeScanner scanner;
    private BluetoothGatt centralGatt;
    private BluetoothGattCharacteristic centralCommandCharacteristic;
    private AndroidConfigPairingProtocol.PairingTarget pairingTarget;
    private boolean centralWriteInProgress = false;

    private String sessionId = "";
    private String sessionSecret = "";
    private long sessionExpiresAtMs = 0L;

    AndroidConfigPairingBridge(Host host) {
        this.host = host;
    }

    JSONObject startTargetSession(JSONObject request) throws JSONException {
        BluetoothAdapter adapter = bluetoothAdapter();
        if (adapter == null || !adapter.isEnabled()) {
            return AndroidConfigPairingProtocol.errorResponse(request, "configPairingShow", "Bluetooth is not enabled or not available.");
        }

        sessionId = UUID.randomUUID().toString();
        sessionSecret = randomBase64Url(18);
        sessionExpiresAtMs = System.currentTimeMillis() + SESSION_LIFETIME_MS;
        JSONObject identity = targetIdentity();
        String payload = AndroidConfigPairingProtocol.pairingPayload(sessionId, sessionSecret, sessionExpiresAtMs, identity);

        Bitmap qrBitmap;
        try {
            qrBitmap = qrBitmap(payload, 720);
        } catch (WriterException error) {
            return AndroidConfigPairingProtocol.errorResponse(request, "configPairingShow", "Could not generate config pairing QR code.");
        }

        host.showPairingOverlay(payload, qrBitmap, false);
        startGattServer();
        startAdvertising();

        return AndroidConfigPairingProtocol.showResponse(request, payload, sessionExpiresAtMs, identity);
    }

    JSONObject stopTargetSession(JSONObject request) throws JSONException {
        stopTargetSession();
        return AndroidConfigPairingProtocol.acknowledgementResponse(request, "configPairingStop");
    }

    JSONObject connect(JSONObject request) throws JSONException {
        String payload = request.optString("payload", request.optString("pairingPayload", request.optString("code", ""))).trim();
        AndroidConfigPairingProtocol.PairingTarget target = AndroidConfigPairingProtocol.PairingTarget.parse(payload);
        if (target == null) {
            return AndroidConfigPairingProtocol.errorResponse(request, "configPairingConnect", "Invalid config pairing payload.");
        }
        BluetoothAdapter adapter = bluetoothAdapter();
        if (adapter == null || !adapter.isEnabled()) {
            return AndroidConfigPairingProtocol.errorResponse(request, "configPairingConnect", "Bluetooth is not enabled or not available.");
        }

        disconnectCentral();
        pairingTarget = target;
        scanner = adapter.getBluetoothLeScanner();
        if (scanner == null) {
            return AndroidConfigPairingProtocol.errorResponse(request, "configPairingConnect", "BLE scanner is not available.");
        }

        ScanFilter filter = new ScanFilter.Builder().setServiceUuid(new ParcelUuid(target.serviceUuid)).build();
        ScanSettings settings = new ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .build();
        scanner.startScan(singleton(filter), settings, scanCallback);

        return AndroidConfigPairingProtocol.connectResponse(request, target);
    }

    JSONObject disconnect(JSONObject request) throws JSONException {
        disconnectCentral();
        return AndroidConfigPairingProtocol.acknowledgementResponse(request, "configPairingDisconnect");
    }

    JSONObject send(JSONObject request) throws JSONException {
        if (pairingTarget == null || centralGatt == null || centralCommandCharacteristic == null) {
            return AndroidConfigPairingProtocol.errorResponse(request, "configPairingSend", "Config pairing is not ready yet.");
        }

        JSONObject command = AndroidConfigPairingProtocol.commandFromRequest(pairingTarget, request);

        byte[] data = command.toString().getBytes(StandardCharsets.UTF_8);
        CentralWriteResult writeResult = writeCentralCommandData(data);

        return AndroidConfigPairingProtocol.sendResponse(
                request,
                writeResult.started,
                data.length,
                writeResult.chunks,
                command.optString("command"),
                writeResult.error
        );
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
        targetInboundChunks.clear();
        targetDevice = null;
        sessionId = "";
        sessionSecret = "";
        sessionExpiresAtMs = 0L;
        host.hidePairingOverlay();
    }

    private void closePairingPromptAfterConnection() {
        if (advertiser != null) {
            try {
                advertiser.stopAdvertising(advertiseCallback);
            } catch (Exception ignored) {
                // Already stopped.
            }
        }
        advertiser = null;
        host.setPairingOverlayAdvertising(false);
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
        if (targetDevice != null && device != null && !targetDevice.getAddress().equals(device.getAddress())) {
            notifyResponse(device, AndroidConfigPairingProtocol.errorPayload("unknown", "", "Another config device is already connected."));
            return;
        }

        JSONObject command;
        try {
            command = new JSONObject(new String(value, StandardCharsets.UTF_8));
        } catch (JSONException error) {
            notifyResponse(device, AndroidConfigPairingProtocol.errorPayload("unknown", "", "Invalid JSON command."));
            return;
        }
        if ("configPairingChunk".equals(command.optString("action", ""))) {
            handleTargetCommandChunk(device, command);
            return;
        }

        String commandName = AndroidConfigPairingProtocol.nonEmpty(command.optString("command", ""), "statusGet");
        if (!commandIsPaired(command)) {
            notifyResponse(device, AndroidConfigPairingProtocol.errorPayload(commandName, command.optString("requestId", ""), "Invalid or expired config pairing session."));
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
                        notifyResponse(device, AndroidConfigPairingProtocol.errorPayload(commandName, command.optString("requestId", ""), "securityToken is required for settingsSet."));
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
                        notifyResponse(device, AndroidConfigPairingProtocol.errorPayload(commandName, command.optString("requestId", ""), "securityToken is required for wifiConfigure."));
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
                            notifyResponse(device, AndroidConfigPairingProtocol.errorPayload(commandName, command.optString("requestId", ""), error.getMessage()));
                        }
                    });
                    break;
                }
                case "reload": {
                    if (!host.hasValidSecurityToken(command.optString("token", command.optString("securityToken", "")))) {
                        notifyResponse(device, AndroidConfigPairingProtocol.errorPayload(commandName, command.optString("requestId", ""), "securityToken is required for reload."));
                        break;
                    }
                    host.reloadConfiguredUrl();
                    JSONObject response = responsePayload(commandName, command.optString("requestId", ""));
                    response.put("success", true);
                    notifyResponse(device, response);
                    break;
                }
                default:
                    notifyResponse(device, AndroidConfigPairingProtocol.errorPayload(commandName, command.optString("requestId", ""), "Unknown config command: " + commandName + "."));
            }
        } catch (JSONException error) {
            notifyResponse(device, AndroidConfigPairingProtocol.errorPayload(commandName, command.optString("requestId", ""), error.getMessage()));
        }
    }

    private void handleTargetCommandChunk(BluetoothDevice device, JSONObject object) {
        String chunkId = object.optString("id", "");
        int index = object.optInt("i", -1);
        int count = object.optInt("n", 0);
        String encoded = object.optString("d", "");
        if (!AndroidConfigPairingProtocol.isValidChunkEnvelope(object)) {
            notifyResponse(device, AndroidConfigPairingProtocol.errorPayload("unknown", "", "Invalid config command chunk."));
            return;
        }

        byte[] chunk;
        try {
            chunk = Base64.decode(encoded, Base64.NO_WRAP);
        } catch (IllegalArgumentException error) {
            notifyResponse(device, AndroidConfigPairingProtocol.errorPayload("unknown", "", "Invalid config command chunk encoding."));
            return;
        }

        AndroidConfigPairingProtocol.ChunkAccumulator accumulator = targetInboundChunks.get(chunkId);
        if (accumulator == null) {
            accumulator = new AndroidConfigPairingProtocol.ChunkAccumulator(count);
            targetInboundChunks.put(chunkId, accumulator);
        }
        accumulator.chunks.put(index, chunk);
        if (!accumulator.isComplete()) {
            return;
        }

        targetInboundChunks.remove(chunkId);
        handleTargetCommand(device, accumulator.assembled());
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
        if (data.length <= SINGLE_NOTIFICATION_LIMIT) {
            notifyData(device, data);
            return;
        }
        notifyDataInChunks(device, data);
    }

    private void notifyData(BluetoothDevice device, byte[] data) {
        responseCharacteristic.setValue(data);
        gattServer.notifyCharacteristicChanged(device, responseCharacteristic, false);
    }

    private void notifyDataInChunks(BluetoothDevice device, byte[] data) {
        String chunkId = UUID.randomUUID().toString();
        int count = (int) Math.ceil(data.length / (double) CHUNK_PAYLOAD_SIZE);
        for (int index = 0; index < count; index += 1) {
            int start = index * CHUNK_PAYLOAD_SIZE;
            int length = Math.min(CHUNK_PAYLOAD_SIZE, data.length - start);
            byte[] chunk = new byte[length];
            System.arraycopy(data, start, chunk, 0, length);
            JSONObject payload = new JSONObject();
            try {
                payload.put("action", "configPairingChunk");
                payload.put("id", chunkId);
                payload.put("i", index);
                payload.put("n", count);
                payload.put("d", Base64.encodeToString(chunk, Base64.NO_WRAP));
            } catch (JSONException ignored) {
                continue;
            }
            byte[] payloadData = payload.toString().getBytes(StandardCharsets.UTF_8);
            long delayMs = index * 20L;
            handler.postDelayed(() -> {
                if (gattServer != null && responseCharacteristic != null) {
                    notifyData(device, payloadData);
                }
            }, delayMs);
        }
    }

    private JSONObject responsePayload(String command, String requestId) throws JSONException {
        return AndroidConfigPairingProtocol.responsePayload(command, requestId, sessionId);
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
        centralInboundChunks.clear();
        centralWriteQueue.clear();
        centralWriteInProgress = false;
    }

    private final BluetoothGattServerCallback gattServerCallback = new BluetoothGattServerCallback() {
        @Override
        public void onConnectionStateChange(BluetoothDevice device, int status, int newState) {
            emitEvent("target", newState == BluetoothProfile.STATE_CONNECTED ? "connected" : "disconnected", status == BluetoothGatt.GATT_SUCCESS, null);
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                if (targetDevice == null) {
                    targetDevice = device;
                    closePairingPromptAfterConnection();
                } else if (device != null && !targetDevice.getAddress().equals(device.getAddress()) && gattServer != null) {
                    gattServer.cancelConnection(device);
                    emitEvent("target", "connectionRejected", false, "Another config device is already connected.");
                }
            }
            if (newState != BluetoothProfile.STATE_CONNECTED) {
                subscribedDevices.remove(device);
                if (targetDevice != null && device != null && targetDevice.getAddress().equals(device.getAddress())) {
                    targetDevice = null;
                }
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
                handleCentralResponse(response);
            } catch (JSONException error) {
                emitEvent("configurator", "responseParseFailed", false, error.getMessage());
            }
        }

        @Override
        public void onCharacteristicWrite(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic, int status) {
            centralWriteInProgress = false;
            if (status != BluetoothGatt.GATT_SUCCESS) {
                centralWriteQueue.clear();
                emitEvent("configurator", "writeFailed", false, "BLE write failed with status " + status + ".");
                return;
            }
            if (!centralWriteQueue.isEmpty()) {
                centralWriteQueue.remove(0);
            }
            writeNextCentralPayload();
        }
    };

    private void emitEvent(String role, String event, boolean success, String error) {
        try {
            host.sendResult(AndroidConfigPairingProtocol.eventPayload(role, event, success, error));
        } catch (JSONException ignored) {
            // Ignore secondary JSON failure.
        }
    }

    private void handleCentralResponse(JSONObject response) throws JSONException {
        if (!"configPairingChunk".equals(response.optString("action", ""))) {
            host.sendResult(response);
            return;
        }

        String chunkId = response.optString("id", "");
        int index = response.optInt("i", -1);
        int count = response.optInt("n", 0);
        String encoded = response.optString("d", "");
        if (!AndroidConfigPairingProtocol.isValidChunkEnvelope(response)) {
            emitEvent("configurator", "chunkParseFailed", false, "Invalid config response chunk.");
            return;
        }

        byte[] chunk;
        try {
            chunk = Base64.decode(encoded, Base64.NO_WRAP);
        } catch (IllegalArgumentException error) {
            emitEvent("configurator", "chunkParseFailed", false, error.getMessage());
            return;
        }

        AndroidConfigPairingProtocol.ChunkAccumulator accumulator = centralInboundChunks.get(chunkId);
        if (accumulator == null) {
            accumulator = new AndroidConfigPairingProtocol.ChunkAccumulator(count);
            centralInboundChunks.put(chunkId, accumulator);
        }
        accumulator.chunks.put(index, chunk);
        if (!accumulator.isComplete()) {
            return;
        }

        centralInboundChunks.remove(chunkId);
        byte[] assembled = accumulator.assembled();
        try {
            host.sendResult(new JSONObject(new String(assembled, StandardCharsets.UTF_8)));
        } catch (JSONException error) {
            emitEvent("configurator", "chunkAssemblyFailed", false, error.getMessage());
        }
    }

    private CentralWriteResult writeCentralCommandData(byte[] data) {
        if (centralGatt == null || centralCommandCharacteristic == null) {
            return new CentralWriteResult(false, 0, "Config pairing is not ready yet.");
        }

        List<byte[]> payloads;
        if (data.length <= SINGLE_NOTIFICATION_LIMIT) {
            payloads = new ArrayList<>();
            payloads.add(data);
        } else {
            payloads = chunkPayloads(data, SINGLE_NOTIFICATION_LIMIT);
            if (payloads.isEmpty()) {
                return new CentralWriteResult(false, 0, "Config command is too large for the negotiated BLE write length.");
            }
        }

        centralWriteQueue.addAll(payloads);
        boolean started = writeNextCentralPayload();
        return new CentralWriteResult(started, payloads.size(), started ? "" : "Android rejected the BLE characteristic write.");
    }

    private boolean writeNextCentralPayload() {
        if (centralWriteInProgress || centralWriteQueue.isEmpty()) {
            return true;
        }
        if (centralGatt == null || centralCommandCharacteristic == null) {
            centralWriteQueue.clear();
            return false;
        }
        centralCommandCharacteristic.setValue(centralWriteQueue.get(0));
        boolean started = centralGatt.writeCharacteristic(centralCommandCharacteristic);
        centralWriteInProgress = started;
        if (!started) {
            centralWriteQueue.clear();
        }
        return started;
    }

    private List<byte[]> chunkPayloads(byte[] data, int maxPayloadLength) {
        ArrayList<byte[]> payloads = new ArrayList<>();
        String chunkId = UUID.randomUUID().toString();
        int chunkSize = CHUNK_PAYLOAD_SIZE;

        while (chunkSize >= 8) {
            payloads.clear();
            int count = (int) Math.ceil(data.length / (double) chunkSize);
            boolean fits = true;
            for (int index = 0; index < count; index += 1) {
                int start = index * chunkSize;
                int length = Math.min(chunkSize, data.length - start);
                byte[] chunk = new byte[length];
                System.arraycopy(data, start, chunk, 0, length);
                JSONObject payload = new JSONObject();
                try {
                    payload.put("action", "configPairingChunk");
                    payload.put("id", chunkId);
                    payload.put("i", index);
                    payload.put("n", count);
                    payload.put("d", Base64.encodeToString(chunk, Base64.NO_WRAP));
                } catch (JSONException error) {
                    fits = false;
                    break;
                }
                byte[] payloadData = payload.toString().getBytes(StandardCharsets.UTF_8);
                if (payloadData.length > maxPayloadLength) {
                    fits = false;
                    break;
                }
                payloads.add(payloadData);
            }
            if (fits) {
                return new ArrayList<>(payloads);
            }
            chunkSize /= 2;
        }

        payloads.clear();
        return payloads;
    }

    private BluetoothManager bluetoothManager() {
        return (BluetoothManager) host.context().getSystemService(Context.BLUETOOTH_SERVICE);
    }

    private BluetoothAdapter bluetoothAdapter() {
        BluetoothManager manager = bluetoothManager();
        return manager != null ? manager.getAdapter() : null;
    }

    private JSONObject targetIdentity() throws JSONException {
        JSONObject settings = host.settingsSnapshot();
        String deviceName = settings.optString("deviceName", "");
        String deviceUuid = settings.optString("deviceUUID", "");
        String deviceLocation = settings.optString("deviceLocation", "");
        String name = AndroidConfigPairingProtocol.nonEmpty(deviceName, Build.MODEL != null ? Build.MODEL : "Android");
        return AndroidConfigPairingProtocol.identity(name, deviceName, deviceUuid, deviceLocation);
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

    private List<ScanFilter> singleton(ScanFilter filter) {
        ArrayList<ScanFilter> filters = new ArrayList<>();
        filters.add(filter);
        return filters;
    }

    private static final class CentralWriteResult {
        final boolean started;
        final int chunks;
        final String error;

        CentralWriteResult(boolean started, int chunks, String error) {
            this.started = started;
            this.chunks = chunks;
            this.error = error;
        }
    }
}
