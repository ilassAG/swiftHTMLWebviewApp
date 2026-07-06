package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.json.JSONException;
import org.json.JSONObject;
import org.junit.Test;

import java.nio.charset.StandardCharsets;

public class AndroidNatsBridgeTest {
    @Test
    public void provisionRequiresCurrentSecurityToken() throws Exception {
        FakeHost host = new FakeHost();
        MockCredentialStore credentials = new MockCredentialStore();
        AndroidNatsBridge bridge = new AndroidNatsBridge(host, credentials, new MockConnectionDriver());

        JSONObject response = bridge.provision(new JSONObject()
                .put("requestId", "req-1")
                .put("nats", new JSONObject()
                        .put("enabled", true)
                        .put("auth", new JSONObject()
                                .put("method", "creds")
                                .put("creds", "SECRET"))));

        assertEquals("natsProvision", response.getString("action"));
        assertFalse(response.getBoolean("success"));
        assertEquals("securityToken is required for natsProvision.", response.getString("error"));
        assertFalse(credentials.hasCredential());
    }

    @Test
    public void provisionStoresSecretAndReturnsOnlyRedactedStatus() throws Exception {
        FakeHost host = new FakeHost();
        MockCredentialStore credentials = new MockCredentialStore();
        AndroidNatsBridge bridge = new AndroidNatsBridge(host, credentials, new MockConnectionDriver());

        JSONObject response = bridge.provision(new JSONObject()
                .put("requestId", "req-2")
                .put("token", "current-token")
                .put("nats", new JSONObject()
                        .put("enabled", true)
                        .put("urls", new org.json.JSONArray().put("tls://nats.example.invalid:4222"))
                        .put("auth", new JSONObject()
                                .put("method", "creds")
                                .put("creds", "SECRET-CREDS"))));
        JSONObject auth = response.getJSONObject("nats").getJSONObject("auth");

        assertTrue(response.getBoolean("success"));
        assertEquals("SECRET-CREDS", credentials.credential);
        assertEquals("tls://nats.example.invalid:4222", host.settings.urls.get(0));
        assertTrue(auth.getBoolean("credentialSet"));
        assertFalse(auth.has("creds"));
        assertFalse(response.toString().contains("SECRET-CREDS"));
    }

    @Test
    public void provisionRejectsAuthMethodsNotSupportedByNativeTransport() throws Exception {
        FakeHost host = new FakeHost();
        MockCredentialStore credentials = new MockCredentialStore();
        AndroidNatsBridge bridge = new AndroidNatsBridge(host, credentials, new MockConnectionDriver());

        JSONObject response = bridge.provision(new JSONObject()
                .put("requestId", "req-unsupported-auth")
                .put("token", "current-token")
                .put("nats", new JSONObject()
                        .put("enabled", true)
                        .put("urls", new org.json.JSONArray().put("tls://nats.example.invalid:4222"))
                        .put("auth", new JSONObject()
                                .put("method", "userPassword")
                                .put("password", "SECRET"))));

        assertEquals("natsProvision", response.getString("action"));
        assertFalse(response.getBoolean("success"));
        assertEquals("NATS auth method is not supported by the native transport yet: userPassword.", response.getString("error"));
        assertFalse(credentials.hasCredential());
    }

    @Test
    public void connectUsesProvisionedCredentialThroughDriver() throws Exception {
        FakeHost host = new FakeHost();
        MockCredentialStore credentials = new MockCredentialStore();
        MockConnectionDriver connection = new MockConnectionDriver();
        connection.connectError = null;
        AndroidNatsBridge bridge = new AndroidNatsBridge(host, credentials, connection);

        bridge.provision(new JSONObject()
                .put("token", "current-token")
                .put("nats", new JSONObject()
                        .put("enabled", true)
                        .put("urls", new org.json.JSONArray().put("tls://nats.example.invalid:4222"))
                        .put("auth", new JSONObject()
                                .put("method", "creds")
                                .put("creds", "SECRET-CREDS"))));
        JSONObject response = bridge.connect(new JSONObject().put("requestId", "req-3"));

        assertEquals("natsConnect", response.getString("action"));
        assertTrue(response.getBoolean("success"));
        assertEquals("SECRET-CREDS", connection.lastCredential);
        assertEquals("swift-wrapper-APP-123", connection.lastClientName);
        assertEquals("swift.wrapper.APP-123.status", connection.lastPublishedSubject);
        assertTrue(connection.lastPublishedPayload.contains("\"action\":\"natsStatus\""));
    }

