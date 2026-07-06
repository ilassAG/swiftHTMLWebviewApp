package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assume.assumeTrue;

import io.nats.client.Connection;
import io.nats.client.Message;
import io.nats.client.Nats;
import io.nats.client.Options;

import org.json.JSONObject;
import org.junit.Test;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Base64;

public class AndroidNatsClusterSmokeTest {
    @Test
    public void bridgeConnectsHandlesCommandAndPublishesAgainstRealClusterWhenConfigured() throws Exception {
        String credential = smokeCredential();
        assumeTrue("Set NATS_SMOKE_CREDS_B64 or NATS_SMOKE_CREDS_PATH to run this smoke test.", !credential.isEmpty());
        ArrayList<String> urls = smokeURLs();
        assumeTrue("Set NATS_SMOKE_URLS to run this smoke test.", !urls.isEmpty());

        FakeHost host = new FakeHost();
        host.settings.enabled = true;
        host.settings.urls = urls;
        host.settings.authMethod = "creds";
        host.settings.clientNameTemplate = "swift-wrapper-android-smoke-${appUUID}";

        AndroidNatsBridge bridge = new AndroidNatsBridge(
                host,
                new StaticCredentialStore(credential),
                new AndroidNatsClientConnectionDriver()
        );

        JSONObject connected = bridge.connect(new JSONObject().put("requestId", "android-smoke-connect"));
        assertTrue(connected.toString(), connected.getBoolean("success"));

        try {
            Options.Builder builder = new Options.Builder()
                    .servers(host.settings.urls.toArray(new String[0]))
                    .connectionName("swift-wrapper-android-smoke-control")
                    .authHandler(Nats.staticCredentials(credential.getBytes(StandardCharsets.UTF_8)))
                    .connectionTimeout(Duration.ofSeconds(5));
            if (host.settings.tlsFirst) {
                builder.tlsFirst();
            }
            try (Connection control = Nats.connect(builder.build())) {
                String subject = host.settings.devicePrefix(host.appUUID()) + ".commands.status";
                Message reply = control.request(
                        subject,
                        "{\"requestId\":\"android-smoke-command\"}".getBytes(StandardCharsets.UTF_8),
                        Duration.ofSeconds(8)
                );
                assertNotNull("Expected NATS command reply.", reply);
                JSONObject payload = new JSONObject(new String(reply.getData(), StandardCharsets.UTF_8));
                assertEquals("deviceInfoGet", payload.getString("action"));
                assertTrue(payload.getBoolean("success"));
                assertEquals("android", payload.getString("platform"));
                assertTrue(payload.has("natsCommand"));
            }

            JSONObject published = bridge.publish(new JSONObject()
                    .put("requestId", "android-smoke-publish")
                    .put("subject", host.settings.devicePrefix(host.appUUID()) + ".events.demo")
                    .put("payload", "{\"ok\":true}"));
            assertTrue(published.toString(), published.getBoolean("success"));
        } finally {
            bridge.disconnect(new JSONObject().put("requestId", "android-smoke-disconnect"));
        }
    }

    private static ArrayList<String> smokeURLs() {
        String raw = System.getenv().getOrDefault(
                "NATS_SMOKE_URLS",
                System.getenv().getOrDefault(
                        "TEST_RUNNER_NATS_SMOKE_URLS",
                        ""
                )
        );
        ArrayList<String> urls = new ArrayList<>();
        for (String item : raw.split(",")) {
            String trimmed = item.trim();
            if (!trimmed.isEmpty()) {
                urls.add(trimmed);
            }
        }
        return urls;
    }

    private static String smokeCredential() throws Exception {
        String encoded = firstEnvironmentValue("NATS_SMOKE_CREDS_B64", "TEST_RUNNER_NATS_SMOKE_CREDS_B64");
        if (encoded != null && !encoded.trim().isEmpty()) {
            return new String(Base64.getDecoder().decode(encoded.replaceAll("\\s+", "")), StandardCharsets.UTF_8);
        }
        String path = firstEnvironmentValue("NATS_SMOKE_CREDS_PATH", "TEST_RUNNER_NATS_SMOKE_CREDS_PATH");
        if (path != null && !path.trim().isEmpty()) {
            return new String(Files.readAllBytes(Path.of(path.trim())), StandardCharsets.UTF_8);
        }
        return "";
    }

    private static String firstEnvironmentValue(String first, String second) {
        String value = System.getenv(first);
        if (value != null && !value.trim().isEmpty()) {
            return value;
        }
        return System.getenv(second);
    }

    private static final class StaticCredentialStore implements AndroidNatsBridge.CredentialStore {
        private final String credential;

        StaticCredentialStore(String credential) {
            this.credential = credential;
        }

        @Override
        public void store(String credential, String method) {
        }

        @Override
        public boolean hasCredential() {
            return !credential.isEmpty();
        }

        @Override
        public String loadCredential() {
            return credential;
        }

        @Override
        public void clear() {
        }
    }

    private static final class FakeHost implements AndroidNatsBridge.Host {
        final AndroidNatsSettings settings = new AndroidNatsSettings();

        @Override
        public String securityToken() {
            return "smoke-token";
        }

        @Override
        public String appUUID() {
            return "android-smoke";
        }

        @Override
        public AndroidNatsSettings natsSettings() {
            return settings;
        }

        @Override
        public void persistNatsSettings(AndroidNatsSettings settings) {
        }

        @Override
        public JSONObject executeNatsCommand(JSONObject command) throws org.json.JSONException {
            return new JSONObject()
                    .put("action", command.optString("action"))
                    .put("requestId", command.optString("requestId"))
                    .put("success", true)
                    .put("platform", "android");
        }
    }
}
