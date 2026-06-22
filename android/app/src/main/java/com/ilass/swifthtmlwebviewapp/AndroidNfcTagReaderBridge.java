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

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

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
        JSONObject response = AndroidNfcPayload.baseResponse(request);
        response.put("success", true);
        response.put("tag", tagPayload(tag));
        response.put("ndef", ndefPayload(tag));
        return response;
    }

    private JSONObject tagPayload(Tag tag) throws JSONException {
        JSONObject payload = AndroidNfcPayload.tagPayload(tag.getId(), tag.getTechList(), NdefFormatable.get(tag) != null);
        addTechDetails(payload, tag);
        return payload;
    }

    private void addTechDetails(JSONObject payload, Tag tag) throws JSONException {
        NfcA nfcA = NfcA.get(tag);
        if (nfcA != null) {
            payload.put("nfcA", AndroidNfcPayload.nfcAPayload(nfcA.getAtqa(), nfcA.getSak()));
        }

        NfcB nfcB = NfcB.get(tag);
        if (nfcB != null) {
            payload.put("nfcB", AndroidNfcPayload.nfcBPayload(nfcB.getApplicationData(), nfcB.getProtocolInfo()));
        }

        NfcF nfcF = NfcF.get(tag);
        if (nfcF != null) {
            payload.put("nfcF", AndroidNfcPayload.nfcFPayload(nfcF.getManufacturer(), nfcF.getSystemCode()));
        }

        NfcV nfcV = NfcV.get(tag);
        if (nfcV != null) {
            payload.put("nfcV", AndroidNfcPayload.nfcVPayload(nfcV.getResponseFlags(), nfcV.getDsfId()));
        }

        IsoDep isoDep = IsoDep.get(tag);
        if (isoDep != null) {
            payload.put("isoDep", AndroidNfcPayload.isoDepPayload(
                    isoDep.getHistoricalBytes(),
                    isoDep.getHiLayerResponse(),
                    isoDep.isExtendedLengthApduSupported()
            ));
        }

        MifareUltralight ultralight = MifareUltralight.get(tag);
        if (ultralight != null) {
            payload.put("mifareUltralight", AndroidNfcPayload.mifareUltralightPayload(ultralight.getType()));
        }

        MifareClassic classic = MifareClassic.get(tag);
        if (classic != null) {
            payload.put("mifareClassic", AndroidNfcPayload.mifareClassicPayload(
                    classic.getType(),
                    classic.getSize(),
                    classic.getBlockCount(),
                    classic.getSectorCount()
            ));
        }
    }

    private JSONObject ndefPayload(Tag tag) throws JSONException {
        JSONObject payload = new JSONObject();
        Ndef ndef = Ndef.get(tag);
        if (ndef == null) {
            return AndroidNfcPayload.ndefUnavailablePayload();
        }

        payload = AndroidNfcPayload.ndefMetadataPayload(
                ndef.getType(),
                ndef.getMaxSize(),
                ndef.isWritable(),
                ndef.canMakeReadOnly()
        );

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
        AndroidNfcPayload.putNdefMessages(payload, messages, records);
        return payload;
    }

    private JSONObject messagePayload(NdefMessage message) throws JSONException {
        JSONArray records = new JSONArray();
        NdefRecord[] ndefRecords = message.getRecords();
        for (int index = 0; index < ndefRecords.length; index += 1) {
            records.put(recordPayload(ndefRecords[index], index));
        }
        return AndroidNfcPayload.messagePayload(records);
    }

    private JSONObject recordPayload(NdefRecord record, int index) throws JSONException {
        android.net.Uri uri = record.toUri();
        String mimeType = record.toMimeType();
        return AndroidNfcPayload.recordPayload(
                index,
                record.getTnf(),
                record.getType(),
                record.getId(),
                record.getPayload(),
                uri != null ? uri.toString() : null,
                mimeType
        );
    }

    private void sendError(JSONObject request, String message) {
        try {
            host.sendResult(AndroidNfcPayload.errorResponse(request, message));
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

}
