package com.ilass.swifthtmlwebviewapp;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

final class AndroidRecoveryPageBuilder {
    static final String BASE_URL = "https://android-recovery.local/";

    private AndroidRecoveryPageBuilder() {
    }

    static String html(Config config) {
        Config source = config != null ? config : new Config.Builder().build();
        StringBuilder candidatesHtml = new StringBuilder();
        for (String candidate : source.candidates) {
            candidatesHtml.append("<li>").append(escapeHtml(candidate)).append("</li>");
        }
        String escapedReason = escapeHtml(nonEmpty(source.reason, "Server nicht erreichbar."));
        String escapedShortMark = escapeHtml(source.shortMark);
        String escapedTitle = escapeHtml(source.title);
        String escapedBody = escapeHtml(source.body);
        String escapedSuccessMessage = escapeJavaScriptString(source.successMessage);
        String escapedInvalidQRMessage = escapeJavaScriptString(source.invalidQRMessage);
        return "<!doctype html><html lang=\"de\"><head>"
                + "<meta charset=\"utf-8\">"
                + "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1, viewport-fit=cover\">"
                + "<title>" + escapedTitle + "</title>"
                + "<style>"
                + ":root{color-scheme:light;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#f4f8ff;color:#14213d;}"
                + "*{box-sizing:border-box;}"
                + "body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:28px;background:linear-gradient(180deg,#eef6ff 0%,#fff 48%,#f7fbff 100%);}"
                + "main{width:min(520px,100%);display:grid;gap:18px;}"
                + ".mark{width:76px;height:76px;border-radius:22px;background:#fff;border:1px solid #d8e7ff;display:grid;place-items:center;box-shadow:0 18px 38px rgba(10,132,255,.18);}"
                + ".mark svg{width:56px;height:56px;display:block;}.sr-only{position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;border:0;}"
                + "h1{font-size:32px;line-height:1.08;margin:0;}p{line-height:1.45;color:#4f5f76;margin:0;font-size:16px;}"
                + "button{width:100%;border:0;border-radius:14px;padding:16px 18px;margin-top:0;font-size:17px;font-weight:800;color:#fff;background:#0a84ff;}"
                + "button.secondary{background:#fff;color:#0a63ce;border:1px solid #b9d7ff;}"
                + ".actions{display:grid;gap:10px;}#status{color:#0a63ce;font-weight:700;min-height:22px;}ul{padding:0;margin:4px 0 0;list-style:none;display:grid;gap:8px;color:#0a63ce;font-size:13px;word-break:break-all;}li{padding:10px 12px;border:1px solid #d8e7ff;border-radius:10px;background:#fff;}small{display:block;color:#6d7d93;}"
                + "</style></head><body><main>"
                + "<div class=\"mark\" aria-label=\"" + escapedShortMark + "\">"
                + "<svg viewBox=\"0 0 64 64\" aria-hidden=\"true\">"
                + "<path fill=\"#ff6b2b\" d=\"M49.5 13.5c6.4 7.7 8.5 17.8 4.7 26.7-4 9.4-13.3 14.7-25.8 14.7-9 0-16.7-3.1-22.4-8.8 6.9 2.7 14.7 2.1 20.7-1.4C17.7 38 10.8 29.5 6.8 19.4c7.4 6.8 15.3 12.1 23.8 15.8C22.8 27 17.1 18.7 13.4 10.1c9.4 10.5 19.6 18.2 30.8 23.3 1.7-6.6.1-13.1-4.2-19.6 3.4 1.3 6.6 3 9.5 5.1z\"/>"
                + "<path fill=\"#0a84ff\" d=\"M13 46.3c8.8 5.2 19.4 5.5 29.4 1.1-3.9 5.4-10.7 8.6-19.3 8.6-7.2 0-13.5-2.7-18.1-7.2 2.7.2 5.4-.6 8-2.5z\"/>"
                + "</svg><span class=\"sr-only\">" + escapedShortMark + "</span></div>"
                + "<h1>" + escapedTitle + "</h1>"
                + "<p>" + escapedBody + "</p>"
                + "<div class=\"actions\"><button type=\"button\" onclick=\"scanQr()\">QR-Code scannen</button>"
                + "<button class=\"secondary\" type=\"button\" onclick=\"retry()\">Erneut pruefen</button></div>"
                + "<div id=\"status\">" + escapedReason + "</div>"
                + "<small>Gepruefte Adressen</small><ul>" + candidatesHtml + "</ul>"
                + "</main><script>"
                + "function post(m){try{window.AndroidNativeBridge.postMessage(JSON.stringify(m||{}));}catch(e){setStatus('Native Bridge nicht bereit: '+e.message);}}"
                + "function setStatus(t){document.getElementById('status').textContent=t;}"
                + "function scanQr(){setStatus('Scanner wird geoeffnet...');post({action:'scanBarcode',source:'recovery',types:['qr'],requestId:'recovery-'+Date.now()});}"
                + "function retry(){setStatus('Verbindung wird geprueft...');post({action:'reload',source:'recovery',requestId:'reload-'+Date.now()});}"
                + "window.handleNativeResult=function(payload){"
                + "payload=payload||{};"
                + "if(payload.action==='scanBarcode'){"
                + "if(payload.serverURLPersisted){setStatus('" + escapedSuccessMessage + "');setTimeout(retry,250);return;}"
                + "if(payload.error){setStatus(payload.error);return;}"
                + "setStatus('" + escapedInvalidQRMessage + "');return;"
                + "}"
                + "if(payload.action==='reload'&&payload.error){setStatus(payload.error);return;}"
                + "if(payload.error){setStatus(payload.error);}"
                + "};"
                + "</script></body></html>";
    }

