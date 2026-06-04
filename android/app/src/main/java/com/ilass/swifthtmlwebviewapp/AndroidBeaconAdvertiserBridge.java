package com.ilass.swifthtmlwebviewapp;

import android.Manifest;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothManager;
import android.bluetooth.le.AdvertiseCallback;
import android.bluetooth.le.AdvertiseSettings;
import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Build;

import androidx.core.content.ContextCompat;

import org.altbeacon.beacon.Beacon;
import org.altbeacon.beacon.BeaconParser;
import org.altbeacon.beacon.BeaconTransmitter;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.Locale;
import java.util.UUID;

final class AndroidBeaconAdvertiserBridge {
    interface Listener {
        void onBeaconAdvertiseEvent(JSONObject event);
    }

    private static final String DEFAULT_BEACON_UUID = AndroidBeaconBridge.DEFAULT_BEACON_UUID;
    private static final int DEFAULT_MAJOR = 1;
    private static final int DEFAULT_MINOR = 1;
    private static final int DEFAULT_TX_POWER = -59;
    private static final int IBEACON_MANUFACTURER = 0x004c;
    private static final String IBEACON_LAYOUT = "m:2-3=0215,i:4-19,i:20-21,i:22-23,p:24-24";

    private final Context context;
    private final Listener listener;
    private BeaconTransmitter transmitter;
    private JSONObject activeRequest;
    private BeaconAdvertiseConfig activeConfig;
    private boolean advertising = false;

    AndroidBeaconAdvertiserBridge(Context context, Listener listener) {
        this.context = context.getApplicationContext();
        this.listener = listener;
    }

