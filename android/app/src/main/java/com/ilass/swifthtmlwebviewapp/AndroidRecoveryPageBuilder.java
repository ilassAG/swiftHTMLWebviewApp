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
                + ":root{color-scheme:dark light;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#07110d;color:#eef7ef;}"
                + "body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:28px;background:linear-gradient(160deg,#07110d,#12211a);}"
                + "main{width:min(520px,100%);border:1px solid rgba(166,232,125,.25);border-radius:22px;padding:24px;background:rgba(13,24,18,.88);box-shadow:0 18px 48px rgba(0,0,0,.35);}"
                + ".mark{width:58px;height:58px;border-radius:18px;background:linear-gradient(135deg,#9eea72,#56c7a5);display:grid;place-items:center;margin-bottom:18px;color:#06100b;font-weight:900;font-size:25px;}"
                + "h1{font-size:25px;margin:0 0 10px;}p{line-height:1.45;color:#c8d1c9;margin:0 0 16px;}button{width:100%;border:0;border-radius:14px;padding:16px 18px;margin-top:12px;font-size:17px;font-weight:800;color:#07110d;background:#a9ed7b;}"
                + "button.secondary{background:transparent;color:#eef7ef;border:1px solid rgba(238,247,239,.28);}"
                + "#status{margin-top:14px;color:#a9ed7b;font-weight:700;min-height:22px;}ul{padding-left:18px;margin:10px 0 0;color:#9fa9a1;font-size:13px;word-break:break-all;}small{display:block;margin-top:18px;color:#859088;}"
                + "</style></head><body><main>"
                + "<div class=\"mark\">" + escapedShortMark + "</div>"
                + "<h1>" + escapedTitle + "</h1>"
                + "<p>" + escapedBody + "</p>"
                + "<button type=\"button\" onclick=\"scanQr()\">QR-Code scannen</button>"
                + "<button class=\"secondary\" type=\"button\" onclick=\"retry()\">Erneut pruefen</button>"
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