    static String escapeHtml(String value) {
        String raw = value != null ? value : "";
        return raw.replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
    }

    static String escapeJavaScriptString(String value) {
        String raw = value != null ? value : "";
        return raw.replace("\\", "\\\\")
                .replace("'", "\\'")
                .replace("\n", "\\n")
                .replace("\r", "\\r")
                .replace("<", "\\u003C")
                .replace(">", "\\u003E")
                .replace("&", "\\u0026");
    }

    private static String nonEmpty(String value, String fallback) {
        String trimmed = value == null ? "" : value.trim();
        return trimmed.isEmpty() ? fallback : trimmed;
    }

    static final class Config {
        final String reason;
        final List<String> candidates;
        final String shortMark;
        final String title;
        final String body;
        final String successMessage;
        final String invalidQRMessage;

        private Config(Builder builder) {
            this.reason = builder.reason;
            this.candidates = Collections.unmodifiableList(new ArrayList<>(builder.candidates));
            this.shortMark = builder.shortMark;
            this.title = builder.title;
            this.body = builder.body;
            this.successMessage = builder.successMessage;
            this.invalidQRMessage = builder.invalidQRMessage;
        }

        static final class Builder {
            private String reason = "";
            private List<String> candidates = Collections.emptyList();
            private String shortMark = "SW";
            private String title = "Server nicht erreichbar";
            private String body = "";
            private String successMessage = "Neue Server-Adresse gespeichert. Verbindung wird geprueft...";
            private String invalidQRMessage = "QR-Code erkannt, aber keine Server-Adresse gefunden.";

            Builder reason(String value) {
                reason = value;
                return this;
            }

            Builder candidates(List<String> values) {
                candidates = values != null ? values : Collections.emptyList();
                return this;
            }

            Builder shortMark(String value) {
                shortMark = value;
                return this;
            }

            Builder title(String value) {
                title = value;
                return this;
            }

            Builder body(String value) {
                body = value;
                return this;
            }

            Builder successMessage(String value) {
                successMessage = value;
                return this;
            }

            Builder invalidQRMessage(String value) {
                invalidQRMessage = value;
                return this;
            }

            Config build() {
                return new Config(this);
            }
        }
    }
}
