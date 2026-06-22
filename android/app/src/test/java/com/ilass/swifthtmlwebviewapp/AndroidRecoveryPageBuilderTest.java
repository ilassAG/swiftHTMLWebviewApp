package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.util.Arrays;

import org.junit.Test;

public class AndroidRecoveryPageBuilderTest {
    @Test
    public void htmlUsesVariantBrandingAndEscapesText() {
        AndroidRecoveryPageBuilder.Config config = new AndroidRecoveryPageBuilder.Config.Builder()
                .reason("Timeout <wifi> & retry")
                .candidates(Arrays.asList("https://primary.invalid/?a=1&b=2", "https://backup.invalid/<bad>"))
                .shortMark("W<i>")
                .title("WebView Demo <Verbindung>")
                .body("Server & WLAN pruefen")
                .successMessage("Adresse <ok> & weiter")
                .invalidQRMessage("QR 'ungueltig' <bad>")
                .build();

        String html = AndroidRecoveryPageBuilder.html(config);

        assertTrue(html.contains("<title>WebView Demo &lt;Verbindung&gt;</title>"));
        assertTrue(html.contains("<div class=\"mark\">W&lt;i&gt;</div>"));
        assertTrue(html.contains("Server &amp; WLAN pruefen"));
        assertTrue(html.contains("Timeout &lt;wifi&gt; &amp; retry"));
        assertTrue(html.contains("https://primary.invalid/?a=1&amp;b=2"));
        assertTrue(html.contains("https://backup.invalid/&lt;bad&gt;"));
        assertTrue(html.contains("Adresse \\u003Cok\\u003E \\u0026 weiter"));
        assertTrue(html.contains("QR \\'ungueltig\\' \\u003Cbad\\u003E"));
        assertFalse(html.contains("Timeout <wifi>"));
    }

    @Test
    public void htmlKeepsRecoveryBridgeActions() {
        String html = AndroidRecoveryPageBuilder.html(new AndroidRecoveryPageBuilder.Config.Builder().build());

        assertTrue(html.contains("window.AndroidNativeBridge.postMessage"));
        assertTrue(html.contains("action:'scanBarcode',source:'recovery',types:['qr'],requestId:'recovery-'"));
        assertTrue(html.contains("action:'reload',source:'recovery',requestId:'reload-'"));
        assertTrue(html.contains("payload.serverURLPersisted"));
    }

    @Test
    public void blankReasonFallsBackToDefaultStatus() {
        AndroidRecoveryPageBuilder.Config config = new AndroidRecoveryPageBuilder.Config.Builder()
                .reason(" ")
                .build();

        assertTrue(AndroidRecoveryPageBuilder.html(config).contains("Server nicht erreichbar."));
    }
}
