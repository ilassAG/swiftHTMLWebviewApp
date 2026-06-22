package com.ilass.swifthtmlwebviewapp;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;

final class AndroidBridgeRouter {
    interface Handler {
        void handle(JSONObject message) throws JSONException;
    }

    interface ResultSender {
        void send(JSONObject payload);
    }

    private final Map<String, Handler> handlers;
    private final ResultSender resultSender;

    private AndroidBridgeRouter(Map<String, Handler> handlers, ResultSender resultSender) {
        this.handlers = Collections.unmodifiableMap(new LinkedHashMap<>(handlers));
        this.resultSender = resultSender;
    }

    void postMessage(String rawMessage) {
        try {
            JSONObject message = new JSONObject(rawMessage == null ? "{}" : rawMessage);
            String action = BridgeDispatcher.action(message);
            if (action.isEmpty()) {
                resultSender.send(BridgeDispatcher.missingActionResponse(message));
                return;
            }

            Handler handler = handlers.get(action);
            if (handler == null) {
                resultSender.send(BridgeDispatcher.unknownActionResponse(message, action));
                return;
            }

            handler.handle(message);
        } catch (JSONException error) {
            try {
                resultSender.send(BridgeDispatcher.parseErrorResponse(error.getMessage()));
            } catch (JSONException ignored) {
                // Ignore secondary JSON failure.
            }
        }
    }

    Set<String> actions() {
        return handlers.keySet();
    }

    static final class Builder {
        private final Map<String, Handler> handlers = new LinkedHashMap<>();
        private final ResultSender resultSender;

        Builder(ResultSender resultSender) {
            this.resultSender = resultSender;
        }

        Builder on(String action, Handler handler) {
            handlers.put(action, handler);
            return this;
        }

        Builder onAll(Handler handler, String... actions) {
            for (String action : actions) {
                on(action, handler);
            }
            return this;
        }

        AndroidBridgeRouter build() {
            return new AndroidBridgeRouter(handlers, resultSender);
        }
    }
}
