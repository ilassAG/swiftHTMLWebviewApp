package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import android.content.res.Configuration;

import org.junit.Test;

public class AndroidConfigPairingLayoutTest {
    @Test
    public void tabletPortraitKeepsLargeQrInSingleColumn() {
        AndroidConfigPairingLayout.Spec spec = AndroidConfigPairingLayout.from(
                800,
                1340,
                213f / 160f,
                Configuration.ORIENTATION_PORTRAIT
        );

        assertFalse(spec.twoColumn);
        assertTrue(spec.qrSizeDp >= 260);
        assertTrue(spec.estimatedDialogHeightDp() < 1006);
    }

    @Test
    public void tabletLandscapeUsesTwoColumnsAndKeepsControlsVisible() {
        AndroidConfigPairingLayout.Spec spec = AndroidConfigPairingLayout.from(
                1340,
                800,
                213f / 160f,
                Configuration.ORIENTATION_LANDSCAPE
        );

        assertTrue(spec.twoColumn);
        assertTrue(spec.qrSizeDp >= 260);
        assertTrue(spec.estimatedDialogHeightDp() < 602);
    }

    @Test
    public void phoneLandscapeShrinksButStillFitsControls() {
        AndroidConfigPairingLayout.Spec spec = AndroidConfigPairingLayout.from(
                2400,
                1080,
                3f,
                Configuration.ORIENTATION_LANDSCAPE
        );

        assertTrue(spec.twoColumn);
        assertTrue(spec.qrSizeDp >= 170);
        assertTrue(spec.estimatedDialogHeightDp() <= 360);
    }
}
