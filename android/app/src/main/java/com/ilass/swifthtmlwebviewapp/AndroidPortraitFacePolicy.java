package com.ilass.swifthtmlwebviewapp;

import android.graphics.Rect;

import com.google.mlkit.vision.face.Face;
import com.google.mlkit.vision.face.FaceLandmark;

import java.util.List;

final class AndroidPortraitFacePolicy {
    static final float COMPLETE_FACE_FRAME_INSET = 0.04f;
    static final float MINIMUM_COMPLETE_FACE_SIZE = 0.12f;

    private AndroidPortraitFacePolicy() {
    }

    static int statusFaceCount(List<Face> faces, int imageWidth, int imageHeight) {
        if (faces == null || faces.isEmpty()) {
            return 0;
        }
        int completeCount = 0;
        for (Face face : faces) {
            if (isCompleteFace(face, imageWidth, imageHeight)) {
                completeCount += 1;
            }
        }
        if (completeCount == faces.size()) {
            return completeCount;
        }
        return completeCount > 0 ? faces.size() : 0;
    }

    static boolean isCompleteFace(Face face, int imageWidth, int imageHeight) {
        if (face == null || imageWidth <= 0 || imageHeight <= 0) {
            return false;
        }
        Rect box = face.getBoundingBox();
        return isCompleteGeometry(
                box.left / (float) imageWidth,
                box.top / (float) imageHeight,
                box.right / (float) imageWidth,
                box.bottom / (float) imageHeight,
                face.getLandmark(FaceLandmark.LEFT_EYE) != null,
                face.getLandmark(FaceLandmark.RIGHT_EYE) != null,
                face.getLandmark(FaceLandmark.NOSE_BASE) != null,
                face.getLandmark(FaceLandmark.MOUTH_BOTTOM) != null
                        || face.getLandmark(FaceLandmark.MOUTH_LEFT) != null
                        || face.getLandmark(FaceLandmark.MOUTH_RIGHT) != null
        );
    }

    static boolean isCompleteGeometry(
            float left,
            float top,
            float right,
            float bottom,
            boolean hasLeftEye,
            boolean hasRightEye,
            boolean hasNose,
            boolean hasMouth
    ) {
        float width = Math.max(0f, right - left);
        float height = Math.max(0f, bottom - top);
        return left >= COMPLETE_FACE_FRAME_INSET
                && top >= COMPLETE_FACE_FRAME_INSET
                && right <= 1f - COMPLETE_FACE_FRAME_INSET
                && bottom <= 1f - COMPLETE_FACE_FRAME_INSET
                && width >= MINIMUM_COMPLETE_FACE_SIZE
                && height >= MINIMUM_COMPLETE_FACE_SIZE
                && hasLeftEye
                && hasRightEye
                && hasNose
                && hasMouth;
    }
}
