//
//  ScreenStreamPayload.swift
//  swiftHTMLWebviewApp
//
//  Pure request and payload helpers for app-screen streaming.
//

import Foundation

enum ScreenStreamPayload {
    struct StreamRequest {
        let transport: String
        let targetUrl: String
        let subject: String
        let metaSubject: String
        let eventSubject: String
        let format: String
        let fps: Int
        let quality: Double
        let maxWidth: Int

        var hasTargetUrl: Bool {
            !targetUrl.isEmpty
        }

        var isJpeg: Bool {
            format == "jpeg"
        }

        var isNats: Bool {
            transport == "nats"
        }

        var isWebSocket: Bool {
            transport == "websocket"
        }
    }

    static func streamRequest(from request: [String: Any]) -> StreamRequest {
        var format = nonEmpty(stringValue(request["format"]), fallback: "jpeg").lowercased()
        if format == "jpg" {
            format = "jpeg"
        }

        let qualityInput = finiteDoubleValue(request["quality"]) ?? 65.0
        let normalizedQuality = qualityInput > 1 ? qualityInput / 100.0 : qualityInput
        let explicitTransport = stringValue(request["transport"]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let subject = stringValue(request["subject"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let transport = explicitTransport.isEmpty
            ? (subject.isEmpty ? "websocket" : "nats")
            : explicitTransport

        return StreamRequest(
            transport: transport == "nats" ? "nats" : "websocket",
            targetUrl: nonEmpty(stringValue(request["targetUrl"]), fallback: stringValue(request["url"])),
            subject: subject,
            metaSubject: stringValue(request["metaSubject"]).trimmingCharacters(in: .whitespacesAndNewlines),
            eventSubject: stringValue(request["eventSubject"]).trimmingCharacters(in: .whitespacesAndNewlines),
            format: format,
            fps: clamp(intValue(request["fps"]) ?? 2, min: 1, max: 10),
            quality: clamp(normalizedQuality, min: 0.25, max: 0.95),
            maxWidth: clamp(intValue(request["maxWidth"]) ?? 720, min: 240, max: 1920)
        )
    }

    static func startAck(request: [String: Any], streamRequest: StreamRequest) -> [String: Any] {
        var response = response(request: request, action: "screenStreamStart", success: true)
        response["transport"] = streamRequest.transport
        if streamRequest.isWebSocket {
            response["targetUrl"] = streamRequest.targetUrl
        } else {
            response["subject"] = streamRequest.subject
            response["metaSubject"] = streamRequest.metaSubject
            response["eventSubject"] = streamRequest.eventSubject
        }
        response["format"] = "jpeg"
        response["fps"] = streamRequest.fps
        response["quality"] = streamRequest.quality
        response["maxWidth"] = streamRequest.maxWidth
        return response
    }

    static func stopAck(request: [String: Any], framesSent: Int64, bytesSent: Int64) -> [String: Any] {
        var response = response(request: request, action: "screenStreamStop", success: true)
        response["frames"] = framesSent
        response["bytes"] = bytesSent
        return response
    }

    static func response(
        request: [String: Any],
        action: String,
        success: Bool,
        error: String? = nil
    ) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: action)
        response["success"] = success
        if let error, !error.isEmpty {
            response["error"] = error
        }
        return response
    }

    static func meta(streamRequest: StreamRequest) -> [String: Any] {
        [
            "type": "screenStreamMeta",
            "platform": "ios",
            "transport": streamRequest.transport,
            "format": "jpeg",
            "fps": streamRequest.fps,
            "quality": streamRequest.quality,
            "maxWidth": streamRequest.maxWidth,
            "subject": streamRequest.subject
        ]
    }

    static func event(action: String, success: Bool, message: String? = nil) -> [String: Any] {
        var event: [String: Any] = [
            "platform": "ios",
            "action": action,
            "success": success
        ]
        if let message, !message.isEmpty {
            event[success ? "message" : "error"] = message
        }
        return event
    }

    static func stats(
        framesSent: Int64,
        bytesSent: Int64,
        lastFrameBytes: Int,
        startedAt: Date,
        now: Date
    ) -> [String: Any] {
        var event = event(action: "screenStreamStats", success: true)
        event["frames"] = framesSent
        event["bytes"] = bytesSent
        event["lastFrameBytes"] = lastFrameBytes
        event["durationSeconds"] = max(0.001, now.timeIntervalSince(startedAt))
        return event
    }

    private static func nonEmpty(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private static func clamp(_ value: Int, min: Int, max: Int) -> Int {
        Swift.max(min, Swift.min(max, value))
    }

    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }

    private static func finiteDoubleValue(_ value: Any?) -> Double? {
        guard let value = doubleValue(value), value.isFinite else {
            return nil
        }
        return value
    }
}
