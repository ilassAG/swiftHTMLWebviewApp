package com.ilass.swifthtmlwebviewapp;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

final class AndroidDeviceInfoPayload {
    private static final int BATTERY_STATUS_CHARGING = 2;
    private static final int BATTERY_STATUS_FULL = 5;
    private static final int BATTERY_PLUGGED_AC = 1;
    private static final int BATTERY_PLUGGED_USB = 2;
    private static final int BATTERY_PLUGGED_WIRELESS = 4;
    private static final int LENS_FACING_FRONT = 0;
    private static final int LENS_FACING_BACK = 1;
    private static final int LENS_FACING_EXTERNAL = 2;

    private AndroidDeviceInfoPayload() {
    }

    static final class Snapshot {
        String name = "";
        String appUUID = "";
        String configuredDeviceName = "";
        String configuredDeviceUUID = "";
        String configuredDeviceLocation = "";
        String osVersion = "";
        int sdkInt = 0;
        String manufacturer = "";
        String brand = "";
        String device = "";
        String model = "";
        String product = "";
        String hardware = "";
        String serialNumber = "";
        String androidId = "";
        String appVersion = "";
        JSONObject battery = new JSONObject();
        JSONObject screen = new JSONObject();
        JSONObject memory = new JSONObject();
        JSONObject network = new JSONObject();
        JSONArray cameras = new JSONArray();
        JSONArray sensors = new JSONArray();
        JSONObject capabilities = new JSONObject();
    }

    static final class DeviceSummary {
        String manufacturer = "";
        String model = "";
        String device = "";
        String osVersion = "";
        int sdkInt = 0;
        String appVersion = "";
        JSONObject wifi = new JSONObject();
    }

    static JSONObject response(JSONObject source, Snapshot snapshot) throws JSONException {
        Snapshot data = snapshot != null ? snapshot : new Snapshot();
        JSONObject response = BridgeResponse.base(source, "deviceInfoGet");
        response.put("success", true);
        response.put("name", stringOrEmpty(data.name));
        response.put("appUUID", stringOrEmpty(data.appUUID));
        response.put("configuredDeviceName", stringOrEmpty(data.configuredDeviceName));
        response.put("configuredDeviceUUID", stringOrEmpty(data.configuredDeviceUUID));
        response.put("configuredDeviceLocation", stringOrEmpty(data.configuredDeviceLocation));
        response.put("os", "Android");
        response.put("osVersion", stringOrEmpty(data.osVersion));
        response.put("sdkInt", data.sdkInt);
        response.put("manufacturer", stringOrEmpty(data.manufacturer));
        response.put("brand", stringOrEmpty(data.brand));
        response.put("device", stringOrEmpty(data.device));
        response.put("model", stringOrEmpty(data.model));
        response.put("product", stringOrEmpty(data.product));
        response.put("hardware", stringOrEmpty(data.hardware));
        response.put("serialNumber", stringOrEmpty(data.serialNumber));
        response.put("androidId", stringOrEmpty(data.androidId));
        response.put("appVersion", stringOrEmpty(data.appVersion));
        response.put("battery", objectOrEmpty(data.battery));
        response.put("screen", objectOrEmpty(data.screen));
        response.put("memory", objectOrEmpty(data.memory));
        response.put("network", objectOrEmpty(data.network));
        response.put("cameras", arrayOrEmpty(data.cameras));
        response.put("sensors", arrayOrEmpty(data.sensors));
        response.put("capabilities", objectOrEmpty(data.capabilities));
        return response;
    }

    static JSONObject configPairingDeviceSummary(DeviceSummary summary) throws JSONException {
        DeviceSummary data = summary != null ? summary : new DeviceSummary();
        JSONObject info = new JSONObject();
        info.put("manufacturer", stringOrEmpty(data.manufacturer));
        info.put("model", stringOrEmpty(data.model));
        info.put("device", stringOrEmpty(data.device));
        info.put("os", "Android");
        info.put("osVersion", stringOrEmpty(data.osVersion));
        info.put("sdkInt", data.sdkInt);
        info.put("appVersion", stringOrEmpty(data.appVersion));
        info.put("wifi", objectOrEmpty(data.wifi));
        return info;
    }

    static JSONObject battery(int level, int scale, int plugged, int status) throws JSONException {
        JSONObject info = new JSONObject();
        info.put("level", level);
        info.put("scale", scale);
        info.put("percent", scale > 0 && level >= 0 ? Math.round((level * 1000f) / scale) / 10f : JSONObject.NULL);
        info.put("charging", status == BATTERY_STATUS_CHARGING || status == BATTERY_STATUS_FULL);
        info.put("plugged", plugged);
        info.put("powerSource", powerSourceName(plugged));
        return info;
    }

    static JSONObject screen(
            int widthPixels,
            int heightPixels,
            float density,
            int densityDpi,
            float scaledDensity
    ) throws JSONException {
        JSONObject screen = new JSONObject();
        screen.put("widthPixels", widthPixels);
        screen.put("heightPixels", heightPixels);
        screen.put("density", density);
        screen.put("densityDpi", densityDpi);
        screen.put("scaledDensity", scaledDensity);
        return screen;
    }

    static JSONObject memory(
            long totalBytes,
            long availableBytes,
            boolean lowMemory,
            long thresholdBytes
    ) throws JSONException {
        JSONObject memory = new JSONObject();
        memory.put("totalBytes", totalBytes);
        memory.put("availableBytes", availableBytes);
        memory.put("lowMemory", lowMemory);
        memory.put("thresholdBytes", thresholdBytes);
        return memory;
    }

    static String powerSourceName(int plugged) {
        if ((plugged & BATTERY_PLUGGED_AC) != 0) {
            return "ac";
        }
        if ((plugged & BATTERY_PLUGGED_USB) != 0) {
            return "usb";
        }
        if ((plugged & BATTERY_PLUGGED_WIRELESS) != 0) {
            return "wireless";
        }
        return "battery";
    }

    static JSONObject camera(String id, Integer lensFacing) throws JSONException {
        JSONObject camera = new JSONObject();
        camera.put("id", stringOrEmpty(id));
        camera.put("lensFacing", lensFacingName(lensFacing));
        return camera;
    }

    static JSONObject sensor(
            String name,
            String vendor,
            int type,
            int version,
            float maximumRange,
            float resolution,
            float powerMilliAmp
    ) throws JSONException {
        JSONObject sensor = new JSONObject();
        sensor.put("name", stringOrEmpty(name));
        sensor.put("vendor", stringOrEmpty(vendor));
        sensor.put("type", type);
        sensor.put("version", version);
        sensor.put("maximumRange", maximumRange);
        sensor.put("resolution", resolution);
        sensor.put("powerMilliAmp", powerMilliAmp);
        return sensor;
    }

    static String lensFacingName(Integer lensFacing) {
        if (lensFacing == null) {
            return "unknown";
        }
        if (lensFacing == LENS_FACING_FRONT) {
            return "front";
        }
        if (lensFacing == LENS_FACING_BACK) {
            return "back";
        }
        if (lensFacing == LENS_FACING_EXTERNAL) {
            return "external";
        }
        return "unknown";
    }

    private static String stringOrEmpty(String value) {
        return value != null ? value : "";
    }

    private static JSONObject objectOrEmpty(JSONObject value) {
        return value != null ? value : new JSONObject();
    }

    private static JSONArray arrayOrEmpty(JSONArray value) {
        return value != null ? value : new JSONArray();
    }
}
