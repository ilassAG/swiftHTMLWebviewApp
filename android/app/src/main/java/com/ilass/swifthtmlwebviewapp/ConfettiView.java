package com.ilass.swifthtmlwebviewapp;

import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.view.View;
import android.view.ViewGroup;
import android.view.animation.DecelerateInterpolator;

import java.util.ArrayList;
import java.util.List;
import java.util.Random;

public class ConfettiView extends View {
    private static final int[] COLORS = {
            Color.rgb(255, 204, 64),
            Color.rgb(52, 199, 89),
            Color.rgb(0, 122, 255),
            Color.rgb(255, 45, 85),
            Color.rgb(175, 82, 222),
            Color.rgb(255, 149, 0)
    };

    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final List<Piece> pieces = new ArrayList<>();
    private final Random random = new Random();
    private float progress = 0f;

    public ConfettiView(Context context) {
        super(context);
        setWillNotDraw(false);
    }

    public void start(Runnable onEnd) {
        post(() -> {
            createPieces();
            ValueAnimator animator = ValueAnimator.ofFloat(0f, 1f);
            animator.setDuration(1450L);
            animator.setInterpolator(new DecelerateInterpolator(0.85f));
            animator.addUpdateListener(animation -> {
                progress = (float) animation.getAnimatedValue();
                invalidate();
            });
            animator.addListener(new android.animation.AnimatorListenerAdapter() {
                @Override
                public void onAnimationEnd(android.animation.Animator animation) {
                    if (onEnd != null) {
                        onEnd.run();
                    }
                }
            });
            animator.start();
        });
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        for (Piece piece : pieces) {
            float t = progress;
            float x = piece.startX + piece.velocityX * t;
            float y = piece.startY + piece.velocityY * t + getHeight() * 0.55f * t * t;
            float alpha = Math.max(0f, 1f - Math.max(0f, t - 0.72f) / 0.28f);
            paint.setColor(piece.color);
            paint.setAlpha((int) (255 * alpha));
            canvas.save();
            canvas.rotate(piece.rotation + 460f * t * piece.rotationDirection, x, y);
            canvas.drawRoundRect(
                    x - piece.width / 2f,
                    y - piece.height / 2f,
                    x + piece.width / 2f,
                    y + piece.height / 2f,
                    piece.height / 3f,
                    piece.height / 3f,
                    paint
            );
            canvas.restore();
        }
    }

    private void createPieces() {
        pieces.clear();
        int width = Math.max(getWidth(), 1);
        int height = Math.max(getHeight(), 1);
        int count = 120;
        for (int i = 0; i < count; i++) {
            Piece piece = new Piece();
            piece.startX = width * (0.18f + random.nextFloat() * 0.64f);
            piece.startY = height * (0.12f + random.nextFloat() * 0.12f);
            piece.velocityX = (random.nextFloat() - 0.5f) * width * 1.15f;
            piece.velocityY = -height * (0.18f + random.nextFloat() * 0.42f);
            piece.width = 8f + random.nextFloat() * 18f;
            piece.height = 5f + random.nextFloat() * 13f;
            piece.rotation = random.nextFloat() * 360f;
            piece.rotationDirection = random.nextBoolean() ? 1f : -1f;
            piece.color = COLORS[random.nextInt(COLORS.length)];
            pieces.add(piece);
        }
    }

    public static void attachAndStart(ActivityHost host, Runnable onEnd) {
        ConfettiView view = new ConfettiView(host.context());
        host.addOverlay(view);
        view.start(() -> {
            host.removeOverlay(view);
            if (onEnd != null) {
                onEnd.run();
            }
        });
    }

    public interface ActivityHost {
        Context context();
        void addOverlay(View view);
        void removeOverlay(View view);
    }

    private static class Piece {
        float startX;
        float startY;
        float velocityX;
        float velocityY;
        float width;
        float height;
        float rotation;
        float rotationDirection;
        int color;
    }
}
