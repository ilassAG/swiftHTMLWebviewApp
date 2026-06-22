package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

public class AndroidPrinterPayloadTest {
    @Test
    public void selectedPrinterKindUsesDirectNestedAndDefaultEpson() throws Exception {
        assertEquals(
                "sunmi_internal",
                AndroidPrinterPayload.selectedPrinterKind(new JSONObject()
                        .put("kind", "sunmi_internal")
                        .put("printer", new JSONObject().put("kind", "epson_epos_xml")))
        );
        assertEquals(
                "escpos_raw",
                AndroidPrinterPayload.selectedPrinterKind(new JSONObject()
                        .put("printer", new JSONObject().put("kind", "escpos_raw")))
        );
        assertEquals("epson_epos_xml", AndroidPrinterPayload.selectedPrinterKind(new JSONObject()));
    }

    @Test
    public void selectedPrinterLabelUsesNestedLabelOrFallback() throws Exception {
        JSONObject request = new JSONObject()
                .put("printer", new JSONObject().put("label", "Front Demo Printer"));

        assertEquals("Front Demo Printer", AndroidPrinterPayload.selectedPrinterLabel(request, "Fallback"));
        assertEquals("Fallback", AndroidPrinterPayload.selectedPrinterLabel(new JSONObject(), "Fallback"));
    }

    @Test
    public void epsonHelloWorldRequestTrimsAndDefaultsFields() throws Exception {
        AndroidPrinterPayload.EpsonHelloWorldRequest request = AndroidPrinterPayload.epsonHelloWorldRequest(
                new JSONObject()
                        .put("host", " 192.168.1.60 ")
                        .put("devid", " ")
                        .put("timeoutMs", 1234L)
                        .put("title", " Bon ")
                        .put("subtitle", " ")
                        .put("body", " Testdruck ")
        );

        assertEquals("192.168.1.60", request.hostAddress);
        assertEquals("local_printer", request.devid);
        assertEquals(1234L, request.timeoutMs);
        assertEquals("Bon", request.title);
        assertEquals("swiftHTMLWebviewApp", request.subtitle);
        assertEquals("Testdruck", request.body);

        AndroidPrinterPayload.EpsonHelloWorldRequest defaults = AndroidPrinterPayload.epsonHelloWorldRequest(
                new JSONObject()
        );

        assertEquals("", defaults.hostAddress);
        assertEquals("local_printer", defaults.devid);
        assertEquals(20000L, defaults.timeoutMs);
        assertEquals("Hallo Welt", defaults.title);
        assertEquals("swiftHTMLWebviewApp", defaults.subtitle);
        assertEquals("Android bridge test", defaults.body);
    }

    @Test
    public void discoveryOptionsAddsLocalCidrsOnlyWhenNoTargetsAreProvided() throws Exception {
        JSONArray localCIDRs = new JSONArray().put("192.168.1.0/24");

        JSONObject withoutTargets = AndroidPrinterPayload.discoveryOptions(
                new JSONObject().put("scanEpson", true),
                localCIDRs
        );
        assertEquals("192.168.1.0/24", withoutTargets.getJSONArray("cidrs").getString(0));
        assertTrue(withoutTargets.getBoolean("scanEpson"));

        JSONObject withHost = AndroidPrinterPayload.discoveryOptions(
                new JSONObject().put("host", "192.168.1.50"),
                localCIDRs
        );
        assertFalse(withHost.has("cidrs"));
        assertEquals("192.168.1.50", withHost.getString("host"));
    }

    @Test
    public void discoveryUnavailableResponseUsesStablePrintercoreEnvelope() throws Exception {
        JSONObject response = AndroidPrinterPayload.discoveryUnavailableResponse(
                new JSONObject().put("requestId", "req-printer"),
                "unlinked"
        );

        assertEquals("android", response.getString("platform"));
        assertEquals("printerDiscover", response.getString("action"));
        assertEquals("req-printer", response.getString("requestId"));
        assertEquals("unlinked", response.getString("goCoreVersion"));
        assertEquals(true, response.getBoolean("success"));
        assertFalse(response.getBoolean("available"));
        assertFalse(response.getBoolean("goCoreAvailable"));
        assertEquals("printercore.aar is not linked in this build.", response.getString("message"));
        assertEquals(0, response.getJSONArray("printers").length());
    }

    @Test
    public void discoveryResponseMergesCoreFieldsAndVersion() throws Exception {
        JSONObject response = AndroidPrinterPayload.discoveryResponse(
                new JSONObject().put("requestId", "req-discover"),
                new JSONObject()
                        .put("success", true)
                        .put("available", true)
                        .put("printers", new JSONArray()
                                .put(new JSONObject()
                                        .put("id", "epson-1")
                                        .put("kind", "epson_epos_xml"))),
                "2.1.0"
        );

        assertEquals("android", response.getString("platform"));
        assertEquals("printerDiscover", response.getString("action"));
        assertEquals("req-discover", response.getString("requestId"));
        assertTrue(response.getBoolean("success"));
        assertTrue(response.getBoolean("available"));
        assertEquals("2.1.0", response.getString("goCoreVersion"));
        assertEquals("epson-1", response.getJSONArray("printers").getJSONObject(0).getString("id"));
    }

