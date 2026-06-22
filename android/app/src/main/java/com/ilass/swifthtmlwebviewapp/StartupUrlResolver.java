package com.ilass.swifthtmlwebviewapp;

import java.util.ArrayList;
import java.util.Locale;

final class StartupUrlResolver {
    private StartupUrlResolver() {
    }

    static String resolveStartUrl(String configuredValue, String fallbackValue, String localUrl) {
        String value = nonEmpty(configuredValue, fallbackValue);
        return isLocalConfiguredUrl(value, localUrl) ? localUrl : value;
    }

    static ArrayList<String> candidates(
            String primaryValue,
            boolean highAvailabilityEnabled,
            String haUrl2,
            String haUrl3,
            String haUrl4,
            String localUrl
    ) {
        ArrayList<String> candidates = new ArrayList<>();
        addUniqueUrlCandidate(candidates, primaryValue, localUrl);
        if (highAvailabilityEnabled) {
            addUniqueUrlCandidate(candidates, haUrl2, localUrl);
            addUniqueUrlCandidate(candidates, haUrl3, localUrl);
            addUniqueUrlCandidate(candidates, haUrl4, localUrl);
        }
        if (candidates.isEmpty()) {
            candidates.add(localUrl);
        }
        return candidates;
    }

    static boolean isLocalConfiguredUrl(String value, String localUrl) {
        String normalized = value != null ? value.trim().toLowerCase(Locale.US) : "";
        return normalized.isEmpty()
                || "local".equals(normalized)
                || localUrl.equals(normalized)
                || normalized.startsWith("file:///android_asset/");
    }

    private static void addUniqueUrlCandidate(ArrayList<String> candidates, String rawValue, String localUrl) {
        String value = nonEmpty(rawValue, "");
        if (value.isEmpty()) {
            return;
        }
        String normalized = isLocalConfiguredUrl(value, localUrl) ? localUrl : value;
        for (String existing : candidates) {
            if (urlIdentity(existing, localUrl).equals(urlIdentity(normalized, localUrl))) {
                return;
            }
        }
        candidates.add(normalized);
    }

    private static String urlIdentity(String value, String localUrl) {
        String trimmed = value != null ? value.trim() : "";
        if (isLocalConfiguredUrl(trimmed, localUrl)) {
            return localUrl;
        }
        return trimmed.endsWith("/") ? trimmed.substring(0, trimmed.length() - 1) : trimmed;
    }

    private static String nonEmpty(String value, String fallback) {
        String trimmed = value != null ? value.trim() : "";
        return trimmed.isEmpty() ? fallback : trimmed;
    }
}
