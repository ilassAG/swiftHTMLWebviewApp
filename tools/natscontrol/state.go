package main

import (
	"encoding/json"
	"strings"
	"sync"
	"time"
)

type streamState struct {
	mu                sync.RWMutex
	startedAt         time.Time
	lastFrameAt       time.Time
	lastFrameSubject  string
	lastFrame         []byte
	lastFrameBytes    int
	totalFrames       int64
	totalFrameBytes   int64
	metaMessages      int64
	eventMessages     int64
	replyMessages     int64
	statusMessages    int64
	telemetryMessages int64
	lastMeta          string
	lastEvent         string
	lastReply         string
	lastStatus        string
	lastTelemetry     string
	subjects          subjectSet
}

func newStreamState(subjects subjectSet) *streamState {
	return &streamState{
		startedAt: time.Now(),
		subjects:  subjects,
	}
}

func (s *streamState) recordFrame(subject string, frame []byte) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.lastFrame = append(s.lastFrame[:0], frame...)
	s.lastFrameBytes = len(frame)
	s.totalFrames++
	s.totalFrameBytes += int64(len(frame))
	s.lastFrameAt = time.Now()
	s.lastFrameSubject = subject
}

func (s *streamState) recordText(kind string, payload []byte) {
	value := formatMaybeJSON(payload)
	s.mu.Lock()
	defer s.mu.Unlock()
	switch kind {
	case "meta":
		s.metaMessages++
		s.lastMeta = value
	case "event":
		s.eventMessages++
		s.lastEvent = value
	case "reply":
		s.replyMessages++
		s.lastReply = value
	case "status":
		s.statusMessages++
		s.lastStatus = value
	case "telemetry":
		s.telemetryMessages++
		s.lastTelemetry = value
	}
}

func (s *streamState) latestFrame() []byte {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return append([]byte(nil), s.lastFrame...)
}

func (s *streamState) snapshot() map[string]any {
	s.mu.RLock()
	defer s.mu.RUnlock()
	duration := time.Since(s.startedAt).Seconds()
	if duration <= 0 {
		duration = 0.001
	}
	lastFrameAgeMs := -1
	if !s.lastFrameAt.IsZero() {
		lastFrameAgeMs = int(time.Since(s.lastFrameAt).Milliseconds())
	}
	return map[string]any{
		"startedAt":         s.startedAt.Format(time.RFC3339),
		"frames":            s.totalFrames,
		"frameBytes":        s.totalFrameBytes,
		"bytesPerSecond":    float64(s.totalFrameBytes) / duration,
		"fpsAverage":        float64(s.totalFrames) / duration,
		"lastFrameBytes":    s.lastFrameBytes,
		"lastFrameAgeMs":    lastFrameAgeMs,
		"lastFrameSubject":  s.lastFrameSubject,
		"hasFrame":          len(s.lastFrame) > 0,
		"metaMessages":      s.metaMessages,
		"eventMessages":     s.eventMessages,
		"replyMessages":     s.replyMessages,
		"statusMessages":    s.statusMessages,
		"telemetryMessages": s.telemetryMessages,
		"lastMeta":          s.lastMeta,
		"lastEvent":         s.lastEvent,
		"lastReply":         s.lastReply,
		"lastStatus":        s.lastStatus,
		"lastTelemetry":     s.lastTelemetry,
		"subjects": map[string]any{
			"frames":    s.subjects.Frames,
			"meta":      s.subjects.Meta,
			"events":    s.subjects.Events,
			"responses": s.subjects.Responses,
			"status":    s.subjects.Status,
			"telemetry": s.subjects.Telemetry,
			"commands":  s.subjects.CommandRoot + ".*",
		},
	}
}

func formatMaybeJSON(payload []byte) string {
	raw := strings.TrimSpace(string(payload))
	if raw == "" {
		return ""
	}
	var value any
	if err := json.Unmarshal(payload, &value); err != nil {
		return raw
	}
	pretty, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return raw
	}
	return string(pretty)
}
