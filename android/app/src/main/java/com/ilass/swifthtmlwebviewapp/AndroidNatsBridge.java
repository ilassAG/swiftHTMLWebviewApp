package com.ilass.swifthtmlwebviewapp;

import org.json.JSONException;
import org.json.JSONObject;

import java.nio.charset.StandardCharsets;

final class AndroidNatsBridge {
    interface Host {
        String securityToken();

        String appUUID();

        AndroidNatsSettings natsSettings();

        void persistNatsSettings(AndroidNatsSettings settings) throws JSONException;

        JSONObject executeNatsCommand(JSONObject command) throws JSONException;
    }

    interface CredentialStore {
        void store(String credential, String method) throws Exception;

        boolean hasCredential();

        String loadCredential();

        void clear();
    }

    interface ConnectionDriver {
        boolean isConnected();

        String connect(AndroidNatsSettings settings, String appUUID, String credential, CommandHandler commandHandler);

        void disconnect();

        String publish(String subject, byte[] payload);
    }

    interface CommandHandler {
        void onCommand(String subject, byte[] payload, String replyTo);
    }

    static final class UnavailableConnectionDriver implements ConnectionDriver {
        private boolean connected = false;

        @Override
        public boolean isConnected() {
            return connected;
        }

        @Override
        public String connect(AndroidNatsSettings settings, String appUUID, String credential, CommandHandler commandHandler) {
            connected = false;
            return "NATS transport is not linked in this build.";
        }

        @Override
        public void disconnect() {
            connected = false;
        }

        @Override
        public String publish(String subject, byte[] payload) {
            return "NATS transport is not linked in this build.";
        }
    }

    private final Host host;
    private final CredentialStore credentialStore;
    private final ConnectionDriver connection;
    private String lastError = "";

    AndroidNatsBridge(Host host, CredentialStore credentialStore, ConnectionDriver connection) {
        this.host = host;
        this.credentialStore = credentialStore;
        this.connection = connection;
    }

    JSONObject statusSnapshot() throws JSONException {
        return host.natsSettings().redactedSnapshot(
                host.appUUID(),
                credentialStore.hasCredential(),
                connection.isConnected(),
                lastError
        );
    }

    JSONObject provision(JSONObject message) throws JSONException {
        if (!hasValidToken(message)) {
            return BridgeResponse.error(message, "natsProvision", "securityToken is required for natsProvision.");
        }
        JSONObject nats = message.optJSONObject("nats");
        if (nats == null) {
            return BridgeResponse.error(message, "natsProvision", "nats payload is required.");
        }
        try {
            AndroidNatsSettings parsed = AndroidNatsSettings.fromPayload(nats, host.natsSettings());
            if (parsed.authRequiresSecret()) {
                String secret = secretFromPayload(nats, parsed.authMethod);
                if (secret.isEmpty()) {
                    return BridgeResponse.error(message, "natsProvision", "NATS credential is required for auth method " + parsed.authMethod + ".");
                }
                credentialStore.store(secret, parsed.authMethod);
            } else {
                credentialStore.clear();
            }
            host.persistNatsSettings(parsed);
            lastError = "";
            return response(message, "natsProvision", true);
        } catch (Exception error) {
            lastError = error.getMessage() != null ? error.getMessage() : String.valueOf(error);
            return BridgeResponse.error(message, "natsProvision", lastError);
        }
    }

    JSONObject status(JSONObject message) throws JSONException {
        return response(message, "natsStatus", true);
    }

    JSONObject connect(JSONObject message) throws JSONException {
        AndroidNatsSettings settings = host.natsSettings();
        if (!settings.enabled) {
            lastError = "NATS is not enabled.";
            return response(message, "natsConnect", false);
        }
        if (settings.urls.isEmpty()) {
            lastError = "At least one NATS URL is required.";
            return response(message, "natsConnect", false);
        }
        String credential = credentialStore.loadCredential();
        if (settings.authRequiresSecret() && credential.isEmpty()) {
            lastError = "NATS credential is not provisioned.";
            return response(message, "natsConnect", false);
        }
        String error = connection.connect(settings, host.appUUID(), credential, this::handleCommand);
        if (error != null && !error.isEmpty()) {
            lastError = error;
            return response(message, "natsConnect", false);
        }
        lastError = "";
        publishStatusEvent();
        return response(message, "natsConnect", true);
    }