    boolean hasRequiredPermissions() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return true;
        }
        return ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_ADVERTISE) == PackageManager.PERMISSION_GRANTED
                && ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED;
    }

    static boolean isSupported(Context context) {
        return context.getPackageManager().hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)
                && BeaconTransmitter.checkTransmissionSupported(context) == BeaconTransmitter.SUPPORTED;
    }

    JSONObject start(JSONObject request) throws JSONException {
        BeaconAdvertiseConfig config = BeaconAdvertiseConfig.from(request);
        if (config == null) {
            return errorResponse(request, "beaconAdvertiseStart", "Invalid iBeacon parameters. uuid must be a UUID and major/minor must be between 0 and 65535.");
        }
        if (!isBluetoothEnabled()) {
            return errorResponse(request, "beaconAdvertiseStart", "Bluetooth is not enabled or not available.");
        }

        int support = BeaconTransmitter.checkTransmissionSupported(context);
        if (support != BeaconTransmitter.SUPPORTED) {
            return errorResponse(request, "beaconAdvertiseStart", transmissionSupportMessage(support));
        }

        stopInternal();
        activeRequest = request != null ? copy(request) : new JSONObject();
        activeConfig = config;
        transmitter = new BeaconTransmitter(context, new BeaconParser().setBeaconLayout(IBEACON_LAYOUT));

        Beacon beacon = new Beacon.Builder()
                .setId1(config.uuid)
                .setId2(String.valueOf(config.major))
                .setId3(String.valueOf(config.minor))
                .setManufacturer(IBEACON_MANUFACTURER)
                .setTxPower(config.measuredPower)
                .build();

        transmitter.startAdvertising(beacon, advertiseCallback);

        JSONObject response = config.decorate(baseResponse(request, "beaconAdvertiseStart"));
        response.put("success", true);
        response.put("provider", "android_altbeacon_transmitter");
        response.put("state", "starting");
        response.put("advertising", false);
        return response;
    }

    JSONObject stop(JSONObject request) throws JSONException {
        stopInternal();
        JSONObject response = baseResponse(request, "beaconAdvertiseStop");
        response.put("success", true);
        response.put("provider", "android_altbeacon_transmitter");
        response.put("state", "stopped");
        return response;
    }

    void shutdown() {
        stopInternal();
    }

    private void stopInternal() {
        if (transmitter != null) {
            try {
                transmitter.stopAdvertising();
            } catch (Exception ignored) {
                // The Android BLE stack may already have torn the advertiser down.
            }
        }
        transmitter = null;
        advertising = false;
        activeConfig = null;
        activeRequest = null;
    }

    private boolean isBluetoothEnabled() {
        BluetoothManager manager = (BluetoothManager) context.getSystemService(Context.BLUETOOTH_SERVICE);
        BluetoothAdapter adapter = manager != null ? manager.getAdapter() : BluetoothAdapter.getDefaultAdapter();
        return adapter != null && adapter.isEnabled();
    }

    private void emitState(boolean success, String state, String error) {
        if (activeConfig == null) {
            return;
        }
        try {
            JSONObject event = activeConfig.decorate(baseResponse(activeRequest, "beaconAdvertiseStart"));
            event.put("success", success);
            event.put("provider", "android_altbeacon_transmitter");
            event.put("state", state);
            event.put("advertising", advertising);
            if (error != null && !error.isEmpty()) {
                event.put("error", error);
            }
            listener.onBeaconAdvertiseEvent(event);
        } catch (JSONException ignored) {
            // Ignore malformed telemetry; the next command can report state again.
        }
    }

    private final AdvertiseCallback advertiseCallback = new AdvertiseCallback() {
        @Override
        public void onStartSuccess(AdvertiseSettings settingsInEffect) {
            advertising = true;
            emitState(true, "advertising", null);
        }

        @Override
        public void onStartFailure(int errorCode) {
            advertising = false;
            emitState(false, "advertisingFailed", advertiseFailureMessage(errorCode));
        }
    };

    private static JSONObject baseResponse(JSONObject request, String action) throws JSONException {
        JSONObject response = new JSONObject();
        response.put("platform", "android");
        response.put("action", action);
        if (request != null && request.has("requestId")) {
            response.put("requestId", request.optString("requestId"));
        }
        return response;
    }

    private static JSONObject errorResponse(JSONObject request, String action, String error) throws JSONException {
        JSONObject response = baseResponse(request, action);
        response.put("success", false);
        response.put("error", error);
        return response;
    }

    private static JSONObject copy(JSONObject source) {
        try {
            return new JSONObject(source != null ? source.toString() : "{}");
        } catch (JSONException ignored) {
            return new JSONObject();
        }
    }

    private static String advertiseFailureMessage(int errorCode) {
        switch (errorCode) {
            case AdvertiseCallback.ADVERTISE_FAILED_ALREADY_STARTED:
                return "BLE advertising is already started.";
            case AdvertiseCallback.ADVERTISE_FAILED_DATA_TOO_LARGE:
                return "BLE advertising data is too large.";
            case AdvertiseCallback.ADVERTISE_FAILED_FEATURE_UNSUPPORTED:
                return "BLE advertising is not supported on this device.";
            case AdvertiseCallback.ADVERTISE_FAILED_INTERNAL_ERROR:
                return "BLE advertising failed with an internal Android error.";
            case AdvertiseCallback.ADVERTISE_FAILED_TOO_MANY_ADVERTISERS:
                return "Too many BLE advertisers are active on this device.";
            default:
                return String.format(Locale.US, "BLE advertising failed with code %d.", errorCode);
        }
    }

    private static String transmissionSupportMessage(int support) {
        switch (support) {
            case BeaconTransmitter.NOT_SUPPORTED_MIN_SDK:
                return "BLE beacon advertising requires a newer Android version.";
            case BeaconTransmitter.NOT_SUPPORTED_BLE:
                return "Bluetooth LE is not supported on this device.";
            case BeaconTransmitter.NOT_SUPPORTED_CANNOT_GET_ADVERTISER:
                return "Android could not get a Bluetooth LE advertiser.";
            case BeaconTransmitter.NOT_SUPPORTED_CANNOT_GET_ADVERTISER_MULTIPLE_ADVERTISEMENTS:
                return "This device does not support Bluetooth LE multiple advertisements.";
            default:
                return String.format(Locale.US, "BLE beacon advertising is not supported (%d).", support);
        }
    }

    private static final class BeaconAdvertiseConfig {
        final String uuid;
        final int major;
        final int minor;
        final int measuredPower;

        private BeaconAdvertiseConfig(String uuid, int major, int minor, int measuredPower) {
            this.uuid = uuid;
            this.major = major;
            this.minor = minor;
            this.measuredPower = measuredPower;
        }

        static BeaconAdvertiseConfig from(JSONObject request) {
            String uuid = firstNonEmpty(request, "uuid", "beaconUUID", "beaconUuid", "proximityUUID");
            if (uuid.isEmpty()) {
                uuid = DEFAULT_BEACON_UUID;
            }
            try {
                UUID.fromString(uuid);
            } catch (Exception ignored) {
                return null;
            }

            int major = request != null && request.has("major") ? request.optInt("major", -1) : DEFAULT_MAJOR;
            int minor = request != null && request.has("minor") ? request.optInt("minor", -1) : DEFAULT_MINOR;
            if (major < 0 || major > 65535 || minor < 0 || minor > 65535) {
                return null;
            }

            int measuredPower = DEFAULT_TX_POWER;
            if (request != null) {
                if (request.has("measuredPower")) {
                    measuredPower = request.optInt("measuredPower", DEFAULT_TX_POWER);
                } else if (request.has("measuredPowerDbm")) {
                    measuredPower = request.optInt("measuredPowerDbm", DEFAULT_TX_POWER);
                } else if (request.has("txPower")) {
                    measuredPower = request.optInt("txPower", DEFAULT_TX_POWER);
                }
            }
            if (measuredPower < -127 || measuredPower > 20) {
                return null;
            }
            return new BeaconAdvertiseConfig(uuid.toUpperCase(Locale.US), major, minor, measuredPower);
        }

        JSONObject decorate(JSONObject response) throws JSONException {
            response.put("uuid", uuid);
            response.put("major", major);
            response.put("minor", minor);
            response.put("measuredPower", measuredPower);
            return response;
        }

        private static String firstNonEmpty(JSONObject request, String... keys) {
            if (request == null) {
                return "";
            }
            for (String key : keys) {
                String value = request.optString(key, "").trim();
                if (!value.isEmpty()) {
                    return value;
                }
            }
            return "";
        }
    }
}
