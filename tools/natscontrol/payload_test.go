package main

import (
	"os"
	"strings"
	"testing"
)

func TestBuildScreenStreamStartDefaultsAndClamps(t *testing.T) {
	subjects := subjectSet{
		Frames: "swift.wrapper.APP.screen.frames",
		Meta:   "swift.wrapper.APP.screen.meta",
		Events: "swift.wrapper.APP.screen.events",
	}
	payload := buildScreenStreamStart(subjects, streamStartOptions{
		RequestID: "req-1",
		FPS:       99,
		Quality:   3,
		MaxWidth:  9000,
		Format:    "jpg",
	})
	assertPayloadValue(t, payload, "action", "screenStreamStart")
	assertPayloadValue(t, payload, "requestId", "req-1")
	assertPayloadValue(t, payload, "source", "app")
	assertPayloadValue(t, payload, "transport", "nats")
	assertPayloadValue(t, payload, "subject", "swift.wrapper.APP.screen.frames")
	assertPayloadValue(t, payload, "metaSubject", "swift.wrapper.APP.screen.meta")
	assertPayloadValue(t, payload, "eventSubject", "swift.wrapper.APP.screen.events")
	assertPayloadValue(t, payload, "format", "jpeg")
	if payload["fps"] != 10 {
		t.Fatalf("fps = %v", payload["fps"])
	}
	if payload["quality"] != 25 {
		t.Fatalf("quality = %v", payload["quality"])
	}
	if payload["maxWidth"] != 1920 {
		t.Fatalf("maxWidth = %v", payload["maxWidth"])
	}
}

func TestBuildScreenStreamStop(t *testing.T) {
	payload := buildScreenStreamStop("stop-1")
	assertPayloadValue(t, payload, "action", "screenStreamStop")
	assertPayloadValue(t, payload, "requestId", "stop-1")
}

func TestBuildQRScanImageFromDataURL(t *testing.T) {
	payload, err := buildQRScanImage("", "data:image/png;base64,AAAA", "qr-1", "job-1")
	if err != nil {
		t.Fatal(err)
	}
	assertPayloadValue(t, payload, "action", "qrScanImage")
	assertPayloadValue(t, payload, "requestId", "qr-1")
	assertPayloadValue(t, payload, "jobId", "job-1")
	assertPayloadValue(t, payload, "dataURL", "data:image/png;base64,AAAA")
}

func TestImageFileDataURL(t *testing.T) {
	path := t.TempDir() + "/qr.png"
	if err := os.WriteFile(path, []byte{0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'}, 0o600); err != nil {
		t.Fatal(err)
	}
	dataURL, err := imageFileDataURL(path)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(dataURL, "data:image/png;base64,") {
		t.Fatalf("unexpected data URL prefix: %q", dataURL)
	}
}

func TestReadJSONObjectFromString(t *testing.T) {
	payload, err := readJSONObject(`{"ok":true}`, "", false, strings.NewReader(""))
	if err != nil {
		t.Fatal(err)
	}
	if payload["ok"] != true {
		t.Fatalf("ok = %v", payload["ok"])
	}
}

func assertPayloadValue(t *testing.T, payload map[string]any, key string, want any) {
	t.Helper()
	if got := payload[key]; got != want {
		t.Fatalf("%s = %v, want %v", key, got, want)
	}
}