    JSONObject disconnect(JSONObject message) throws JSONException {
        connection.disconnect();
        lastError = "";
        return response(message, "natsDisconnect", true);
    }

    JSONObject publish(JSONObject message) throws JSONException {
        if (!connection.isConnected()) {
            lastError = "NATS is not connected.";
            return response(message, "natsPublish", false);
        }
        AndroidNatsSettings settings = host.natsSettings();
        String subject = message.optString("subject", "").trim();
        if (!subject.startsWith(settings.devicePrefix(host.appUUID()) + ".")) {
            lastError = "NATS publish subject is outside the device namespace.";
            return response(message, "natsPublish", false);
        }
        byte[] payload;
        if (message.has("json")) {
            payload = message.opt("json").toString().getBytes(StandardCharsets.UTF_8);
        } else {
            payload = message.optString("payload", message.optString("data", "")).getBytes(StandardCharsets.UTF_8);
        }
        String error = connection.publish(subject, payload);
        if (error != null && !error.isEmpty()) {
            lastError = error;
            return response(message, "natsPublish", false);
        }
        lastError = "";
        JSONObject response = response(message, "natsPublish", true);
        response.put("subject", subject);
        response.put("bytes", payload.length);
        return response;
    }

    String publishData(String subject, byte[] payload) {
        if (!connection.isConnected()) {
            lastError = "NATS is not connected.";
            return lastError;
        }
        String trimmed = subject != null ? subject.trim() : "";
        if (!trimmed.startsWith(host.natsSettings().devicePrefix(host.appUUID()) + ".")) {
            lastError = "NATS publish subject is outside the device namespace.";
            return lastError;
        }
        String error = connection.publish(trimmed, payload != null ? payload : new byte[0]);
        if (error != null && !error.isEmpty()) {
            lastError = error;
            return error;
        }
        lastError = "";
        return null;
    }

    String publishJson(String subject, JSONObject payload) {
        if (payload == null) {
            lastError = "NATS JSON payload is not serializable.";
            return lastError;
        }
        return publishData(subject, payload.toString().getBytes(StandardCharsets.UTF_8));
    }

    private JSONObject response(JSONObject message, String action, boolean success) throws JSONException {
        JSONObject response = BridgeResponse.base(message, action);
        response.put("success", success);
        response.put("nats", statusSnapshot());
        if (!success && !lastError.isEmpty()) {
            response.put("error", lastError);
        }
        return response;
    }

    private void handleCommand(String subject, byte[] payload, String transportReplyTo) {
        try {
            JSONObject command = commandFromPayload(payload);
            normalizeCommandAction(command, subject);
            String action = command.optString("action", "");
            if (!isAllowedCommand(action)) {
                publishCommandResponse(command, subject, transportReplyTo,
                        BridgeResponse.error(command, action.isEmpty() ? "natsCommand" : action, "NATS command is not allowed: " + action));
                return;
            }
            JSONObject response = host.executeNatsCommand(command);
            publishCommandResponse(command, subject, transportReplyTo, response);
        } catch (Exception error) {
            try {
                JSONObject command = new JSONObject();
                JSONObject response = BridgeResponse.error(command, "natsCommand", error.getMessage() != null ? error.getMessage() : String.valueOf(error));
                publishCommandResponse(command, subject, transportReplyTo, response);
            } catch (JSONException ignored) {
                lastError = error.getMessage() != null ? error.getMessage() : String.valueOf(error);
            }
        }
    }

    private JSONObject commandFromPayload(byte[] payload) throws JSONException {
        String raw = payload != null ? new String(payload, StandardCharsets.UTF_8).trim() : "";
        if (raw.isEmpty()) {
            return new JSONObject();
        }
        return new JSONObject(raw);
    }

