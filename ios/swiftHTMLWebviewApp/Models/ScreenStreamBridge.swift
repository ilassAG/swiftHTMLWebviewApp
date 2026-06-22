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
    private var streamRequest = ScreenStreamPayload.StreamRequest(
        targetUrl: "",
        format: "jpeg",
        fps: 2,
        quality: 0.65,
        maxWidth: 720
    )
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

        streamRequest = ScreenStreamPayload.streamRequest(from: request)
        guard streamRequest.hasTargetUrl, let url = URL(string: streamRequest.targetUrl) else {
            return ScreenStreamPayload.response(
                request: request,
                action: "screenStreamStart",
                success: false,
                error: "targetUrl is required."
            )
        }

        guard streamRequest.isJpeg else {
            return ScreenStreamPayload.response(
                request: request,
                action: "screenStreamStart",
                success: false,
                error: "Only jpeg is implemented in this iOS build."
            )
        }

        fps = streamRequest.fps
        quality = streamRequest.quality
        maxWidth = CGFloat(streamRequest.maxWidth)
        framesSent = 0
        bytesSent = 0
        startedAt = Date()
        lastStatsAt = .distantPast
        running = true

        webSocket = URLSession.shared.webSocketTask(with: url)
        webSocket?.resume()
        sendTextMeta()
        scheduleTimer()

        return ScreenStreamPayload.startAck(request: request, streamRequest: streamRequest)
    }

    func stop(request: [String: Any]) -> [String: Any] {
        self.request = request
        stopInternal(closeSocket: true)
        return ScreenStreamPayload.stopAck(request: request, framesSent: framesSent, bytesSent: bytesSent)
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
        let meta = ScreenStreamPayload.meta(streamRequest: streamRequest)
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
        eventHandler?(ScreenStreamPayload.stats(
            framesSent: framesSent,
            bytesSent: bytesSent,
            lastFrameBytes: lastFrameBytes,
            startedAt: startedAt,
            now: now
        ))
    }

    private func emit(action: String, success: Bool, message: String?) {
        eventHandler?(ScreenStreamPayload.event(action: action, success: success, message: message))
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

}
