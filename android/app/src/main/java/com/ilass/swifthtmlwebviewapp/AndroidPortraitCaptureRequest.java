package com.ilass.swifthtmlwebviewapp;

import org.json.JSONObject;

final class AndroidPortraitCaptureRequest {
    final JSONObject source;
    final String action;
    final String outputType;
    final boolean removeBackground;
    final boolean cropTransparent;
    final String background;
    final String backgroundColor;
    final String camera;
    final int requiredFaces;
    final long countdownMs;
    final int variationCount;
    final long captureIntervalMs;
    final boolean faceCenteredCrop;
    final boolean mirrorOutput;

    private AndroidPortraitCaptureRequest(
            JSONObject source,
            String action,
            String outputType,
            boolean removeBackground,
            boolean cropTransparent,
            String background,
            String backgroundColor,
            String camera,
            int requiredFaces,
            long countdownMs,
            int variationCount,
            long captureIntervalMs,
            boolean faceCenteredCrop,
            boolean mirrorOutput
    ) {
        this.source = source;
        this.action = action;
        this.outputType = outputType;
        this.removeBackground = removeBackground;
        this.cropTransparent = cropTransparent;
        this.background = background;
        this.backgroundColor = backgroundColor;
        this.camera = camera;
        this.requiredFaces = requiredFaces;
        this.countdownMs = countdownMs;
        this.variationCount = variationCount;
        this.captureIntervalMs = captureIntervalMs;
        this.faceCenteredCrop = faceCenteredCrop;
        this.mirrorOutput = mirrorOutput;
    }

    static AndroidPortraitCaptureRequest from(JSONObject request) {
        JSONObject source = request != null ? request : new JSONObject();
        boolean removeBackground = boolValue(firstPresent(source, "removeBackground"), false);
        String background = stringValue(firstPresent(source, "background"), "transparent").trim().toLowerCase();
        if (!"color".equals(background)) {
            background = "transparent";
        }
        String defaultOutput = removeBackground && "transparent".equals(background) ? "png" : "jpeg";
        String outputType = normalizeOutputType(firstPresent(source, "outputType"), defaultOutput);
        String camera = stringValue(firstPresent(source, "camera"), "front").trim().toLowerCase();
        if (!"back".equals(camera)) {
            camera = "front";
        }
        String crop = stringValue(firstPresent(source, "crop"), "squareFaceCentered").trim().toLowerCase();
        return new AndroidPortraitCaptureRequest(
                source,
                stringValue(firstPresent(source, "action"), "portraitCapture"),
                outputType,
                removeBackground,
                boolValue(firstPresent(source, "cropTransparent"), false),
                background,
                stringValue(firstPresent(source, "backgroundColor"), "#FFFFFF"),
                camera,
                clampedInt(firstPresent(source, "requiredFaces", "amountFaces"), 1, 1, 8),
                Math.round(clampedDouble(firstPresent(source, "countdownSeconds", "secondsDelay"), 3, 0, 15) * 1000),
                clampedInt(firstPresent(source, "variationCount", "withVariation"), 4, 1, 8),
                Math.round(clampedDouble(firstPresent(source, "captureIntervalMs", "burstIntervalMs", "variationIntervalMs"), 200, 50, 2000)),
                !"none".equals(crop),
                boolValue(firstPresent(source, "mirrorOutput", "mirror"), false)
        );
    }

    String responseFormat(boolean backgroundRemoved) {
        if (backgroundRemoved && "transparent".equals(background)) {
            return "png";
        }
        return "png".equals(outputType) ? "png" : "jpeg";
    }

    long preCaptureLeadMs() {
        return variationCount > 1 ? captureIntervalMs : 0;
    }

    long[] captureOffsetsMs() {
        long[] offsets = new long[variationCount];
        for (int i = 0; i < variationCount; i += 1) {
            offsets[i] = captureIntervalMs * i;
        }
        return offsets;
    }

    int defaultSelectedIndex() {
        return variationCount > 1 ? Math.min(1, variationCount - 1) : 0;
    }

    private static Object firstPresent(JSONObject source, String... keys) {
        if (source == null) {
            return null;
        }
        for (String key : keys) {
            if (source.has(key)) {
                return source.opt(key);
            }
        }
        return null;
    }

    private static String normalizeOutputType(Object value, String defaultValue) {
        String normalized = stringValue(value, defaultValue).trim().toLowerCase();
        return "png".equals(normalized) ? "png" : "jpeg";
    }

    private static String stringValue(Object value, String defaultValue) {
        if (value == null || JSONObject.NULL.equals(value)) {
            return defaultValue;
        }
        String string = String.valueOf(value).trim();
        return string.isEmpty() ? defaultValue : string;
    }

    private static int clampedInt(Object value, int defaultValue, int min, int max) {
        int parsed = defaultValue;
        if (value instanceof Number) {
            parsed = ((Number) value).intValue();
        } else if (value != null && !JSONObject.NULL.equals(value)) {
            try {
                parsed = Integer.parseInt(String.valueOf(value).trim());
            } catch (NumberFormatException ignored) {
                parsed = defaultValue;
            }
        }
        return Math.max(min, Math.min(max, parsed));
    }

    private static double clampedDouble(Object value, double defaultValue, double min, double max) {
        double parsed = defaultValue;
        if (value instanceof Number) {
            parsed = ((Number) value).doubleValue();
        } else if (value != null && !JSONObject.NULL.equals(value)) {
            try {
                parsed = Double.parseDouble(String.valueOf(value).trim());
            } catch (NumberFormatException ignored) {
                parsed = defaultValue;
            }
        }
        return Math.max(min, Math.min(max, parsed));
    }

    private static boolean boolValue(Object value, boolean defaultValue) {
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        if (value == null || JSONObject.NULL.equals(value)) {
            return defaultValue;
        }
        switch (String.valueOf(value).trim().toLowerCase()) {
            case "1":
            case "true":
            case "yes":
            case "y":
            case "on":
                return true;
            case "0":
            case "false":
            case "no":
            case "n":
            case "off":
                return false;
            default:
                return defaultValue;
        }
    }
}
