//
//  ScreenStreamBridge.swift
//  swiftHTMLWebviewApp
//
//  App-screen JPEG stream over WebSocket for native diagnostics.
//

import Foundation
import UIKit
import WebKit

@MainActor
final class ScreenStreamBridge: ObservableObject {
    private var webSocket: URLSessionWebSocketTask?
    private var timer: Timer?
    private weak var webView: WKWebView?
    private var running = false
    private var captureInFlight = false
    private var request: [String: Any] = [:]
    private var targetUrl = ""
    private var fps = 2
    private var quality = 0.65
    private var maxWidth: CGFloat = 720
    private var framesSent: Int64 = 0
    private var bytesSent: Int64 = 0
    private var startedAt = Date()
    private var lastStatsAt = Date.distantPast
    private var eventHandler: (([String: Any]) -> Void)?

    func start(request: [String: Any], webView: WKWebView, eventHandler: @escaping ([String: Any]) -> Void) -> [String: Any] {
        stopInternal(closeSocket: true)
        self.request = request
        self.webView = webView
        self.eventHandler = eventHandler

        targetUrl = stringValue(request["targetUrl"]).isEmpty ? stringValue(request["url"]) : stringValue(request["targetUrl"])
        guard let url = URL(string: targetUrl), !targetUrl.isEmpty else {
            return errorResponse(action: "screenStreamStart", error: "targetUrl is required.")
        }

        let format = stringValue(request["format"]).isEmpty ? "jpeg" : stringValue(request["format"]).lowercased()
        guard format == "jpeg" || format == "jpg" else {
            return errorResponse(action: "screenStreamStart", error: "Only jpeg is implemented in this iOS build.")
        }

        fps = max(1, min(10, intValue(request["fps"]) ?? 2))
        let qualityInput = doubleValue(request["quality"]) ?? 65.0
        quality = max(0.25, min(0.95, qualityInput > 1 ? qualityInput / 100.0 : qualityInput))
        maxWidth = CGFloat(max(240, min(1920, intValue(request["maxWidth"]) ?? 720)))
        framesSent = 0
        bytesSent = 0
        startedAt = Date()
        lastStatsAt = .distantPast
        running = true

        webSocket = URLSession.shared.webSocketTask(with: url)
        webSocket?.resume()
        sendTextMeta()
        scheduleTimer()

        var response = baseResponse(action: "screenStreamStart")
        response["success"] = true
        response["targetUrl"] = targetUrl
        response["transport"] = "websocket"
        response["format"] = "jpeg"
        response["fps"] = fps
        response["quality"] = quality
        response["maxWidth"] = Int(maxWidth)
        return response
    }

    func stop(request: [String: Any]) -> [String: Any] {
        self.request = request
        stopInternal(closeSocket: true)
        var response = baseResponse(action: "screenStreamStop")
        response["success"] = true
        response["frames"] = framesSent
        response["bytes"] = bytesSent
        return response
    }

    func shutdown() {
        stopInternal(closeSocket: true)
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = 1.0 / Double(max(fps, 1))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.captureAndSend()
            }
        }
    }

    private func captureAndSend() {
        guard running, !captureInFlight, let webView else { return }
        captureInFlight = true
        let config = WKSnapshotConfiguration()
        config.rect = webView.bounds
        webView.takeSnapshot(with: config) { [weak self] image, error in
            Task { @MainActor in
                guard let self else { return }
                self.captureInFlight = false
                if let error {
                    self.emit(action: "screenStreamError", success: false, message: error.localizedDescription)
                    return
                }
                guard let image else { return }
                let output = self.scale(image: image, maxWidth: self.maxWidth)
                guard let data = output.jpegData(compressionQuality: self.quality) else {
                    self.emit(action: "screenStreamError", success: false, message: "JPEG encoding failed.")
                    return
                }
                self.webSocket?.send(.data(data)) { error in
                    Task { @MainActor in
                        if let error {
                            self.emit(action: "screenStreamError", success: false, message: error.localizedDescription)
                            return
                        }
                        self.framesSent += 1
                        self.bytesSent += Int64(data.count)
                        self.emitStatsIfNeeded(lastFrameBytes: data.count)
                    }
                }
            }
        }
    }

    private func sendTextMeta() {
        let meta: [String: Any] = [
            "type": "screenStreamMeta",
            "platform": "ios",
            "format": "jpeg",
            "fps": fps,
            "quality": quality,
            "maxWidth": Int(maxWidth)
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: meta),
              let string = String(data: data, encoding: .utf8) else {
            return
        }
        webSocket?.send(.string(string)) { [weak self] error in
            if let error {
                Task { @MainActor in
                    self?.emit(action: "screenStreamError", success: false, message: error.localizedDescription)
                }
            }
        }
    }

    private func emitStatsIfNeeded(lastFrameBytes: Int) {
        let now = Date()
        guard now.timeIntervalSince(lastStatsAt) >= 2 else { return }
        lastStatsAt = now
        var event = baseEvent(action: "screenStreamStats", success: true)
        event["frames"] = framesSent
        event["bytes"] = bytesSent
        event["lastFrameBytes"] = lastFrameBytes
        event["durationSeconds"] = max(0.001, now.timeIntervalSince(startedAt))
        eventHandler?(event)
    }

    private func emit(action: String, success: Bool, message: String?) {
        var event = baseEvent(action: action, success: success)
        if let message, !message.isEmpty {
            event[success ? "message" : "error"] = message
        }
        eventHandler?(event)
    }

    private func stopInternal(closeSocket: Bool) {
        running = false
        timer?.invalidate()
        timer = nil
        captureInFlight = false
        if closeSocket {
            webSocket?.cancel(with: .normalClosure, reason: nil)
        }
        webSocket = nil
    }

    private func scale(image: UIImage, maxWidth: CGFloat) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        guard pixelWidth > maxWidth else { return image }

        let scale = maxWidth / pixelWidth
        let pixelHeight = image.size.height * image.scale
        let target = CGSize(width: maxWidth, height: pixelHeight * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    private func baseResponse(action: String) -> [String: Any] {
        var response: [String: Any] = [
            "platform": "ios",
            "action": action
        ]
        if let requestId = request["requestId"] {
            response["requestId"] = requestId
        }
        return response
    }

    private func baseEvent(action: String, success: Bool) -> [String: Any] {
        [
            "platform": "ios",
            "action": action,
            "success": success
        ]
    }

    private func errorResponse(action: String, error: String) -> [String: Any] {
        var response = baseResponse(action: action)
        response["success"] = false
        response["error"] = error
        return response
    }
}
