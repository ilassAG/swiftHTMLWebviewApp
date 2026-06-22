package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.json.JSONObject;
import org.junit.Test;

import java.nio.charset.StandardCharsets;

public class AndroidConfigPairingProtocolTest {
    @Test
    public void pairingPayloadRoundTripsIdentityFields() throws Exception {
        JSONObject identity = AndroidConfigPairingProtocol.identity(
                "Demo Tablet 03",
                "Demo Tablet 03",
                "device-123",
                "Hall A / Entrance"
        );

        String payload = AndroidConfigPairingProtocol.pairingPayload(
                "session-1",
                "secret+/=",
                300000L,
                identity
        );
        AndroidConfigPairingProtocol.PairingTarget target = AndroidConfigPairingProtocol.PairingTarget.parse(payload);

        assertNotNull(target);
        assertEquals("session-1", target.sessionId);
        assertEquals("secret+/=", target.secret);
        assertEquals(AndroidConfigPairingProtocol.SERVICE_UUID, target.serviceUuid);
        assertEquals("Demo Tablet 03", target.name);
        assertEquals("Demo Tablet 03", target.deviceName);
        assertEquals("device-123", target.deviceUuid);
        assertEquals("Hall A / Entrance", target.deviceLocation);
        assertEquals("Hall A / Entrance", target.identityPayload().getString("deviceLocation"));
    }

    @Test
    public void pairingTargetParseSupportsLegacyAliasesAndRejectsInvalidPayloads() {
        String payload = "swifthtml-config://pair?id=s&secret=t&device_name=Legacy%20Name&device_uuid=uuid-1&device_location=Bar";
        AndroidConfigPairingProtocol.PairingTarget target = AndroidConfigPairingProtocol.PairingTarget.parse(payload);

        assertNotNull(target);
        assertEquals("Legacy Name", target.deviceName);
        assertEquals("uuid-1", target.deviceUuid);
        assertEquals("Bar", target.deviceLocation);
        assertEquals("Legacy Name", target.name);

        assertNull(AndroidConfigPairingProtocol.PairingTarget.parse("https://example.invalid/?id=s&secret=t"));
        assertNull(AndroidConfigPairingProtocol.PairingTarget.parse("swifthtml-config://pair?id=s"));
    }

    @Test
    public void commandFromRequestUsesDefaultsAliasesAndTrimming() throws Exception {
        AndroidConfigPairingProtocol.PairingTarget target = AndroidConfigPairingProtocol.PairingTarget.parse(
                "swifthtml-config://pair?id=session-1&secret=secret-1"
        );
        JSONObject settings = new JSONObject().put("serverURL", "https://example.invalid/app/");
        JSONObject command = AndroidConfigPairingProtocol.commandFromRequest(target, new JSONObject()
                .put("requestId", "req-1")
                .put("configCommand", "wifiConfigure")
                .put("securityToken", " token ")
                .put("settings", settings)
                .put("ssid", " Standort ")
                .put("password", " pass ")
                .put("joinOnce", true));

        assertEquals("session-1", command.getString("sessionId"));
        assertEquals("secret-1", command.getString("secret"));
        assertEquals("req-1", command.getString("requestId"));
        assertEquals("wifiConfigure", command.getString("command"));
        assertEquals("token", command.getString("token"));
        assertEquals(settings, command.getJSONObject("settings"));
        assertEquals("Standort", command.getString("ssid"));
        assertEquals("pass", command.getString("passphrase"));
        assertTrue(command.getBoolean("joinOnce"));

        JSONObject defaultCommand = AndroidConfigPairingProtocol.commandFromRequest(target, new JSONObject());
        assertEquals("statusGet", defaultCommand.getString("command"));
        assertTrue(defaultCommand.getString("requestId").length() > 0);
    }

    @Test
    public void internalRequestUsesActionAndOptionalSource() throws Exception {
        JSONObject show = AndroidConfigPairingProtocol.internalRequest("configPairingShow", "twoFingerHold");
        JSONObject stop = AndroidConfigPairingProtocol.internalRequest("configPairingStop", "");

        assertEquals("configPairingShow", show.getString("action"));
        assertEquals("twoFingerHold", show.getString("source"));
        assertEquals("configPairingStop", stop.getString("action"));
        assertFalse(stop.has("source"));
    }

    @Test
    public void responseErrorAndEventPayloadsUseBridgeContractShape() throws Exception {
        JSONObject response = AndroidConfigPairingProtocol.responsePayload("settingsGet", "req-2", "session-2");
        assertEquals("configPairingResponse", response.getString("action"));
        assertEquals("android", response.getString("platform"));
        assertEquals("target", response.getString("role"));
        assertEquals("settingsGet", response.getString("command"));
        assertEquals("req-2", response.getString("requestId"));
        assertEquals("session-2", response.getString("sessionId"));

        JSONObject error = AndroidConfigPairingProtocol.errorPayload("reload", "req-3", "no token");
        assertFalse(error.getBoolean("success"));
        assertEquals("reload", error.getString("command"));
        assertEquals("no token", error.getString("error"));

        JSONObject event = AndroidConfigPairingProtocol.eventPayload("configurator", "ready", true, "");
        assertEquals("configPairingEvent", event.getString("action"));
        assertEquals("configurator", event.getString("role"));
        assertEquals("ready", event.getString("event"));
        assertTrue(event.getBoolean("success"));
        assertFalse(event.has("error"));
    }

