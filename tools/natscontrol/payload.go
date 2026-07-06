package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

type streamStartOptions struct {
	RequestID    string
	FrameSubject string
	MetaSubject  string
	EventSubject string
	FPS          int
	Quality      int
	MaxWidth     int
	Format       string
	Source       string
}

func buildScreenStreamStart(subjects subjectSet, opts streamStartOptions) map[string]any {
	frameSubject := strings.TrimSpace(opts.FrameSubject)
	if frameSubject == "" {
		frameSubject = subjects.Frames
	}
	metaSubject := strings.TrimSpace(opts.MetaSubject)
	if metaSubject == "" {
		metaSubject = subjects.Meta
	}
	eventSubject := strings.TrimSpace(opts.EventSubject)
	if eventSubject == "" {
		eventSubject = subjects.Events
	}
	requestIDValue := strings.TrimSpace(opts.RequestID)
	if requestIDValue == "" {
		requestIDValue = requestID("screenStreamStart")
	}
	format := strings.TrimSpace(strings.ToLower(opts.Format))
	if format == "" {
		format = "jpeg"
	}
	if format == "jpg" {
		format = "jpeg"
	}
	source := strings.TrimSpace(strings.ToLower(opts.Source))
	if source == "" {
		source = "app"
	}
	fps := clampInt(opts.FPS, 1, 10)
	quality := clampInt(opts.Quality, 25, 95)
	maxWidth := clampInt(opts.MaxWidth, 240, 1920)
	return map[string]any{
		"action":       "screenStreamStart",
		"requestId":    requestIDValue,
		"source":       source,
		"transport":    "nats",
		"subject":      frameSubject,
		"metaSubject":  metaSubject,
		"eventSubject": eventSubject,
		"format":       format,
		"fps":          fps,
		"quality":      quality,
		"maxWidth":     maxWidth,
	}
}

func buildScreenStreamStop(requestIDValue string) map[string]any {
	if strings.TrimSpace(requestIDValue) == "" {
		requestIDValue = requestID("screenStreamStop")
	}
	return map[string]any{
		"action":    "screenStreamStop",
		"requestId": requestIDValue,
	}
}

func buildQRScanImage(imagePath, dataURL, requestIDValue, jobID string) (map[string]any, error) {
	if strings.TrimSpace(requestIDValue) == "" {
		requestIDValue = requestID("qrScanImage")
	}
	payload := map[string]any{
		"action":    "qrScanImage",
		"requestId": requestIDValue,
	}
	if strings.TrimSpace(jobID) != "" {
		payload["jobId"] = strings.TrimSpace(jobID)
	}
	if strings.TrimSpace(dataURL) != "" {
		payload["dataURL"] = strings.TrimSpace(dataURL)
		return payload, nil
	}
	if strings.TrimSpace(imagePath) == "" {
		return nil, fmt.Errorf("either -image or -data-url is required")
	}
	value, err := imageFileDataURL(imagePath)
	if err != nil {
		return nil, err
	}
	payload["dataURL"] = value
	return payload, nil
}

func imageFileDataURL(path string) (string, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	mimeType := mime.TypeByExtension(strings.ToLower(filepath.Ext(path)))
	if mimeType == "" {
		sample := raw
		if len(sample) > 512 {
			sample = sample[:512]
		}
		mimeType = http.DetectContentType(sample)
	}
	if mimeType == "" || mimeType == "application/octet-stream" {
		mimeType = "image/png"
	}
	return "data:" + mimeType + ";base64," + base64.StdEncoding.EncodeToString(raw), nil
}

func readJSONObject(jsonText string, jsonPath string, readStdin bool, stdin io.Reader) (map[string]any, error) {
	var raw []byte
	switch {
	case strings.TrimSpace(jsonText) != "":
		raw = []byte(jsonText)
	case strings.TrimSpace(jsonPath) != "":
		data, err := os.ReadFile(jsonPath)
		if err != nil {
			return nil, err
		}
		raw = data
	case readStdin:
		data, err := io.ReadAll(stdin)
		if err != nil {
			return nil, err
		}
		raw = data
	default:
		return nil, fmt.Errorf("one of -json, -json-file, or -stdin is required")
	}
	var object map[string]any
	if err := json.Unmarshal(raw, &object); err != nil {
		return nil, err
	}
	return object, nil
}

func marshalJSONObject(value map[string]any) ([]byte, error) {
	return json.Marshal(value)
}

func clampInt(value, minValue, maxValue int) int {
	if value < minValue {
		return minValue
	}
	if value > maxValue {
		return maxValue
	}
	return value
}
