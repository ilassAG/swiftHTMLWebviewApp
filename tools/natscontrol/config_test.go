package main

import "testing"

func TestSubjectSetFromAppUUID(t *testing.T) {
	cfg := commonConfig{AppUUID: "APP-123", Namespace: defaultNamespace}
	subjects, err := cfg.subjects()
	if err != nil {
		t.Fatal(err)
	}
	if subjects.Prefix != "swift.wrapper.APP-123" {
		t.Fatalf("prefix = %q", subjects.Prefix)
	}
	if subjects.Frames != "swift.wrapper.APP-123.screen.frames" {
		t.Fatalf("frames = %q", subjects.Frames)
	}
	if subjects.Responses != "swift.wrapper.APP-123.events.responses" {
		t.Fatalf("responses = %q", subjects.Responses)
	}
	if subjects.Telemetry != "swift.wrapper.APP-123.telemetry.status" {
		t.Fatalf("telemetry = %q", subjects.Telemetry)
	}
	if got := commandSubject(subjects, ".screenStreamStart."); got != "swift.wrapper.APP-123.commands.screenStreamStart" {
		t.Fatalf("command subject = %q", got)
	}
}

func TestSubjectSetFromPrefixTrimsDots(t *testing.T) {
	cfg := commonConfig{Prefix: ".custom.prefix."}
	subjects, err := cfg.subjects()
	if err != nil {
		t.Fatal(err)
	}
	if subjects.Prefix != "custom.prefix" {
		t.Fatalf("prefix = %q", subjects.Prefix)
	}
}

func TestSubjectSetRequiresAppOrPrefix(t *testing.T) {
	_, err := (commonConfig{}).subjects()
	if err == nil {
		t.Fatal("expected error")
	}
}

func TestLocalHTTPURL(t *testing.T) {
	tests := map[string]string{
		":18091":        "http://127.0.0.1:18091/",
		"0.0.0.0:18091": "http://127.0.0.1:18091/",
		"[::]:18091":    "http://127.0.0.1:18091/",
		"127.0.0.1:90":  "http://127.0.0.1:90/",
	}
	for input, want := range tests {
		if got := localHTTPURL(input); got != want {
			t.Fatalf("localHTTPURL(%q) = %q, want %q", input, got, want)
		}
	}
}
