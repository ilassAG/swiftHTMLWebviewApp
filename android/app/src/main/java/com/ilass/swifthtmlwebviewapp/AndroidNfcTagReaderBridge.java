package com.ilass.swifthtmlwebviewapp;

import android.app.Activity;
import android.content.Context;
import android.content.pm.PackageManager;
import android.nfc.NdefMessage;
import android.nfc.NdefRecord;
import android.nfc.NfcAdapter;
import android.nfc.Tag;
import android.nfc.tech.IsoDep;
import android.nfc.tech.MifareClassic;
import android.nfc.tech.MifareUltralight;
import android.nfc.tech.Ndef;
import android.nfc.tech.NdefFormatable;
import android.nfc.tech.NfcA;
import android.nfc.tech.NfcB;
import android.nfc.tech.NfcF;
import android.nfc.tech.NfcV;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Base64;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.util.Locale;

final class AndroidNfcTagReaderBridge implements NfcAdapter.ReaderCallback {
    interface Host {
        Activity activity();
        Context context();
        void sendResult(JSONObject payload);
    }

    private static final long DEFAULT_TIMEOUT_MS = 30000L;

    private final Host host;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private NfcAdapter nfcAdapter;
    private JSONObject pendingRequest;
    private boolean reading = false;
    private Runnable timeoutRunnable;

    AndroidNfcTagReaderBridge(Host host) {
        this.host = host;
        this.nfcAdapter = NfcAdapter.getDefaultAdapter(host.context());
    }

    void startRead(JSONObject request) {
        JSONObject copiedRequest = copyRequest(request);
        if (nfcAdapter == null) {
            sendError(copiedRequest, "NFC tag reading is not available on this device.");
            return;
        }
        if (!nfcAdapter.isEnabled()) {
            sendError(copiedRequest, "NFC is disabled on this device.");
            return;
        }
        if (reading) {
            sendError(copiedRequest, "An NFC tag read session is already active.");
            return;
        }

        reading = true;
        pendingRequest = copiedRequest;
        int flags = NfcAdapter.FLAG_READER_NFC_A
                | NfcAdapter.FLAG_READER_NFC_B
                | NfcAdapter.FLAG_READER_NFC_F
                | NfcAdapter.FLAG_READER_NFC_V
                | NfcAdapter.FLAG_READER_NFC_BARCODE;
        Bundle extras = new Bundle();
        handler.post(() -> {
            try {
                nfcAdapter.enableReaderMode(host.activity(), this, flags, extras);
                scheduleTimeout(copiedRequest);
            } catch (Exception error) {
                reading = false;
                pendingRequest = null;
                sendError(copiedRequest, "Could not start Android NFC reader mode: " + error.getMessage());
            }
        });
    }

    void shutdown() {
        stopReader(false);
        pendingRequest = null;
    }

    static boolean isAvailable(Context context) {
        return context.getPackageManager().hasSystemFeature(PackageManager.FEATURE_NFC)
                && NfcAdapter.getDefaultAdapter(context) != null;
    }

    static boolean isEnabled(Context context) {
        NfcAdapter adapter = NfcAdapter.getDefaultAdapter(context);
        return adapter != null && adapter.isEnabled();
    }

    @Override
    public void onTagDiscovered(Tag tag) {
        JSONObject request = pendingRequest != null ? copyRequest(pendingRequest) : new JSONObject();
        stopReader(false);
        try {
            host.sendResult(tagResponse(request, tag));
        } catch (JSONException error) {
            sendError(request, error.getMessage());
        }
    }

    private void scheduleTimeout(JSONObject request) {
        cancelTimeout();
        long timeoutMs = Math.max(1000L, request.optLong("timeoutMs", Math.round(request.optDouble("timeoutSeconds", DEFAULT_TIMEOUT_MS / 1000.0) * 1000.0)));
        timeoutRunnable = () -> {
            JSONObject activeRequest = pendingRequest != null ? copyRequest(pendingRequest) : request;
            stopReader(false);
            sendError(activeRequest, "NFC tag reading timed out.");
        };
        handler.postDelayed(timeoutRunnable, Math.min(timeoutMs, 60000L));
    }

    private void stopReader(boolean keepRequest) {
        cancelTimeout();
        handler.post(() -> {
            try {
                if (nfcAdapter != null) {
                    nfcAdapter.disableReaderMode(host.activity());
                }
            } catch (Exception ignored) {
                // Reader mode may already be disabled.
            }
        });
        reading = false;
        if (!keepRequest) {
            pendingRequest = null;
        }
    }

    private void cancelTimeout() {
        if (timeoutRunnable != null) {
            handler.removeCallbacks(timeoutRunnable);
            timeoutRunnable = null;
        }
    }

    private JSONObject tagResponse(JSONObject request, Tag tag) throws JSONException {
        JSONObject response = baseResponse(request);
        response.put("success", true);
        response.put("tag", tagPayload(tag));
        response.put("ndef", ndefPayload(tag));
        return response;
    }