    @Test
    public void connectRejectsEnabledConfigurationWithoutUrl() throws Exception {
        FakeHost host = new FakeHost();
        host.settings.enabled = true;
        host.settings.authMethod = "none";
        MockConnectionDriver connection = new MockConnectionDriver();
        AndroidNatsBridge bridge = new AndroidNatsBridge(host, new MockCredentialStore(), connection);

        JSONObject response = bridge.connect(new JSONObject().put("requestId", "req-empty-url"));

        assertEquals("natsConnect", response.getString("action"));
        assertFalse(response.getBoolean("success"));
        assertEquals("At least one NATS URL is required.", response.getString("error"));
        assertFalse(connection.connected);
    }

    @Test
    public void commandHandlerExecutesAllowedCommandAndPublishesReply() throws Exception {
        FakeHost host = new FakeHost();
        MockCredentialStore credentials = new MockCredentialStore();
        MockConnectionDriver connection = new MockConnectionDriver();
        connection.connectError = null;
        AndroidNatsBridge bridge = new AndroidNatsBridge(host, credentials, connection);

        bridge.provision(new JSONObject()
                .put("token", "current-token")
                .put("nats", new JSONObject()
                        .put("enabled", true)
                        .put("urls", new org.json.JSONArray().put("tls://nats.example.invalid:4222"))
                        .put("auth", new JSONObject()
                                .put("method", "creds")
                                .put("creds", "SECRET-CREDS"))));
        bridge.connect(new JSONObject());
        connection.lastPublishedSubject = null;

        connection.commandHandler.onCommand(
                "swift.wrapper.APP-123.commands.status",
                "{}".getBytes(StandardCharsets.UTF_8),
                "swift.wrapper.APP-123.reply.req-1"
        );

        assertEquals("swift.wrapper.APP-123.reply.req-1", connection.lastPublishedSubject);
        assertTrue(connection.lastPublishedPayload.contains("\"action\":\"deviceInfoGet\""));
        assertTrue(connection.lastPublishedPayload.contains("\"natsCommand\""));
        assertEquals("deviceInfoGet", host.lastCommandAction);
    }

    @Test
    public void commandAliasesAllowQrAndScreenStreamCommands() throws Exception {
        FakeHost host = new FakeHost();
        MockCredentialStore credentials = new MockCredentialStore();
        MockConnectionDriver connection = new MockConnectionDriver();
        connection.connectError = null;
        AndroidNatsBridge bridge = new AndroidNatsBridge(host, credentials, connection);

        bridge.provision(new JSONObject()
                .put("token", "current-token")
                .put("nats", new JSONObject()
                        .put("enabled", true)
                        .put("urls", new org.json.JSONArray().put("tls://nats.example.invalid:4222"))
                        .put("auth", new JSONObject()
                                .put("method", "creds")
                                .put("creds", "SECRET-CREDS"))));
        bridge.connect(new JSONObject());

        connection.commandHandler.onCommand("swift.wrapper.APP-123.commands.qrScan", "{}".getBytes(StandardCharsets.UTF_8), "swift.wrapper.APP-123.reply.qr");
        assertEquals("qrScanImage", host.lastCommandAction);

        connection.commandHandler.onCommand("swift.wrapper.APP-123.commands.qrScanJob", "{}".getBytes(StandardCharsets.UTF_8), "swift.wrapper.APP-123.reply.qr-job");
        assertEquals("qrScanImage", host.lastCommandAction);

        connection.commandHandler.onCommand("swift.wrapper.APP-123.commands.videoStreamStart", "{}".getBytes(StandardCharsets.UTF_8), "swift.wrapper.APP-123.reply.video-start");
        assertEquals("screenStreamStart", host.lastCommandAction);

        connection.commandHandler.onCommand("swift.wrapper.APP-123.commands.videoStreamStop", "{}".getBytes(StandardCharsets.UTF_8), "swift.wrapper.APP-123.reply.video-stop");
        assertEquals("screenStreamStop", host.lastCommandAction);
    }

