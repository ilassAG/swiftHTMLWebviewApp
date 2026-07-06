package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.json.JSONObject;
import org.junit.Test;

public class AndroidScreenStreamPayloadTest {
    @Test
    public void streamRequestNormalizesAliasesAndClampsValues() throws Exception {
        AndroidScreenStreamPayload.StreamRequest request = AndroidScreenStreamPayload.streamRequest(new JSONObject()
                .put("url", " ws://example.invalid/screen ")
                .put("format", "JPG")
                .put("fps", 99)
                .put("quality", 2)
                .put("maxWidth", 99));

        assertEquals("ws://example.invalid/screen", request.targetUrl);
        assertEquals("app", request.source);
        assertEquals("websocket", request.transport);
        assertEquals("jpeg", request.format);
        assertEquals(10, request.fps);
        assertEquals(25, request.quality);
        assertEquals(240, request.maxWidth);
        assertTrue(request.hasTargetUrl());
        assertTrue(request.isJpeg());
    }

    @Test
    public void natsStreamRequestUsesSubjectsAndNoTargetUrl() throws Exception {
        AndroidScreenStreamPayload.StreamRequest request = AndroidScreenStreamPayload.streamRequest(new JSONObject()
                .put("transport", "nats")
                .put("subject", "swift.wrapper.APP.screen.frames")
                .put("metaSubject", "swift.wrapper.APP.screen.meta")
                .put("eventSubject", "swift.wrapper.APP.screen.events")
                .put("quality", 65));

        assertEquals("nats", request.transport);
        assertEquals("app", request.source);
        assertTrue(request.isNats());
        assertFalse(request.hasTargetUrl());
        assertEquals("swift.wrapper.APP.screen.frames", request.subject);
        assertEquals("swift.wrapper.APP.screen.meta", request.metaSubject);
        assertEquals("swift.wrapper.APP.screen.events", request.eventSubject);
        assertEquals(65, request.quality);
    }

    @Test
    public void streamRequestKeepsUnsupportedFormatForErrorPath() throws Exception {
        AndroidScreenStreamPayload.StreamRequest request = AndroidScreenStreamPayload.streamRequest(new JSONObject()
                .put("targetUrl", "ws://example.invalid/screen")
                .put("format", "png"));

        assertEquals("png", request.format);
        assertFalse(request.isJpeg());
    }

    @Test
    public void startAndStopAcksUseCommonBridgeShape() throws Exception {
        JSONObject source = new JSONObject().put("requestId", "req-stream");
        AndroidScreenStreamPayload.StreamRequest request = AndroidScreenStreamPayload.streamRequest(new JSONObject()
                .put("targetUrl", "ws://example.invalid/screen")
                .put("fps", 4)
                .put("quality", 70)
                .put("maxWidth", 800));

        JSONObject start = AndroidScreenStreamPayload.startAck(source, request);
        assertEquals("android", start.getString("platform"));
        assertEquals("screenStreamStart", start.getString("action"));
        assertEquals("req-stream", start.getString("requestId"));
        assertTrue(start.getBoolean("success"));
        assertEquals("app", start.getString("source"));
        assertEquals("websocket", start.getString("transport"));
        assertEquals("jpeg", start.getString("format"));
        assertEquals(4, start.getInt("fps"));
        assertEquals(70, start.getInt("quality"));
        assertEquals(800, start.getInt("maxWidth"));

        JSONObject stop = AndroidScreenStreamPayload.stopAck(source, 12L, 3456L);
        assertEquals("screenStreamStop", stop.getString("action"));
        assertTrue(stop.getBoolean("success"));
        assertEquals(12L, stop.getLong("frames"));
        assertEquals(3456L, stop.getLong("bytes"));
    }

    @Test
    public void natsStartAckIncludesSubjects() throws Exception {
        JSONObject source = new JSONObject().put("requestId", "req-nats-stream");
        AndroidScreenStreamPayload.StreamRequest request = AndroidScreenStreamPayload.streamRequest(new JSONObject()
                .put("transport", "nats")
                .put("subject", "swift.wrapper.APP.screen.frames")
                .put("metaSubject", "swift.wrapper.APP.screen.meta")
                .put("eventSubject", "swift.wrapper.APP.screen.events")
                .put("fps", 3));

        JSONObject start = AndroidScreenStreamPayload.startAck(source, request);

        assertEquals("nats", start.getString("transport"));
        assertFalse(start.has("targetUrl"));
        assertEquals("swift.wrapper.APP.screen.frames", start.getString("subject"));
        assertEquals("swift.wrapper.APP.screen.meta", start.getString("metaSubject"));
        assertEquals("swift.wrapper.APP.screen.events", start.getString("eventSubject"));
        assertEquals(3, start.getInt("fps"));
    }

    @Test
    public void metaEventsAndStatsUseCatalogedEventShapes() throws Exception {
        AndroidScreenStreamPayload.StreamRequest request = AndroidScreenStreamPayload.streamRequest(new JSONObject()
                .put("targetUrl", "ws://example.invalid/screen"));
        JSONObject meta = AndroidScreenStreamPayload.meta(request);
        assertEquals("screenStreamMeta", meta.getString("type"));
        assertEquals("android", meta.getString("platform"));
        assertEquals("app", meta.getString("source"));
        assertEquals("jpeg", meta.getString("format"));

        JSONObject closed = AndroidScreenStreamPayload.event("screenStreamClosed", true, "finished");
        assertEquals("screenStreamClosed", closed.getString("action"));
        assertTrue(closed.getBoolean("success"));
        assertEquals("finished", closed.getString("message"));

        JSONObject error = AndroidScreenStreamPayload.event("screenStreamError", false, "network failed");
        assertEquals("screenStreamError", error.getString("action"));
        assertFalse(error.getBoolean("success"));
        assertEquals("network failed", error.getString("error"));

        JSONObject stats = AndroidScreenStreamPayload.stats(3L, 4096L, 1024L, 1000L, 3500L);
        assertEquals("screenStreamStats", stats.getString("action"));
        assertTrue(stats.getBoolean("success"));
        assertEquals(3L, stats.getLong("frames"));
        assertEquals(4096L, stats.getLong("bytes"));
        assertEquals(1024L, stats.getLong("lastFrameBytes"));
        assertEquals(2.5, stats.getDouble("durationSeconds"), 0.001);
    }
}