    private JSONObject tagPayload(Tag tag) throws JSONException {
        JSONObject payload = new JSONObject();
        payload.put("identifierHex", hex(tag.getId()));
        payload.put("identifierBase64", Base64.encodeToString(tag.getId(), Base64.NO_WRAP));
        JSONArray technologies = new JSONArray();
        for (String tech : tag.getTechList()) {
            technologies.put(shortTechName(tech));
        }
        payload.put("technologies", technologies);
        payload.put("ndefFormatable", NdefFormatable.get(tag) != null);
        addTechDetails(payload, tag);
        return payload;
    }

    private void addTechDetails(JSONObject payload, Tag tag) throws JSONException {
        NfcA nfcA = NfcA.get(tag);
        if (nfcA != null) {
            JSONObject info = new JSONObject();
            info.put("atqaHex", hex(nfcA.getAtqa()));
            info.put("sak", nfcA.getSak());
            payload.put("nfcA", info);
        }

        NfcB nfcB = NfcB.get(tag);
        if (nfcB != null) {
            JSONObject info = new JSONObject();
            info.put("applicationDataHex", hex(nfcB.getApplicationData()));
            info.put("protocolInfoHex", hex(nfcB.getProtocolInfo()));
            payload.put("nfcB", info);
        }

        NfcF nfcF = NfcF.get(tag);
        if (nfcF != null) {
            JSONObject info = new JSONObject();
            info.put("manufacturerHex", hex(nfcF.getManufacturer()));
            info.put("systemCodeHex", hex(nfcF.getSystemCode()));
            payload.put("nfcF", info);
        }

        NfcV nfcV = NfcV.get(tag);
        if (nfcV != null) {
            JSONObject info = new JSONObject();
            info.put("responseFlags", nfcV.getResponseFlags());
            info.put("dsfId", nfcV.getDsfId());
            payload.put("nfcV", info);
        }

        IsoDep isoDep = IsoDep.get(tag);
        if (isoDep != null) {
            JSONObject info = new JSONObject();
            info.put("historicalBytesHex", hex(isoDep.getHistoricalBytes()));
            info.put("hiLayerResponseHex", hex(isoDep.getHiLayerResponse()));
            info.put("extendedLengthApduSupported", isoDep.isExtendedLengthApduSupported());
            payload.put("isoDep", info);
        }

        MifareUltralight ultralight = MifareUltralight.get(tag);
        if (ultralight != null) {
            JSONObject info = new JSONObject();
            info.put("type", mifareUltralightTypeName(ultralight.getType()));
            payload.put("mifareUltralight", info);
        }

        MifareClassic classic = MifareClassic.get(tag);
        if (classic != null) {
            JSONObject info = new JSONObject();
            info.put("type", mifareClassicTypeName(classic.getType()));
            info.put("sizeBytes", classic.getSize());
            info.put("blockCount", classic.getBlockCount());
            info.put("sectorCount", classic.getSectorCount());
            payload.put("mifareClassic", info);
        }
    }

    private JSONObject ndefPayload(Tag tag) throws JSONException {
        JSONObject payload = new JSONObject();
        Ndef ndef = Ndef.get(tag);
        if (ndef == null) {
            payload.put("available", false);
            payload.put("messages", new JSONArray());
            payload.put("records", new JSONArray());
            return payload;
        }

        payload.put("available", true);
        payload.put("type", ndef.getType());
        payload.put("maxSizeBytes", ndef.getMaxSize());
        payload.put("writable", ndef.isWritable());
        payload.put("canMakeReadOnly", ndef.canMakeReadOnly());

        NdefMessage message = null;
        try {
            ndef.connect();
            message = ndef.getNdefMessage();
        } catch (Exception error) {
            payload.put("readError", error.getMessage() != null ? error.getMessage() : error.getClass().getSimpleName());
        } finally {
            try {
                ndef.close();
            } catch (Exception ignored) {
                // Already closed.
            }
        }
        if (message == null) {
            message = ndef.getCachedNdefMessage();
        }

        JSONArray messages = new JSONArray();
        JSONArray records = new JSONArray();
        if (message != null) {
            messages.put(messagePayload(message));
            NdefRecord[] ndefRecords = message.getRecords();
            for (int index = 0; index < ndefRecords.length; index += 1) {
                records.put(recordPayload(ndefRecords[index], index));
            }
        }
        payload.put("messageCount", messages.length());
        payload.put("recordCount", records.length());
        payload.put("messages", messages);
        payload.put("records", records);
        return payload;
    }

    private JSONObject messagePayload(NdefMessage message) throws JSONException {
        JSONArray records = new JSONArray();
        NdefRecord[] ndefRecords = message.getRecords();
        for (int index = 0; index < ndefRecords.length; index += 1) {
            records.put(recordPayload(ndefRecords[index], index));
        }
        JSONObject payload = new JSONObject();
        payload.put("recordCount", records.length());
        payload.put("records", records);
        return payload;
    }

