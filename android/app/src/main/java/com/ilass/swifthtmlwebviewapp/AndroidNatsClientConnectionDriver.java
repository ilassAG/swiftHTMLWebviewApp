package com.ilass.swifthtmlwebviewapp;

import io.nats.client.Connection;
import io.nats.client.Dispatcher;
import io.nats.client.Nats;
import io.nats.client.Options;

import java.nio.charset.StandardCharsets;
import java.time.Duration;

final class AndroidNatsClientConnectionDriver implements AndroidNatsBridge.ConnectionDriver {
    private Connection connection;
    private Dispatcher dispatcher;

    @Override
    public synchronized boolean isConnected() {
        return connection != null && connection.getStatus() == Connection.Status.CONNECTED;
    }

    @Override
    public synchronized String connect(
            AndroidNatsSettings settings,
            String appUUID,
            String credential,
            AndroidNatsBridge.CommandHandler commandHandler
    ) {
        disconnect();
        if (settings.urls.isEmpty()) {
            return "At least one NATS URL is required.";
        }
        try {
            Options.Builder builder = new Options.Builder()
                    .servers(settings.urls.toArray(new String[0]))
                    .connectionName(settings.clientName(appUUID))
                    .maxReconnects(settings.maxReconnects)
                    .reconnectWait(Duration.ofMillis(settings.reconnectWaitMs))
                    .pingInterval(Duration.ofSeconds(settings.pingIntervalSeconds))
                    .connectionTimeout(Duration.ofSeconds(5));

            if (settings.tlsFirst) {
                builder.tlsFirst();
            }
            applyAuth(builder, settings.authMethod, credential);

            connection = Nats.connect(builder.build());
            dispatcher = connection.createDispatcher(message -> {
                if (commandHandler != null) {
                    commandHandler.onCommand(message.getSubject(), message.getData(), message.getReplyTo());
                }
            });
            dispatcher.subscribe(settings.commandSubject(appUUID));
            connection.flush(Duration.ofSeconds(2));
            return null;
        } catch (Exception error) {
            disconnect();
            return error.getMessage() != null ? error.getMessage() : String.valueOf(error);
        }
    }

    @Override
    public synchronized void disconnect() {
        if (connection != null && dispatcher != null) {
            try {
                connection.closeDispatcher(dispatcher);
            } catch (Exception ignored) {
                // Dispatcher may already be closed by connection shutdown.
            }
        }
        dispatcher = null;
        if (connection != null) {
            try {
                connection.close();
            } catch (InterruptedException error) {
                Thread.currentThread().interrupt();
            }
        }
        connection = null;
    }

    @Override
    public synchronized String publish(String subject, byte[] payload) {
        if (!isConnected()) {
            return "NATS is not connected.";
        }
        try {
            connection.publish(subject, payload != null ? payload : new byte[0]);
            connection.flush(Duration.ofSeconds(2));
            return null;
        } catch (Exception error) {
            return error.getMessage() != null ? error.getMessage() : String.valueOf(error);
        }
    }

    private void applyAuth(Options.Builder builder, String authMethod, String credential) {
        String secret = credential != null ? credential : "";
        if ("creds".equals(authMethod)) {
            builder.authHandler(Nats.staticCredentials(secret.getBytes(StandardCharsets.UTF_8)));
        } else if ("token".equals(authMethod)) {
            builder.token(secret.toCharArray());
        } else if ("nkey".equals(authMethod)) {
            builder.authHandler(Nats.staticCredentials(null, secret.toCharArray()));
        } else if ("userPassword".equals(authMethod) || "tlsCertificate".equals(authMethod)) {
            throw new IllegalArgumentException("NATS auth method is not supported by the Android transport yet: " + authMethod);
        }
    }
}
