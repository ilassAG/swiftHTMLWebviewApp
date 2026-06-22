package com.ilass.swifthtmlwebviewapp;

import android.content.res.Configuration;
import android.util.DisplayMetrics;

final class AndroidConfigPairingLayout {
    private AndroidConfigPairingLayout() {}

    static Spec from(DisplayMetrics metrics, int orientation) {
        int widthPixels = metrics != null ? metrics.widthPixels : 0;
        int heightPixels = metrics != null ? metrics.heightPixels : 0;
        float density = metrics != null ? metrics.density : 1f;
        return from(widthPixels, heightPixels, density, orientation);
    }

    static Spec from(int widthPixels, int heightPixels, float density, int orientation) {
        float safeDensity = Math.max(density, 1f);
        float widthDp = Math.max(widthPixels, 1) / safeDensity;
        float heightDp = Math.max(heightPixels, 1) / safeDensity;
        float smallestWidthDp = Math.min(widthDp, heightDp);
        boolean landscape = orientation == Configuration.ORIENTATION_LANDSCAPE || widthPixels > heightPixels;
        boolean twoColumn = landscape && widthDp >= 560f;

        if (twoColumn) {
            int availableHeight = Math.round(heightDp);
            int qr = clamp(availableHeight - 170, 170, 270);
            int scanner = clamp(availableHeight - 210, 120, 230);
            return new Spec(
                    true,
                    14,
                    16,
                    qr,
                    scanner,
                    2,
                    22,
                    48,
                    10
            );
        }

        boolean compact = smallestWidthDp < 520f;
        return new Spec(
                false,
                compact ? 14 : 22,
                compact ? 12 : 24,
                compact ? 180 : 270,
                compact ? 150 : 190,
                compact ? 2 : 5,
                compact ? 20 : 24,
                48,
                compact ? 8 : 14
        );
    }

    private static int clamp(int value, int min, int max) {
        return Math.max(min, Math.min(max, value));
    }

    static final class Spec {
        final boolean twoColumn;
        final int cardPaddingDp;
        final int containerPaddingDp;
        final int qrSizeDp;
        final int scannerHeightDp;
        final int payloadMaxLines;
        final int titleTextSizeSp;
        final int controlsHeightDp;
        final int verticalGapDp;

        Spec(
                boolean twoColumn,
                int cardPaddingDp,
                int containerPaddingDp,
                int qrSizeDp,
                int scannerHeightDp,
                int payloadMaxLines,
                int titleTextSizeSp,
                int controlsHeightDp,
                int verticalGapDp
        ) {
            this.twoColumn = twoColumn;
            this.cardPaddingDp = cardPaddingDp;
            this.containerPaddingDp = containerPaddingDp;
            this.qrSizeDp = qrSizeDp;
            this.scannerHeightDp = scannerHeightDp;
            this.payloadMaxLines = payloadMaxLines;
            this.titleTextSizeSp = titleTextSizeSp;
            this.controlsHeightDp = controlsHeightDp;
            this.verticalGapDp = verticalGapDp;
        }

        int estimatedDialogHeightDp() {
            int titleAndMargins = 44;
            int payloadAndStatus = payloadMaxLines * 13 + 30;
            if (twoColumn) {
                int leftColumn = qrSizeDp + payloadAndStatus + verticalGapDp;
                int rightColumn = scannerHeightDp + controlsHeightDp + verticalGapDp;
                return containerPaddingDp * 2 + cardPaddingDp * 2 + titleAndMargins + Math.max(leftColumn, rightColumn);
            }
            return containerPaddingDp * 2
                    + cardPaddingDp * 2
                    + titleAndMargins
                    + qrSizeDp
                    + scannerHeightDp
                    + controlsHeightDp
                    + payloadAndStatus
                    + verticalGapDp * 4;
        }
    }
}