    private JSONObject recordPayload(NdefRecord record, int index) throws JSONException {
        JSONObject payload = new JSONObject();
        payload.put("index", index);
        payload.put("typeNameFormat", tnfName(record.getTnf()));
        payload.put("typeNameFormatRawValue", record.getTnf());
        payload.put("type", stringOrHex(record.getType()));
        payload.put("typeHex", hex(record.getType()));
        payload.put("identifier", stringOrHex(record.getId()));
        payload.put("identifierHex", hex(record.getId()));
        payload.put("payloadBase64", Base64.encodeToString(record.getPayload(), Base64.NO_WRAP));
        payload.put("payloadHex", hex(record.getPayload()));
        String text = decodeTextRecord(record);
        if (text != null) {
            payload.put("text", text);
            String languageCode = decodeTextLanguageCode(record);
            if (languageCode != null) {
                payload.put("languageCode", languageCode);
            }
        } else {
            String utf8 = utf8(record.getPayload());
            if (utf8 != null && !utf8.isEmpty()) {
                payload.put("text", utf8);
            }
        }
        android.net.Uri uri = record.toUri();
        if (uri != null) {
            payload.put("uri", uri.toString());
        }
        String mimeType = record.toMimeType();
        if (mimeType != null && !mimeType.isEmpty()) {
            payload.put("mimeType", mimeType);
        }
        return payload;
    }

    private String decodeTextRecord(NdefRecord record) {
        if (record.getTnf() != NdefRecord.TNF_WELL_KNOWN || !matches(record.getType(), NdefRecord.RTD_TEXT)) {
            return null;
        }
        byte[] payload = record.getPayload();
        if (payload.length < 1) {
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

    private String decodeTextLanguageCode(NdefRecord record) {
        byte[] payload = record.getPayload();
        if (payload.length < 1) {
            return null;
        }
        int languageLength = payload[0] & 0x3f;
        if (payload.length < 1 + languageLength) {
            return null;
        }
        return new String(payload, 1, languageLength, StandardCharsets.US_ASCII);
    }

    private JSONObject baseResponse(JSONObject request) throws JSONException {
        JSONObject response = new JSONObject();
        response.put("platform", "android");
        response.put("action", "nfcTagRead");
        if (request != null && request.has("requestId")) {
            response.put("requestId", request.optString("requestId"));
        }
        return response;
    }

    private void sendError(JSONObject request, String message) {
        try {
            JSONObject response = baseResponse(request);
            response.put("success", false);
            response.put("error", message != null ? message : "Unknown NFC error.");
            host.sendResult(response);
        } catch (JSONException ignored) {
            // Ignore secondary JSON failure.
        }
    }

    private JSONObject copyRequest(JSONObject request) {
        try {
            return new JSONObject(request != null ? request.toString() : "{}");
        } catch (JSONException ignored) {
            return new JSONObject();
        }
    }

    private String shortTechName(String name) {
        int index = name.lastIndexOf('.');
        return index >= 0 && index + 1 < name.length() ? name.substring(index + 1) : name;
    }

    private String tnfName(short tnf) {
        switch (tnf) {
            case NdefRecord.TNF_EMPTY: return "empty";
            case NdefRecord.TNF_WELL_KNOWN: return "nfcWellKnown";
            case NdefRecord.TNF_MIME_MEDIA: return "media";
            case NdefRecord.TNF_ABSOLUTE_URI: return "absoluteURI";
            case NdefRecord.TNF_EXTERNAL_TYPE: return "nfcExternal";
            case NdefRecord.TNF_UNKNOWN: return "unknown";
            case NdefRecord.TNF_UNCHANGED: return "unchanged";
            default: return "unknown";
        }
    }

    private String mifareUltralightTypeName(int type) {
        switch (type) {
            case MifareUltralight.TYPE_ULTRALIGHT: return "ultralight";
            case MifareUltralight.TYPE_ULTRALIGHT_C: return "ultralightC";
            case MifareUltralight.TYPE_UNKNOWN:
            default: return "unknown";
        }
    }

    private String mifareClassicTypeName(int type) {
        switch (type) {
            case MifareClassic.TYPE_CLASSIC: return "classic";
            case MifareClassic.TYPE_PLUS: return "plus";
            case MifareClassic.TYPE_PRO: return "pro";
            case MifareClassic.TYPE_UNKNOWN:
            default: return "unknown";
        }
    }

    private String stringOrHex(byte[] data) {
        String value = utf8(data);
        return value != null && !value.isEmpty() ? value : hex(data);
    }

    private String utf8(byte[] data) {
        if (data == null || data.length == 0) {
            return "";
        }
        try {
            return new String(data, StandardCharsets.UTF_8);
        } catch (Exception ignored) {
            return null;
        }
    }

    private String hex(byte[] data) {
        if (data == null || data.length == 0) {
            return "";
        }
        StringBuilder builder = new StringBuilder(data.length * 2);
        for (byte item : data) {
            builder.append(String.format(Locale.US, "%02X", item & 0xff));
        }
        return builder.toString();
    }

    private boolean matches(byte[] left, byte[] right) {
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
