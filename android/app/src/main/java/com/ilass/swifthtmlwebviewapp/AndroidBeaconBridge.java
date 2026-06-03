package com.ilass.swifthtmlwebviewapp;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;

import androidx.core.content.ContextCompat;

import org.altbeacon.beacon.Beacon;
import org.altbeacon.beacon.BeaconManager;
import org.altbeacon.beacon.BeaconParser;
import org.altbeacon.beacon.Identifier;
import org.altbeacon.beacon.RangeNotifier;
import org.altbeacon.beacon.Region;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.text.SimpleDateFormat;
import java.util.Collection;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;

final class AndroidBeaconBridge {
    interface Listener {
        void onBeaconEvent(JSONObject event);
    }

    static final String DEFAULT_BEACON_UUID = "7763A937-B779-4D31-A20C-49E83047048F";
    private static final long STALE_AFTER_MS = 4000L;

    private final Context context;
    private final Listener listener;
    private final BeaconManager beaconManager;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Map<String, StableBeacon> stableBeacons = new LinkedHashMap<>();

    private Region region;
    private boolean running = false;

    private final Runnable pruneRunnable = new Runnable() {
        @Override
        public void run() {
            if (!running) {
                return;
            }
            pruneStableBeacons(System.currentTimeMillis());
            sendCurrentBeacons();
            handler.postDelayed(this, 1000L);
        }
    };

    private final RangeNotifier rangeNotifier = (beacons, rangedRegion) -> {
        updateStableBeacons(beacons, System.currentTimeMillis());
        sendCurrentBeacons();
    };

    AndroidBeaconBridge(Context context, Listener listener) {
        this.context = context.getApplicationContext();
        this.listener = listener;
        this.beaconManager = BeaconManager.getInstanceForApplication(this.context);
        this.beaconManager.getBeaconParsers().clear();
        this.beaconManager.getBeaconParsers().add(
                new BeaconParser().setBeaconLayout("m:2-3=0215,i:4-19,i:20-21,i:22-23,p:24-24")
        );
        this.beaconManager.setForegroundScanPeriod(1000L);
        this.beaconManager.setForegroundBetweenScanPeriod(0L);
        try {
            this.beaconManager.updateScanPeriods();
        } catch (Exception ignored) {
            // The manager can still apply the periods after ranging starts.
        }
    }

