package com.ilass.swifthtmlwebviewapp;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.util.Locale;

final class AndroidNfcPayload {
    static final short TNF_EMPTY = 0;
    static final short TNF_WELL_KNOWN = 1;
    static final short TNF_MIME_MEDIA = 2;
    static final short TNF_ABSOLUTE_URI = 3;
    static final short TNF_EXTERNAL_TYPE = 4;
    static final short TNF_UNKNOWN = 5;
    static final short TNF_UNCHANGED = 6;

    private static final byte[] RTD_TEXT = new byte[] {'T'};
    private static final char[] BASE64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".toCharArray();

    private AndroidNfcPayload() {
    }

    static JSONObject baseResponse(JSONObject request) throws JSONException {
        return BridgeResponse.base(request, "nfcTagRead");
    }

    static JSONObject errorResponse(JSONObject request, String message) throws JSONException {
        return BridgeResponse.error(request, "nfcTagRead", message != null ? message : "Unknown NFC error.");
    }

    static JSONObject tagPayload(byte[] identifier, String[] techList, boolean ndefFormatable) throws JSONException {
        JSONObject payload = new JSONObject();
        payload.put("identifierHex", hex(identifier));
        payload.put("identifierBase64", base64(identifier));
        JSONArray technologies = new JSONArray();
        if (techList != null) {
            for (String tech : techList) {
                technologies.put(shortTechName(tech));
            }
        }
        payload.put("technologies", technologies);
        payload.put("ndefFormatable", ndefFormatable);
        return payload;
    }

    static JSONObject nfcAPayload(byte[] atqa, int sak) throws JSONException {
        JSONObject payload = new JSONObject();
        payload.put("atqaHex", hex(atqa));
        payload.put("sak", sak);
        return payload;
    }

    static JSONObject nfcBPayload(byte[] applicationData, byte[] protocolInfo) throws JSONException {
        JSONObject payload = new JSONObject();
        payload.put("applicationDataHex", hex(applicationData));
        payload.put("protocolInfoHex", hex(protocolInfo));
        return payload;
    }

    static JSONObject nfcFPayload(byte[] manufacturer, byte[] systemCode) throws JSONException {
        JSONObject payload = new JSONObject();
        payload.put("manufacturerHex", hex(manufacturer));
        payload.put("systemCodeHex", hex(systemCode));
        return payload;
    }

    static JSONObject nfcVPayload(int responseFlags, int dsfId) throws JSONException {
        JSONObject payload = new JSONObject();
        payload.put("responseFlags", responseFlags);
        payload.put("dsfId", dsfId);
        return payload;
    }

    static JSONObject isoDepPayload(byte[] historicalBytes, byte[] hiLayerResponse, boolean extendedLengthApduSupported) throws JSONException {
        JSONObject payload = new JSONObject();
        payload.put("historicalBytesHex", hex(historicalBytes));
        payload.put("hiLayerResponseHex", hex(hiLayerResponse));
        payload.put("extendedLengthApduSupported", extendedLengthApduSupported);
        return payload;
    }

    static JSONObject mifareUltralightPayload(int type) throws JSONException {
        JSONObject payload = new JSONObject();
        payload.put("type", mifareUltralightTypeName(type));
        return payload;
    }

    static JSONObject mifareClassicPayload(int type, int sizeBytes, int blockCount, int sectorCount) throws JSONException {
        JSONObject payload = new JSONObject();
        payload.put("type", mifareClassicTypeName(type));
        payload.put("sizeBytes", sizeBytes);
        payload.put("blockCount", blockCount);
        payload.put("sectorCount", sectorCount);
        return payload;
    }

    static JSONObject ndefUnavailablePayload() throws JSONException {
        JSONObject payload = new JSONObject();
        payload.put("available", false);
        payload.put("messages", new JSONArray());
        payload.put("records", new JSONArray());
        return payload;
    }

    static JSONObject ndefMetadataPayload(String type, int maxSizeBytes, boolean writable, boolean canMakeReadOnly) throws JSONException {
        JSONObject payload = new JSONObject();
        payload.put("available", true);
        payload.put("type", type);
        payload.put("maxSizeBytes", maxSizeBytes);
        payload.put("writable", writable);
        payload.put("canMakeReadOnly", canMakeReadOnly);
        return payload;
    }

    static void putNdefMessages(JSONObject payload, JSONArray messages, JSONArray records) throws JSONException {
        payload.put("messageCount", messages.length());
        payload.put("recordCount", records.length());
        payload.put("messages", messages);
        payload.put("records", records);
    }

    static JSONObject messagePayload(JSONArray records) throws JSONException {
        JSONObject payload = new JSONObject();
        payload.put("recordCount", records.length());
        payload.put("records", records);
        return payload;
    }

