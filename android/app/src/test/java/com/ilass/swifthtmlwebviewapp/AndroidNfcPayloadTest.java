package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

import java.nio.charset.StandardCharsets;

public class AndroidNfcPayloadTest {
    @Test
    public void tagPayloadNormalizesIdentifierAndTechnologies() throws Exception {
        JSONObject payload = AndroidNfcPayload.tagPayload(
                new byte[] {0x04, (byte) 0xA1, (byte) 0xB2, 0x03},
                new String[] {"android.nfc.tech.NfcA", "android.nfc.tech.Ndef"},
                true
        );

        assertEquals("04A1B203", payload.getString("identifierHex"));
        assertEquals("BKGyAw==", payload.getString("identifierBase64"));
        assertEquals("NfcA", payload.getJSONArray("technologies").getString(0));
        assertEquals("Ndef", payload.getJSONArray("technologies").getString(1));
        assertTrue(payload.getBoolean("ndefFormatable"));
    }

    @Test
    public void technologyDetailPayloadsUseStableFieldNames() throws Exception {
        JSONObject nfcA = AndroidNfcPayload.nfcAPayload(new byte[] {0x44, 0x00}, 8);
        assertEquals("4400", nfcA.getString("atqaHex"));
        assertEquals(8, nfcA.getInt("sak"));

        JSONObject nfcB = AndroidNfcPayload.nfcBPayload(new byte[] {0x01, 0x02}, new byte[] {0x03});
        assertEquals("0102", nfcB.getString("applicationDataHex"));
        assertEquals("03", nfcB.getString("protocolInfoHex"));

        JSONObject nfcF = AndroidNfcPayload.nfcFPayload(new byte[] {0x10}, new byte[] {0x20, 0x21});
        assertEquals("10", nfcF.getString("manufacturerHex"));
        assertEquals("2021", nfcF.getString("systemCodeHex"));

        JSONObject nfcV = AndroidNfcPayload.nfcVPayload(1, 2);
        assertEquals(1, nfcV.getInt("responseFlags"));
        assertEquals(2, nfcV.getInt("dsfId"));

        JSONObject isoDep = AndroidNfcPayload.isoDepPayload(new byte[] {0x01}, new byte[] {0x02}, true);
        assertEquals("01", isoDep.getString("historicalBytesHex"));
        assertEquals("02", isoDep.getString("hiLayerResponseHex"));
        assertTrue(isoDep.getBoolean("extendedLengthApduSupported"));

        assertEquals(
                "ultralightC",
                AndroidNfcPayload.mifareUltralightPayload(2).getString("type")
        );
        JSONObject classic = AndroidNfcPayload.mifareClassicPayload(1, 1024, 64, 16);
        assertEquals("plus", classic.getString("type"));
        assertEquals(1024, classic.getInt("sizeBytes"));
        assertEquals(64, classic.getInt("blockCount"));
        assertEquals(16, classic.getInt("sectorCount"));
    }

    @Test
    public void ndefPayloadsUseStableCommonShape() throws Exception {
        JSONObject unavailable = AndroidNfcPayload.ndefUnavailablePayload();
        assertFalse(unavailable.getBoolean("available"));
        assertEquals(0, unavailable.getJSONArray("messages").length());
        assertEquals(0, unavailable.getJSONArray("records").length());

        JSONObject metadata = AndroidNfcPayload.ndefMetadataPayload("org.nfcforum.ndef.type2", 512, true, false);
        JSONArray records = new JSONArray()
                .put(AndroidNfcPayload.recordPayload(
                        0,
                        AndroidNfcPayload.TNF_MIME_MEDIA,
                        "text/plain".getBytes(StandardCharsets.UTF_8),
                        new byte[] {0x01},
                        "Hallo".getBytes(StandardCharsets.UTF_8),
                        null,
                        "text/plain"
                ));
        JSONArray messages = new JSONArray().put(AndroidNfcPayload.messagePayload(records));
        AndroidNfcPayload.putNdefMessages(metadata, messages, records);

        assertTrue(metadata.getBoolean("available"));
        assertEquals("org.nfcforum.ndef.type2", metadata.getString("type"));
        assertEquals(512, metadata.getInt("maxSizeBytes"));
        assertTrue(metadata.getBoolean("writable"));
        assertFalse(metadata.getBoolean("canMakeReadOnly"));
        assertEquals(1, metadata.getInt("messageCount"));
        assertEquals(1, metadata.getInt("recordCount"));
        assertEquals(1, metadata.getJSONArray("messages").getJSONObject(0).getInt("recordCount"));
    }

    @Test
    public void textRecordDecodesLanguageAndUtf8Text() throws Exception {
        byte[] payload = new byte[] {0x02, 'd', 'e', 'H', 'a', 'l', 'l', 'o'};
        JSONObject record = AndroidNfcPayload.recordPayload(
                2,
                AndroidNfcPayload.TNF_WELL_KNOWN,
                new byte[] {'T'},
                new byte[] {},
                payload,
                null,
                null
        );

        assertEquals(2, record.getInt("index"));
        assertEquals("nfcWellKnown", record.getString("typeNameFormat"));
        assertEquals("T", record.getString("type"));
        assertEquals("54", record.getString("typeHex"));
        assertEquals("AmRlSGFsbG8=", record.getString("payloadBase64"));
        assertEquals("02646548616C6C6F", record.getString("payloadHex"));
        assertEquals("Hallo", record.getString("text"));
        assertEquals("de", record.getString("languageCode"));
    }

    @Test
    public void nonTextRecordKeepsBinaryFieldsAndOptionalUriMime() throws Exception {
        JSONObject record = AndroidNfcPayload.recordPayload(
                1,
                AndroidNfcPayload.TNF_ABSOLUTE_URI,
                "U".getBytes(StandardCharsets.UTF_8),
                new byte[] {0x10, 0x20},
                "https://example.invalid".getBytes(StandardCharsets.UTF_8),
                "https://example.invalid",
                "text/uri-list"
        );

        assertEquals("absoluteURI", record.getString("typeNameFormat"));
        assertEquals("U", record.getString("type"));
        assertEquals("1020", record.getString("identifierHex"));
        assertEquals("https://example.invalid", record.getString("text"));
        assertEquals("https://example.invalid", record.getString("uri"));
        assertEquals("text/uri-list", record.getString("mimeType"));
    }

    @Test
    public void errorResponseUsesCommonBridgeEnvelope() throws Exception {
        JSONObject response = AndroidNfcPayload.errorResponse(
                new JSONObject().put("requestId", "req-nfc"),
                "NFC is disabled on this device."
        );

        assertEquals("android", response.getString("platform"));
        assertEquals("nfcTagRead", response.getString("action"));
        assertEquals("req-nfc", response.getString("requestId"));
        assertFalse(response.getBoolean("success"));
        assertEquals("NFC is disabled on this device.", response.getString("error"));
    }
}
