package com.ilass.swifthtmlwebviewapp;

import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothManager;
import android.bluetooth.le.AdvertiseCallback;
import android.bluetooth.le.AdvertiseSettings;
import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Build;

import org.altbeacon.beacon.Beacon;
import org.altbeacon.beacon.BeaconParser;
import org.altbeacon.beacon.BeaconTransmitter;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.Locale;

final class AndroidBeaconAdvertiserBridge {
    interface Listener {
        void onBeaconAdvertiseEvent(JSONObject event);
    }

    private static final int IBEACON_MANUFACTURER = 0x004c;
    private static final String IBEACON_LAYOUT = "m:2-3=0215,i:4-19,i:20-21,i:22-23,p:24-24";

    private final Context context;
    private final Listener listener;
    private BeaconTransmitter transmitter;
    private JSONObject activeRequest;
    private AndroidBeaconPayload.BeaconAdvertiseConfig activeConfig;
    private boolean advertising = false;

    AndroidBeaconAdvertiserBridge(Context context, Listener listener) {
        this.context = context.getApplicationContext();
        this.listener = listener;
    }

    boolean hasRequiredPermissions() {
        return AndroidPermissionPolicy.allGranted(
                context,
                AndroidPermissionPolicy.beaconAdvertisePermissions(Build.VERSION.SDK_INT)
        );
    }

    static boolean isSupported(Context context) {
        return context.getPackageManager().hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)
                && BeaconTransmitter.checkTransmissionSupported(context) == BeaconTransmitter.SUPPORTED;
    }

    JSONObject start(JSONObject request) throws JSONException {
        AndroidBeaconPayload.BeaconAdvertiseConfig config = AndroidBeaconPayload.advertiseConfigFrom(request);
        if (config == null) {
            return AndroidBeaconPayload.errorResponse(request, "beaconAdvertiseStart", "Invalid iBeacon parameters. uuid must be a UUID and major/minor must be between 0 and 65535.");
        }
        if (!isBluetoothEnabled()) {
            return AndroidBeaconPayload.errorResponse(request, "beaconAdvertiseStart", "Bluetooth is not enabled or not available.");
        }

        int support = BeaconTransmitter.checkTransmissionSupported(context);
        if (support != BeaconTransmitter.SUPPORTED) {
            return AndroidBeaconPayload.errorResponse(request, "beaconAdvertiseStart", transmissionSupportMessage(support));
        }

        stopInternal();
        activeRequest = AndroidBeaconPayload.copyRequest(request);
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

        return AndroidBeaconPayload.advertiseStartResponse(request, config, "starting");
    }

    JSONObject stop(JSONObject request) throws JSONException {
        stopInternal();
        return AndroidBeaconPayload.advertiseStopResponse(request);
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
            listener.onBeaconAdvertiseEvent(AndroidBeaconPayload.advertiseStateEvent(
                    activeRequest,
                    activeConfig,
                    success,
                    state,
                    advertising,
                    error
            ));
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
}