    private void normalizeCommandAction(JSONObject command, String subject) throws JSONException {
        String action = command.optString("action", "").trim();
        if (action.isEmpty()) {
            action = actionFromCommandSubject(subject);
        }
        if ("status".equals(action)) {
            action = "deviceInfoGet";
        } else if ("settings".equals(action)) {
            action = "settingsGet";
        } else if ("screenshot".equals(action)) {
            action = "screenshotGet";
        } else if ("qrScan".equals(action) || "qrCodeScan".equals(action) || "qrScanImage".equals(action)) {
            action = "qrScanImage";
        } else if ("screenStream".equals(action) || "videoStreamStart".equals(action)) {
            action = "screenStreamStart";
        } else if ("videoStreamStop".equals(action)) {
            action = "screenStreamStop";
        }
        if (!action.isEmpty()) {
            command.put("action", action);
        }
    }

    private String actionFromCommandSubject(String subject) {
        String prefix = host.natsSettings().devicePrefix(host.appUUID()) + ".commands.";
        if (subject != null && subject.startsWith(prefix)) {
            return subject.substring(prefix.length()).trim();
        }
        return "";
    }

    private boolean isAllowedCommand(String action) {
        return "natsStatus".equals(action)
                || "deviceInfoGet".equals(action)
                || "settingsGet".equals(action)
                || "settingsSet".equals(action)
                || "screenshotGet".equals(action)
                || "qrScanImage".equals(action)
                || "screenStreamStart".equals(action)
                || "screenStreamStop".equals(action)
                || "reload".equals(action);
    }

    private void publishCommandResponse(JSONObject command, String commandSubject, String transportReplyTo, JSONObject response) throws JSONException {
        JSONObject natsCommand = new JSONObject()
                .put("subject", commandSubject != null ? commandSubject : "");
        if (transportReplyTo != null && !transportReplyTo.trim().isEmpty()) {
            natsCommand.put("transportReplyTo", transportReplyTo.trim());
        }
        response.put("natsCommand", natsCommand);
        String transportReplySubject = transportReplyTo != null ? transportReplyTo.trim() : "";
        String explicitReplySubject = command.optString("replyTo", "").trim();
        String responseSubject = !transportReplySubject.isEmpty()
                ? transportReplySubject
                : !explicitReplySubject.isEmpty()
                        ? explicitReplySubject
                        : host.natsSettings().responseSubject(host.appUUID());
        String publishError = connection.publish(responseSubject, response.toString().getBytes(StandardCharsets.UTF_8));
        if (publishError != null && !publishError.isEmpty()) {
            lastError = publishError;
        }
    }

    private void publishStatusEvent() {
        try {
            JSONObject response = response(new JSONObject(), "natsStatus", true);
            connection.publish(host.natsSettings().statusSubject(host.appUUID()), response.toString().getBytes(StandardCharsets.UTF_8));
        } catch (JSONException error) {
            lastError = error.getMessage() != null ? error.getMessage() : String.valueOf(error);
        }
    }

    private boolean hasValidToken(JSONObject message) {
        String token = message.optString("token", message.optString("securityToken", "")).trim();
        return !token.isEmpty() && token.equals(host.securityToken());
    }

    private String secretFromPayload(JSONObject nats, String authMethod) {
        JSONObject auth = nats.optJSONObject("auth");
        if (auth == null) {
            return "";
        }
        if ("creds".equals(authMethod)) {
            return auth.optString("creds", auth.optString("credentials", "")).trim();
        }
        if ("token".equals(authMethod)) {
            return auth.optString("token", "").trim();
        }
        if ("userPassword".equals(authMethod)) {
            return auth.optString("password", "").trim();
        }
        if ("nkey".equals(authMethod)) {
            return auth.optString("seed", auth.optString("nkey", "")).trim();
        }
        if ("tlsCertificate".equals(authMethod)) {
            return auth.optString("privateKey", auth.optString("p12", auth.optString("pkcs12", ""))).trim();
        }
        return "";
    }
}
