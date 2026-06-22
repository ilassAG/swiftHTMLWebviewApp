package com.ilass.swifthtmlwebviewapp;

import java.util.ArrayList;
import java.util.List;

final class AndroidStartupLoadCoordinator {
    static final String NO_CONFIGURED_URL_REASON = "Keine konfigurierte Server-URL verfuegbar.";
    static final String TIMEOUT_REASON = "Server-Antwort hat zu lange gedauert.";

    interface LocalUrlPolicy {
        boolean isLocal(String url);
    }

    static final class Command {
        enum Kind {
            LOAD_URL,
            SHOW_RECOVERY,
            NONE
        }

        final Kind kind;
        final String url;
        final boolean scheduleTimeout;
        final String reason;
        final ArrayList<String> candidates;

        private Command(
                Kind kind,
                String url,
                boolean scheduleTimeout,
                String reason,
                ArrayList<String> candidates
        ) {
            this.kind = kind;
            this.url = url;
            this.scheduleTimeout = scheduleTimeout;
            this.reason = reason;
            this.candidates = candidates;
        }

        static Command loadUrl(String url, boolean scheduleTimeout) {
            return new Command(Kind.LOAD_URL, url, scheduleTimeout, "", new ArrayList<>());
        }

        static Command showRecovery(String reason, ArrayList<String> candidates) {
            return new Command(Kind.SHOW_RECOVERY, "", false, stringOrDefault(reason), new ArrayList<>(candidates));
        }

        static Command none() {
            return new Command(Kind.NONE, "", false, "", new ArrayList<>());
        }
    }

    private final LocalUrlPolicy localUrlPolicy;
    private final ArrayList<String> candidates = new ArrayList<>();
    private int index = 0;
    private boolean highAvailabilityEnabled = false;
    private boolean showingRecovery = false;

    AndroidStartupLoadCoordinator(LocalUrlPolicy localUrlPolicy) {
        this.localUrlPolicy = localUrlPolicy;
    }

    Command start(List<String> configuredCandidates, boolean highAvailabilityEnabled) {
        this.candidates.clear();
        if (configuredCandidates != null) {
            this.candidates.addAll(configuredCandidates);
        }
        this.index = 0;
        this.highAvailabilityEnabled = highAvailabilityEnabled;
        this.showingRecovery = false;
        return loadCurrentOrRecover(NO_CONFIGURED_URL_REASON);
    }

    Command mainFrameFailed(String reason) {
        return failoverOrRecover(reason);
    }

    Command timeout() {
        return failoverOrRecover(TIMEOUT_REASON);
    }

    private Command failoverOrRecover(String reason) {
        if (showingRecovery) {
            return Command.none();
        }
        if (highAvailabilityEnabled && index + 1 < candidates.size()) {
            index += 1;
            return loadCurrentOrRecover(reason);
        }
        return recover(reason);
    }

    private Command loadCurrentOrRecover(String reason) {
        if (index < 0 || index >= candidates.size()) {
            return recover(reason);
        }
        String url = candidates.get(index);
        showingRecovery = false;
        boolean scheduleTimeout = localUrlPolicy == null || !localUrlPolicy.isLocal(url);
        return Command.loadUrl(url, scheduleTimeout);
    }

    private Command recover(String reason) {
        if (showingRecovery) {
            return Command.none();
        }
        showingRecovery = true;
        return Command.showRecovery(reason, candidates);
    }

    private static String stringOrDefault(String value) {
        return value != null && !value.trim().isEmpty() ? value : NO_CONFIGURED_URL_REASON;
    }
}
