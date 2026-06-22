package com.ilass.swifthtmlwebviewapp;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

final class AndroidPrinterPayload {
    static final String PRINTERCORE_UNLINKED_MESSAGE = "printercore.aar is not linked in this build.";

    private AndroidPrinterPayload() {
    }

    static String selectedPrinterKind(JSONObject request) {
        String kind = nonEmpty(request.optString("kind", ""), "");
        if (!kind.isEmpty()) {
            return kind;
        }
        JSONObject printer = request.optJSONObject("printer");
        if (printer != null) {
            kind = nonEmpty(printer.optString("kind", ""), "");
            if (!kind.isEmpty()) {
                return kind;
            }
        }
        return "epson_epos_xml";
    }

    static String selectedPrinterLabel(JSONObject request, String fallback) {
        JSONObject printer = request.optJSONObject("printer");
        if (printer != null) {
            String label = nonEmpty(printer.optString("label", ""), "");
            if (!label.isEmpty()) {
                return label;
            }
        }
        return fallback;
    }

    static EpsonHelloWorldRequest epsonHelloWorldRequest(JSONObject request) {
        return new EpsonHelloWorldRequest(
                nonEmpty(request.optString("host", ""), ""),
                nonEmpty(request.optString("devid", "local_printer"), "local_printer"),
                request.optLong("timeoutMs", 20000L),
                nonEmpty(request.optString("title", "Hallo Welt"), "Hallo Welt"),
                nonEmpty(request.optString("subtitle", "swiftHTMLWebviewApp"), "swiftHTMLWebviewApp"),
                nonEmpty(request.optString("body", "Android bridge test"), "Android bridge test")
        );
    }

    static JSONObject discoveryOptions(JSONObject request, JSONArray localCIDRs) throws JSONException {
        JSONObject options = new JSONObject(request != null ? request.toString() : "{}");
        if (!hasDiscoveryTargets(options) && localCIDRs != null && localCIDRs.length() > 0) {
            options.put("cidrs", new JSONArray(localCIDRs.toString()));
        }
        return options;
    }

    static JSONObject discoveryUnavailableResponse(JSONObject request, String goCoreVersion) throws JSONException {
        JSONObject response = BridgeResponse.base(request, "printerDiscover");
        response.put("goCoreVersion", goCoreVersion);
        response.put("success", true);
        response.put("available", false);
        response.put("goCoreAvailable", false);
        response.put("message", PRINTERCORE_UNLINKED_MESSAGE);
        response.put("printers", new JSONArray());
        return response;
    }

    static JSONObject discoveryResponse(JSONObject request, JSONObject coreResponse, String goCoreVersion) throws JSONException {
        JSONObject response = BridgeResponse.base(request, "printerDiscover");
        copyFields(coreResponse, response);
        response.put("goCoreVersion", goCoreVersion);
        return response;
    }

    static void appendSunmiInternalPrinter(
            JSONObject response,
            boolean available,
            String model,
            String packageName
    ) throws JSONException {
        if (!available) {
            return;
        }

        JSONArray printers = response.optJSONArray("printers");
        if (printers == null) {
            printers = new JSONArray();
            response.put("printers", printers);
        }
        if (containsPrinterId(printers, "sunmi-internal")) {
            return;
        }

        JSONObject sunmiPrinter = new JSONObject();
        sunmiPrinter.put("id", "sunmi-internal");
        sunmiPrinter.put("kind", "sunmi_internal");
        sunmiPrinter.put("label", "Sunmi interner Drucker");
        sunmiPrinter.put("local", true);
        sunmiPrinter.put("confidence", "confirmed");
        sunmiPrinter.put("provider", "android_aidl");
        sunmiPrinter.put("packageName", packageName);
        sunmiPrinter.put("model", model != null ? model : "");
        printers.put(sunmiPrinter);
    }

    static JSONObject printercoreUnavailableResponse(JSONObject request, String action, String printerKind) throws JSONException {
        JSONObject response = BridgeResponse.unavailable(request, action, PRINTERCORE_UNLINKED_MESSAGE);
        response.put("printerKind", printerKind);
        return response;
    }

    static JSONObject epsonJobResponse(
            JSONObject request,
            String action,
            JSONObject coreResponse,
            String hostAddress,
            String devid,
            String printerLabel,
            String goCoreVersion
    ) throws JSONException {
        JSONObject response = BridgeResponse.base(request, action);
        copyFields(coreResponse, response);
        response.put("host", hostAddress);
        response.put("devid", devid);
        response.put("printerKind", "epson_epos_xml");
        response.put("printerLabel", printerLabel);
        response.put("goCoreVersion", goCoreVersion);
        if (!coreResponse.optBoolean("success", false) && !response.has("error")) {
            response.put("error", nonEmpty(coreResponse.optString("message", ""), "Printer returned an unsuccessful response."));
        }
        return response;
    }

    static JSONObject sunmiJobResponse(
            JSONObject request,
            String action,
            boolean success,
            String message,
            String printerLabel,
            String model,
            String serviceVersion,
            String printerModal,
            String printerVersion
    ) throws JSONException {
        JSONObject response = BridgeResponse.base(request, action);
        response.put("success", success);
        response.put("printerKind", "sunmi_internal");
        response.put("printerLabel", printerLabel);
        response.put("provider", "android_aidl");
        response.put("model", model);
        putNonEmpty(response, "serviceVersion", serviceVersion);
        putNonEmpty(response, "printerModal", printerModal);
        putNonEmpty(response, "printerVersion", printerVersion);
        if (success) {
            response.put("message", message);
        } else {
            response.put("error", message);
        }
        return response;
    }

    private static void copyFields(JSONObject source, JSONObject target) throws JSONException {
        JSONArray names = source.names();
        if (names == null) {
            return;
        }
        for (int i = 0; i < names.length(); i += 1) {
            String name = names.getString(i);
            target.put(name, source.get(name));
        }
    }

    private static String nonEmpty(String value, String fallback) {
        String trimmed = value != null ? value.trim() : "";
        return trimmed.isEmpty() ? fallback : trimmed;
    }

    private static void putNonEmpty(JSONObject target, String key, String value) throws JSONException {
        String trimmed = value != null ? value.trim() : "";
        if (!trimmed.isEmpty()) {
            target.put(key, trimmed);
        }
    }

    private static boolean containsPrinterId(JSONArray printers, String printerId) {
        for (int i = 0; i < printers.length(); i += 1) {
            JSONObject printer = printers.optJSONObject(i);
            if (printer != null && printerId.equals(printer.optString("id", ""))) {
                return true;
            }
        }
        return false;
    }

    private static boolean hasDiscoveryTargets(JSONObject options) {
        return options.has("host")
                || options.has("hosts")
                || options.has("cidr")
                || options.has("cidrs");
    }

    static final class EpsonHelloWorldRequest {
        final String hostAddress;
        final String devid;
        final long timeoutMs;
        final String title;
        final String subtitle;
        final String body;

        private EpsonHelloWorldRequest(
                String hostAddress,
                String devid,
                long timeoutMs,
                String title,
                String subtitle,
                String body
        ) {
            this.hostAddress = hostAddress;
            this.devid = devid;
            this.timeoutMs = timeoutMs;
            this.title = title;
            this.subtitle = subtitle;
            this.body = body;
        }
    }
}