    @Test
    public void printercoreUnavailableResponseMarksKindAndAvailability() throws Exception {
        JSONObject response = AndroidPrinterPayload.printercoreUnavailableResponse(
                new JSONObject().put("requestId", "req-print"),
                "printerPrint",
                "epson_epos_xml"
        );

        assertEquals("android", response.getString("platform"));
        assertEquals("printerPrint", response.getString("action"));
        assertEquals("req-print", response.getString("requestId"));
        assertEquals("epson_epos_xml", response.getString("printerKind"));
        assertFalse(response.getBoolean("success"));
        assertFalse(response.getBoolean("available"));
        assertEquals("printercore.aar is not linked in this build.", response.getString("error"));
    }

    @Test
    public void epsonJobResponseMergesCoreFieldsAndBackfillsError() throws Exception {
        JSONObject request = new JSONObject().put("requestId", "req-epson");
        JSONObject success = AndroidPrinterPayload.epsonJobResponse(
                request,
                "printerHelloWorld",
                new JSONObject()
                        .put("success", true)
                        .put("message", "Printed."),
                "192.168.1.20",
                "local_printer",
                "Thekenbon",
                "1.2.3"
        );

        assertEquals("android", success.getString("platform"));
        assertEquals("printerHelloWorld", success.getString("action"));
        assertEquals("req-epson", success.getString("requestId"));
        assertTrue(success.getBoolean("success"));
        assertEquals("Printed.", success.getString("message"));
        assertEquals("192.168.1.20", success.getString("host"));
        assertEquals("local_printer", success.getString("devid"));
        assertEquals("epson_epos_xml", success.getString("printerKind"));
        assertEquals("Thekenbon", success.getString("printerLabel"));
        assertEquals("1.2.3", success.getString("goCoreVersion"));

        JSONObject failed = AndroidPrinterPayload.epsonJobResponse(
                request,
                "printerEpsonHelloWorld",
                new JSONObject()
                        .put("success", false)
                        .put("message", "Offline."),
                "192.168.1.21",
                "backup",
                "Backup",
                "1.2.4"
        );

        assertFalse(failed.getBoolean("success"));
        assertEquals("Offline.", failed.getString("message"));
        assertEquals("Offline.", failed.getString("error"));
    }

    @Test
    public void sunmiJobResponseUsesAidlProviderMetadataAndOutcomeFields() throws Exception {
        JSONObject request = new JSONObject().put("requestId", "req-sunmi");
        JSONObject success = AndroidPrinterPayload.sunmiJobResponse(
                request,
                "printerPrint",
                true,
                "Submitted.",
                "Sunmi Demo Printer",
                "V2s",
                "3.4.5",
                "T2",
                "1.0.0"
        );

        assertEquals("android", success.getString("platform"));
        assertEquals("printerPrint", success.getString("action"));
        assertEquals("req-sunmi", success.getString("requestId"));
        assertTrue(success.getBoolean("success"));
        assertEquals("sunmi_internal", success.getString("printerKind"));
        assertEquals("Sunmi Demo Printer", success.getString("printerLabel"));
        assertEquals("android_aidl", success.getString("provider"));
        assertEquals("V2s", success.getString("model"));
        assertEquals("3.4.5", success.getString("serviceVersion"));
        assertEquals("T2", success.getString("printerModal"));
        assertEquals("1.0.0", success.getString("printerVersion"));
        assertEquals("Submitted.", success.getString("message"));
        assertFalse(success.has("error"));

        JSONObject failed = AndroidPrinterPayload.sunmiJobResponse(
                request,
                "printerHelloWorld",
                false,
                "Sunmi internal printer service is not available.",
                "Sunmi interner Drucker",
                "X",
                "",
                "",
                ""
        );

        assertFalse(failed.getBoolean("success"));
        assertEquals("Sunmi internal printer service is not available.", failed.getString("error"));
        assertFalse(failed.has("serviceVersion"));
        assertFalse(failed.has("message"));
    }

    @Test
    public void appendSunmiInternalPrinterAddsOnlyOneConfirmedLocalPrinter() throws Exception {
        JSONObject response = new JSONObject().put("printers", new JSONArray());

        AndroidPrinterPayload.appendSunmiInternalPrinter(
                response,
                true,
                "V2s",
                "woyou.aidlservice.jiuiv5"
        );
        AndroidPrinterPayload.appendSunmiInternalPrinter(
                response,
                true,
                "V2s",
                "woyou.aidlservice.jiuiv5"
        );

        JSONArray printers = response.getJSONArray("printers");
        assertEquals(1, printers.length());
        JSONObject printer = printers.getJSONObject(0);
        assertEquals("sunmi-internal", printer.getString("id"));
        assertEquals("sunmi_internal", printer.getString("kind"));
        assertEquals("Sunmi interner Drucker", printer.getString("label"));
        assertEquals("confirmed", printer.getString("confidence"));
        assertEquals("android_aidl", printer.getString("provider"));
        assertEquals("woyou.aidlservice.jiuiv5", printer.getString("packageName"));
        assertTrue(printer.getBoolean("local"));
        assertEquals("V2s", printer.getString("model"));
    }

    @Test
    public void appendSunmiInternalPrinterDoesNothingWhenUnavailable() throws Exception {
        JSONObject response = new JSONObject();

        AndroidPrinterPayload.appendSunmiInternalPrinter(
                response,
                false,
                "V2s",
                "woyou.aidlservice.jiuiv5"
        );

        assertFalse(response.has("printers"));
    }
}