    @Test
    public void bridgeResponsesUseSharedEnvelopeAndTargetIdentity() throws Exception {
        JSONObject identity = AndroidConfigPairingProtocol.identity(
                "Demo Tablet 03",
                "Demo Tablet 03",
                "device-123",
                "Hall A"
        );
        JSONObject request = new JSONObject()
                .put("requestId", "req-4")
                .put("paymentId", "pay-1");
        JSONObject show = AndroidConfigPairingProtocol.showResponse(
                request,
                "swifthtml-config://pair?id=session-1&secret=secret-1",
                300000L,
                identity
        );

        assertEquals("android", show.getString("platform"));
        assertEquals("configPairingShow", show.getString("action"));
        assertEquals("req-4", show.getString("requestId"));
        assertEquals("pay-1", show.getString("paymentId"));
        assertTrue(show.getBoolean("success"));
        assertEquals("ble-gatt", show.getString("transport"));
        assertEquals(AndroidConfigPairingProtocol.SERVICE_UUID.toString(), show.getString("serviceUUID"));
        assertEquals("Demo Tablet 03", show.getJSONObject("targetIdentity").getString("deviceName"));
        assertEquals("device-123", show.getString("deviceUUID"));

        AndroidConfigPairingProtocol.PairingTarget target = AndroidConfigPairingProtocol.PairingTarget.parse(
                "swifthtml-config://pair?id=session-1&secret=secret-1&deviceName=Demo%20Tablet%2003&deviceUUID=device-123&deviceLocation=Hall%20A"
        );
        JSONObject connect = AndroidConfigPairingProtocol.connectResponse(request, target);
        assertEquals("configPairingConnect", connect.getString("action"));
        assertEquals("scanning", connect.getString("state"));
        assertEquals("Demo Tablet 03", connect.getString("targetName"));
        assertEquals("device-123", connect.getString("deviceUUID"));

        JSONObject ack = AndroidConfigPairingProtocol.acknowledgementResponse(request, "configPairingDisconnect");
        assertEquals("configPairingDisconnect", ack.getString("action"));
        assertEquals("req-4", ack.getString("requestId"));
        assertTrue(ack.getBoolean("success"));
    }

    @Test
    public void sendAndErrorResponsesUseSharedEnvelope() throws Exception {
        JSONObject request = new JSONObject().put("requestId", "req-5");
        JSONObject sent = AndroidConfigPairingProtocol.sendResponse(
                request,
                true,
                42,
                1,
                "settingsGet",
                ""
        );

        assertEquals("configPairingSend", sent.getString("action"));
        assertEquals("req-5", sent.getString("requestId"));
        assertTrue(sent.getBoolean("success"));
        assertEquals("sent", sent.getString("state"));
        assertEquals(42, sent.getInt("bytes"));
        assertEquals(1, sent.getInt("chunks"));
        assertEquals("settingsGet", sent.getString("command"));
        assertFalse(sent.has("error"));

        JSONObject failed = AndroidConfigPairingProtocol.sendResponse(
                request,
                false,
                99,
                3,
                "wifiConfigure",
                "write failed"
        );
        assertFalse(failed.getBoolean("success"));
        assertEquals("writeFailed", failed.getString("state"));
        assertEquals("write failed", failed.getString("error"));

        JSONObject error = AndroidConfigPairingProtocol.errorResponse(
                request,
                "configPairingConnect",
                "Invalid config pairing payload."
        );
        assertEquals("configPairingConnect", error.getString("action"));
        assertEquals("req-5", error.getString("requestId"));
        assertFalse(error.getBoolean("success"));
        assertEquals("Invalid config pairing payload.", error.getString("error"));
    }

    @Test
    public void unknownActionResponseUsesSharedEnvelope() throws Exception {
        JSONObject response = AndroidConfigPairingProtocol.unknownActionResponse(
                new JSONObject()
                        .put("requestId", "req-unknown")
                        .put("action", "configPairingUnsupported")
        );

        assertEquals("android", response.getString("platform"));
        assertEquals("configPairingUnsupported", response.getString("action"));
        assertEquals("req-unknown", response.getString("requestId"));
        assertFalse(response.getBoolean("success"));
        assertEquals("Unknown config pairing action: configPairingUnsupported", response.getString("error"));
    }

    @Test
    public void chunkAccumulatorReassemblesOutOfOrderPayloads() {
        AndroidConfigPairingProtocol.ChunkAccumulator accumulator = new AndroidConfigPairingProtocol.ChunkAccumulator(3);

        accumulator.chunks.put(2, "ld".getBytes(StandardCharsets.UTF_8));
        accumulator.chunks.put(0, "he".getBytes(StandardCharsets.UTF_8));
        assertFalse(accumulator.isComplete());
        accumulator.chunks.put(1, "llo wor".getBytes(StandardCharsets.UTF_8));

        assertTrue(accumulator.isComplete());
        assertArrayEquals("hello world".getBytes(StandardCharsets.UTF_8), accumulator.assembled());
    }

    @Test
    public void chunkEnvelopeValidationRejectsMalformedChunks() throws Exception {
        JSONObject valid = new JSONObject()
                .put("id", "chunk-1")
                .put("i", 0)
                .put("n", 1)
                .put("d", "abc");
        assertTrue(AndroidConfigPairingProtocol.isValidChunkEnvelope(valid));

        assertFalse(AndroidConfigPairingProtocol.isValidChunkEnvelope(new JSONObject(valid.toString()).put("i", 1)));
        assertFalse(AndroidConfigPairingProtocol.isValidChunkEnvelope(new JSONObject(valid.toString()).put("d", "")));
        assertFalse(AndroidConfigPairingProtocol.isValidChunkEnvelope(new JSONObject(valid.toString()).put("id", "")));
    }
}