    boolean hasRequiredPermissions() {
        boolean locationGranted = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION)
                == PackageManager.PERMISSION_GRANTED;
        if (!locationGranted) {
            return false;
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return true;
        }
        return ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED
                && ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED;
    }

    JSONObject start(JSONObject request) throws JSONException {
        String uuid = validUUID(request.optString("uuid", "")) ? request.optString("uuid") : DEFAULT_BEACON_UUID;
        region = new Region("SwiftHTMLWebviewAppBeacons", Identifier.parse(uuid), null, null);
        stableBeacons.clear();

        if (!running) {
            beaconManager.addRangeNotifier(rangeNotifier);
        }
        beaconManager.startRangingBeacons(region);
        running = true;
        handler.removeCallbacks(pruneRunnable);
        handler.postDelayed(pruneRunnable, 1000L);

        JSONObject response = baseResponse(request, "beaconsStart");
        response.put("success", true);
        response.put("uuid", uuid);
        response.put("provider", "android_altbeacon");
        return response;
    }

    JSONObject stop(JSONObject request) throws JSONException {
        stopInternal();
        JSONObject response = baseResponse(request, "beaconsStop");
        response.put("success", true);
        return response;
    }

    void shutdown() {
        stopInternal();
    }

    private void stopInternal() {
        if (running && region != null) {
            try {
                beaconManager.stopRangingBeacons(region);
            } catch (Exception ignored) {
                // Ranging may already be stopped by the OS.
            }
            beaconManager.removeRangeNotifier(rangeNotifier);
        }
        running = false;
        region = null;
        stableBeacons.clear();
        handler.removeCallbacks(pruneRunnable);
    }

    private void updateStableBeacons(Collection<Beacon> beacons, long now) {
        for (Beacon beacon : beacons) {
            if (!isValidReading(beacon)) {
                continue;
            }
            String uuid = beacon.getId1() != null ? beacon.getId1().toString() : "";
            int major = beacon.getId2() != null ? beacon.getId2().toInt() : 0;
            int minor = beacon.getId3() != null ? beacon.getId3().toInt() : 0;
            String key = uuid + ":" + major + ":" + minor;
            StableBeacon stable = stableBeacons.get(key);
            if (stable == null) {
                stable = new StableBeacon(uuid, major, minor);
            }
            stable.accuracy = beacon.getDistance();
            stable.rssi = beacon.getRssi();
            stable.proximity = proximityLabel(beacon.getDistance());
            stable.lastSeenMs = now;
            stableBeacons.put(key, stable);
        }
        pruneStableBeacons(now);
    }

    private void pruneStableBeacons(long now) {
        java.util.Iterator<Map.Entry<String, StableBeacon>> iterator = stableBeacons.entrySet().iterator();
        while (iterator.hasNext()) {
            if (now - iterator.next().getValue().lastSeenMs > STALE_AFTER_MS) {
                iterator.remove();
            }
        }
    }

    private void sendCurrentBeacons() {
        try {
            JSONArray beaconsArray = new JSONArray();
            JSONObject kassaMap = new JSONObject();
            long now = System.currentTimeMillis();
            for (StableBeacon stable : stableBeacons.values()) {
                JSONObject beaconJson = stable.toJson(now);
                beaconsArray.put(beaconJson);
                kassaMap.put(String.valueOf(stable.minor), beaconJson);
            }

            JSONObject event = new JSONObject();
            event.put("platform", "android");
            event.put("action", "beacons");
            event.put("success", true);
            event.put("uuid", region != null && region.getId1() != null ? region.getId1().toString() : DEFAULT_BEACON_UUID);
            event.put("count", beaconsArray.length());
            event.put("beacons", beaconsArray);
            event.put("kassaBeacons", kassaMap);
            event.put("timestamp", timestamp(now));
            listener.onBeaconEvent(event);
        } catch (JSONException ignored) {
            // Ignore malformed telemetry; the next ranging cycle can try again.
        }
    }

    private boolean isValidReading(Beacon beacon) {
        return beacon.getDistance() >= 0
                && beacon.getRssi() != 0
                && beacon.getRssi() != 127
                && beacon.getId1() != null
                && beacon.getId2() != null
                && beacon.getId3() != null;
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

    private static boolean validUUID(String value) {
        try {
            java.util.UUID.fromString(value);
            return true;
        } catch (Exception ignored) {
            return false;
        }
    }

    private static String proximityLabel(double distance) {
        if (distance < 0) {
            return "unknown";
        }
        if (distance <= 0.5) {
            return "immediate";
        }
        if (distance <= 3.0) {
            return "near";
        }
        return "far";
    }

    private static String timestamp(long timeMs) {
        return new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", Locale.US).format(new Date(timeMs));
    }

    private static final class StableBeacon {
        final String uuid;
        final int major;
        final int minor;
        String proximity = "unknown";
        double accuracy = 999.0;
        int rssi = 0;
        long lastSeenMs = 0L;

        StableBeacon(String uuid, int major, int minor) {
            this.uuid = uuid;
            this.major = major;
            this.minor = minor;
        }

        JSONObject toJson(long now) throws JSONException {
            JSONObject json = new JSONObject();
            json.put("proximityUUID", uuid);
            json.put("major", major);
            json.put("minor", minor);
            json.put("proximity", proximity);
            json.put("accuracy", accuracy);
            json.put("rssi", rssi);
            json.put("age", Math.max(0, now - lastSeenMs) / 1000.0);
            return json;
        }
    }
}
