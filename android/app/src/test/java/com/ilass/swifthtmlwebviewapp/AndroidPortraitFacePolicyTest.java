package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class AndroidPortraitFacePolicyTest {
    @Test
    public void acceptsCenteredCompleteFaceGeometry() {
        assertTrue(AndroidPortraitFacePolicy.isCompleteGeometry(
                0.30f,
                0.20f,
                0.70f,
                0.70f,
                true,
                true,
                true,
                true
        ));
    }

    @Test
    public void rejectsFaceTouchingFrameEdge() {
        assertFalse(AndroidPortraitFacePolicy.isCompleteGeometry(
                0.01f,
                0.20f,
                0.45f,
                0.70f,
                true,
                true,
                true,
                true
        ));
    }

    @Test
    public void rejectsSmallFace() {
        assertFalse(AndroidPortraitFacePolicy.isCompleteGeometry(
                0.40f,
                0.40f,
                0.48f,
                0.48f,
                true,
                true,
                true,
                true
        ));
    }

    @Test
    public void rejectsMissingLandmarks() {
        assertFalse(AndroidPortraitFacePolicy.isCompleteGeometry(
                0.30f,
                0.20f,
                0.70f,
                0.70f,
                true,
                false,
                true,
                true
        ));
    }
}
