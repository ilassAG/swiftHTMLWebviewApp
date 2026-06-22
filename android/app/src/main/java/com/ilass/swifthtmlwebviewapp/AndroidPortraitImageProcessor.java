package com.ilass.swifthtmlwebviewapp;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Matrix;
import android.graphics.Rect;
import android.util.Base64;

import com.google.mlkit.vision.face.Face;
import com.google.mlkit.vision.segmentation.SegmentationMask;

import java.io.ByteArrayOutputStream;
import java.nio.ByteBuffer;
import java.util.List;

final class AndroidPortraitImageProcessor {
    private AndroidPortraitImageProcessor() {
    }

    static Bitmap rotateAndMirror(Bitmap source, int rotationDegrees, boolean mirror) {
        if (source == null) {
            return null;
        }
        Matrix matrix = new Matrix();
        if (rotationDegrees != 0) {
            matrix.postRotate(rotationDegrees);
        }
        if (mirror) {
            matrix.postScale(-1f, 1f);
        }
        if (matrix.isIdentity()) {
            return source;
        }
        return Bitmap.createBitmap(source, 0, 0, source.getWidth(), source.getHeight(), matrix, true);
    }

    static Bitmap squareFaceCenteredCrop(Bitmap source, List<Face> faces) {
        if (source == null || faces == null || faces.isEmpty()) {
            return source;
        }
        Face target = firstCompleteFace(faces, source.getWidth(), source.getHeight());
        if (target == null) {
            target = faces.get(0);
        }
        Rect box = target.getBoundingBox();
        int faceCenterX = Math.round((box.left + box.right) / 2f);
        int faceCenterY = Math.round((box.top + box.bottom) / 2f);
        int faceSize = Math.max(box.width(), box.height());
        int side = Math.round(faceSize * 2.25f);
        side = Math.max(side, Math.min(source.getWidth(), source.getHeight()) / 2);
        side = Math.min(side, Math.min(source.getWidth(), source.getHeight()));
        int left = clamp(faceCenterX - side / 2, 0, source.getWidth() - side);
        int top = clamp(faceCenterY - Math.round(side * 0.42f), 0, source.getHeight() - side);
        return Bitmap.createBitmap(source, left, top, side, side);
    }

    static Bitmap applySegmentationMask(Bitmap source, SegmentationMask mask, AndroidPortraitCaptureRequest request) {
        int width = source.getWidth();
        int height = source.getHeight();
        int maskWidth = mask.getWidth();
        int maskHeight = mask.getHeight();
        ByteBuffer buffer = mask.getBuffer();
        buffer.rewind();

        boolean transparentBackground = !"color".equalsIgnoreCase(request.background);
        int backgroundColor = parseBackgroundColor(request.backgroundColor);
        Bitmap output = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);

        int minX = width;
        int minY = height;
        int maxX = -1;
        int maxY = -1;

        for (int y = 0; y < height; y += 1) {
            int maskY = Math.min(maskHeight - 1, Math.max(0, Math.round((y / (float) Math.max(1, height - 1)) * (maskHeight - 1))));
            for (int x = 0; x < width; x += 1) {
                int maskX = Math.min(maskWidth - 1, Math.max(0, Math.round((x / (float) Math.max(1, width - 1)) * (maskWidth - 1))));
                float confidence = getMaskConfidence(buffer, maskWidth, maskX, maskY);
                int sourceColor = source.getPixel(x, y);
                int alpha = confidenceToAlpha(confidence);
                int pixel = transparentBackground
                        ? Color.argb(alpha, Color.red(sourceColor), Color.green(sourceColor), Color.blue(sourceColor))
                        : blendOverBackground(sourceColor, backgroundColor, alpha / 255f);
                output.setPixel(x, y, pixel);
                if (alpha > 24) {
                    minX = Math.min(minX, x);
                    minY = Math.min(minY, y);
                    maxX = Math.max(maxX, x);
                    maxY = Math.max(maxY, y);
                }
            }
        }

        if (request.cropTransparent && maxX >= minX && maxY >= minY) {
            int padding = Math.max(8, Math.round(Math.max(width, height) * 0.03f));
            int left = Math.max(0, minX - padding);
            int top = Math.max(0, minY - padding);
            int right = Math.min(width, maxX + padding);
            int bottom = Math.min(height, maxY + padding);
            return Bitmap.createBitmap(output, left, top, Math.max(1, right - left), Math.max(1, bottom - top));
        }
        return output;
    }

    static String dataUrl(Bitmap bitmap, String format) {
        Bitmap.CompressFormat compressFormat = "png".equals(format) ? Bitmap.CompressFormat.PNG : Bitmap.CompressFormat.JPEG;
        int quality = "png".equals(format) ? 100 : 88;
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        bitmap.compress(compressFormat, quality, output);
        String mime = compressFormat == Bitmap.CompressFormat.PNG ? "image/png" : "image/jpeg";
        return "data:" + mime + ";base64," + Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP);
    }

    static Bitmap copyToArgb(Bitmap source) {
        if (source.getConfig() == Bitmap.Config.ARGB_8888) {
            return source;
        }
        Bitmap output = Bitmap.createBitmap(source.getWidth(), source.getHeight(), Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(output);
        canvas.drawBitmap(source, 0, 0, null);
        return output;
    }

    private static Face firstCompleteFace(List<Face> faces, int imageWidth, int imageHeight) {
        for (Face face : faces) {
            if (AndroidPortraitFacePolicy.isCompleteFace(face, imageWidth, imageHeight)) {
                return face;
            }
        }
        return null;
    }

    private static float getMaskConfidence(ByteBuffer buffer, int maskWidth, int x, int y) {
        int index = (y * maskWidth + x) * 4;
        if (index < 0 || index + 4 > buffer.capacity()) {
            return 0f;
        }
        return buffer.getFloat(index);
    }

    private static int confidenceToAlpha(float confidence) {
        float softened = Math.max(0f, Math.min(1f, (confidence - 0.18f) / 0.72f));
        return Math.max(0, Math.min(255, Math.round(softened * 255f)));
    }

    private static int parseBackgroundColor(String raw) {
        try {
            String value = raw == null || raw.trim().isEmpty() ? "#FFFFFF" : raw.trim();
            if (!value.startsWith("#")) {
                value = "#" + value;
            }
            return Color.parseColor(value);
        } catch (Exception ignored) {
            return Color.WHITE;
        }
    }

    private static int blendOverBackground(int foreground, int background, float alpha) {
        float inverse = 1f - alpha;
        int red = Math.round(Color.red(foreground) * alpha + Color.red(background) * inverse);
        int green = Math.round(Color.green(foreground) * alpha + Color.green(background) * inverse);
        int blue = Math.round(Color.blue(foreground) * alpha + Color.blue(background) * inverse);
        return Color.argb(255, red, green, blue);
    }

    private static int clamp(int value, int min, int max) {
        return Math.max(min, Math.min(max, value));
    }
}