    @Test
    public void internalBinaryPublishIsScopedToDeviceNamespace() throws Exception {
        FakeHost host = new FakeHost();
        host.settings.enabled = true;
        host.settings.authMethod = "none";
        host.settings.urls.add("tls://nats.example.invalid:4222");
        MockConnectionDriver connection = new MockConnectionDriver();
        connection.connectError = null;
        AndroidNatsBridge bridge = new AndroidNatsBridge(host, new MockCredentialStore(), connection);
        bridge.connect(new JSONObject());

        assertNull(bridge.publishData("swift.wrapper.APP-123.screen.frames", new byte[]{1, 2, 3}));
        assertEquals("swift.wrapper.APP-123.screen.frames", connection.lastPublishedSubject);
        assertEquals(3, connection.lastPublishedBytes.length);

        assertEquals(
                "NATS publish subject is outside the device namespace.",
                bridge.publishData("swift.wrapper.other.screen.frames", new byte[0])
        );
    }

    private static final class FakeHost implements AndroidNatsBridge.Host {
        AndroidNatsSettings settings = new AndroidNatsSettings();

        @Override
        public String securityToken() {
            return "current-token";
        }

        @Override
        public String appUUID() {
            return "APP-123";
        }

        @Override
        public AndroidNatsSettings natsSettings() {
            return settings;
        }

        @Override
        public void persistNatsSettings(AndroidNatsSettings settings) throws JSONException {
            this.settings = settings;
        }

        @Override
        public JSONObject executeNatsCommand(JSONObject command) throws JSONException {
            lastCommandAction = command.optString("action", "");
            return BridgeResponse.base(command, lastCommandAction)
                    .put("success", true)
                    .put("executedBy", "fake-host");
        }

        String lastCommandAction = "";
    }

    private static final class MockCredentialStore implements AndroidNatsBridge.CredentialStore {
        String credential;

        @Override
        public void store(String credential, String method) {
            this.credential = credential;
        }

        @Override
        public boolean hasCredential() {
            return credential != null;
        }

        @Override
        public String loadCredential() {
            return credential != null ? credential : "";
        }

        @Override
        public void clear() {
            credential = null;
        }
    }

    private static final class MockConnectionDriver implements AndroidNatsBridge.ConnectionDriver {
        boolean connected = false;
        String connectError = "offline";
        String lastCredential;
        String lastClientName;
        AndroidNatsBridge.CommandHandler commandHandler;
        String lastPublishedSubject;
        String lastPublishedPayload;
        byte[] lastPublishedBytes;

        @Override
        public boolean isConnected() {
            return connected;
        }

        @Override
        public String connect(AndroidNatsSettings settings, String appUUID, String credential, AndroidNatsBridge.CommandHandler commandHandler) {
            lastCredential = credential;
            lastClientName = settings.clientName(appUUID);
            this.commandHandler = commandHandler;
            connected = connectError == null;
            return connectError;
        }

        @Override
        public void disconnect() {
            connected = false;
        }

        @Override
        public String publish(String subject, byte[] payload) {
            if (!connected) {
                return "offline";
            }
            lastPublishedSubject = subject;
            lastPublishedBytes = payload;
            lastPublishedPayload = new String(payload, StandardCharsets.UTF_8);
            return null;
        }
    }
}