    static JSONObject recordPayload(
            int index,
            short tnf,
            byte[] type,
            byte[] identifier,
            byte[] rawPayload,
            String uri,
            String mimeType
    ) throws JSONException {
        JSONObject payload = new JSONObject();
        payload.put("index", index);
        payload.put("typeNameFormat", tnfName(tnf));
        payload.put("typeNameFormatRawValue", tnf);
        payload.put("type", stringOrHex(type));
        payload.put("typeHex", hex(type));
        payload.put("identifier", stringOrHex(identifier));
        payload.put("identifierHex", hex(identifier));
        byte[] safePayload = rawPayload != null ? rawPayload : new byte[0];
        payload.put("payloadBase64", base64(safePayload));
        payload.put("payloadHex", hex(safePayload));
        String text = decodeTextRecord(tnf, type, safePayload);
        if (text != null) {
            payload.put("text", text);
            String languageCode = decodeTextLanguageCode(safePayload);
            if (languageCode != null) {
                payload.put("languageCode", languageCode);
            }
        } else {
            String utf8 = utf8(safePayload);
            if (utf8 != null && !utf8.isEmpty()) {
                payload.put("text", utf8);
            }
        }
        if (uri != null) {
            payload.put("uri", uri);
        }
        if (mimeType != null && !mimeType.isEmpty()) {
            payload.put("mimeType", mimeType);
        }
        return payload;
    }

    static String decodeTextRecord(short tnf, byte[] type, byte[] payload) {
        if (tnf != TNF_WELL_KNOWN || !matches(type, RTD_TEXT) || payload == null || payload.length < 1) {
            return null;
        }
        int status = payload[0] & 0xff;
        boolean utf16 = (status & 0x80) != 0;
        int languageLength = status & 0x3f;
        if (payload.length < 1 + languageLength) {
            return null;
        }
        Charset charset = utf16 ? StandardCharsets.UTF_16 : StandardCharsets.UTF_8;
        return new String(payload, 1 + languageLength, payload.length - 1 - languageLength, charset);
    }

    static String decodeTextLanguageCode(byte[] payload) {
        if (payload == null || payload.length < 1) {
            return null;
        }
        int languageLength = payload[0] & 0x3f;
        if (payload.length < 1 + languageLength) {
            return null;
        }
        return new String(payload, 1, languageLength, StandardCharsets.US_ASCII);
    }

    static String shortTechName(String name) {
        if (name == null) {
            return "";
        }
        int index = name.lastIndexOf('.');
        return index >= 0 && index + 1 < name.length() ? name.substring(index + 1) : name;
    }

    static String tnfName(short tnf) {
        switch (tnf) {
            case TNF_EMPTY: return "empty";
            case TNF_WELL_KNOWN: return "nfcWellKnown";
            case TNF_MIME_MEDIA: return "media";
            case TNF_ABSOLUTE_URI: return "absoluteURI";
            case TNF_EXTERNAL_TYPE: return "nfcExternal";
            case TNF_UNKNOWN: return "unknown";
            case TNF_UNCHANGED: return "unchanged";
            default: return "unknown";
        }
    }

    static String mifareUltralightTypeName(int type) {
        switch (type) {
            case 1: return "ultralight";
            case 2: return "ultralightC";
            default: return "unknown";
        }
    }

    static String mifareClassicTypeName(int type) {
        switch (type) {
            case 0: return "classic";
            case 1: return "plus";
            case 2: return "pro";
            default: return "unknown";
        }
    }

    static String stringOrHex(byte[] data) {
        String value = utf8(data);
        return value != null && !value.isEmpty() ? value : hex(data);
    }

    static String utf8(byte[] data) {
        if (data == null || data.length == 0) {
            return "";
        }
        try {
            return new String(data, StandardCharsets.UTF_8);
        } catch (Exception ignored) {
            return null;
        }
    }

    static String hex(byte[] data) {
        if (data == null || data.length == 0) {
            return "";
        }
        StringBuilder builder = new StringBuilder(data.length * 2);
        for (byte item : data) {
            builder.append(String.format(Locale.US, "%02X", item & 0xff));
        }
        return builder.toString();
    }

    static String base64(byte[] data) {
        if (data == null || data.length == 0) {
            return "";
        }
        StringBuilder builder = new StringBuilder(((data.length + 2) / 3) * 4);
        for (int index = 0; index < data.length; index += 3) {
            int byte0 = data[index] & 0xff;
            int byte1 = index + 1 < data.length ? data[index + 1] & 0xff : 0;
            int byte2 = index + 2 < data.length ? data[index + 2] & 0xff : 0;
            int packed = (byte0 << 16) | (byte1 << 8) | byte2;
            builder.append(BASE64_ALPHABET[(packed >> 18) & 0x3f]);
            builder.append(BASE64_ALPHABET[(packed >> 12) & 0x3f]);
            builder.append(index + 1 < data.length ? BASE64_ALPHABET[(packed >> 6) & 0x3f] : '=');
            builder.append(index + 2 < data.length ? BASE64_ALPHABET[packed & 0x3f] : '=');
        }
        return builder.toString();
    }

    static boolean matches(byte[] left, byte[] right) {
        if (left == null || right == null || left.length != right.length) {
            return false;
        }
        for (int index = 0; index < left.length; index += 1) {
            if (left[index] != right[index]) {
                return false;
            }
        }
        return true;
    }
}
