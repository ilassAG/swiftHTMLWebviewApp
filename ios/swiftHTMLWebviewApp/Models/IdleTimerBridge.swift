//
//  IdleTimerBridge.swift
//  swiftHTMLWebviewApp
//
//  Native idle counter controlled by JavaScript.
//

import Foundation
import WebKit

@MainActor
final class IdleTimerBridge: ObservableObject {
    private var timer: Timer?
    private var timeoutSeconds: TimeInterval = 30
    private var intervalSeconds: TimeInterval = 1
    private var lastActivity = Date()
    private var didTimeout = false
    private var eventHandler: (([String: Any]) -> Void)?

    func start(request: [String: Any], webView: WKWebView, eventHandler: @escaping ([String: Any]) -> Void) -> [String: Any] {
        self.eventHandler = eventHandler
        let config = IdleTimerPayload.startRequest(from: request)
        timeoutSeconds = config.timeoutSeconds
        intervalSeconds = config.intervalSeconds
        resetActivity()
        injectActivityShim(into: webView)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        return IdleTimerPayload.startResponse(request: request, config: config)
    }

    func stop(request: [String: Any]) -> [String: Any] {
        timer?.invalidate()
        timer = nil
        return IdleTimerPayload.stopResponse(request: request)
    }

    func reset(request: [String: Any]) -> [String: Any] {
        resetActivity()
        return IdleTimerPayload.resetResponse(request: request)
    }

    func recordActivity() {
        resetActivity()
    }

    func telemetrySnapshot(now: Date = Date()) -> [String: Any] {
        [
            "running": timer != nil,
            "idleSeconds": max(0, now.timeIntervalSince(lastActivity)),
            "timeoutSeconds": timeoutSeconds,
            "timedOut": didTimeout
        ]
    }

    func shutdown() {
        timer?.invalidate()
        timer = nil
    }

    private func resetActivity() {
        lastActivity = Date()
        didTimeout = false
    }

    private func tick() {
        let idleSeconds = Date().timeIntervalSince(lastActivity)
        emit(action: "idleTick", idleSeconds: idleSeconds)
        if !didTimeout && idleSeconds >= timeoutSeconds {
            didTimeout = true
            emit(action: "idleTimeout", idleSeconds: idleSeconds)
        }
    }

    private func injectActivityShim(into webView: WKWebView) {
        let script = """
        (function(){
          if(window.__swiftHTMLIdleShimInstalled){ return; }
          window.__swiftHTMLIdleShimInstalled = true;
          function notify(){
            try {
              window.webkit.messageHandlers.swiftBridge.postMessage({ action: 'idleActivity', source: 'web' });
            } catch(e) {}
          }
          ['pointerdown','touchstart','mousedown','keydown','scroll'].forEach(function(name){
            document.addEventListener(name, notify, { capture: true, passive: true });
          });
        })();
        """
        webView.evaluateJavaScript(script)
    }

    private func emit(action: String, idleSeconds: TimeInterval) {
        eventHandler?(IdleTimerPayload.event(
            action: action,
            idleSeconds: idleSeconds,
            timeoutSeconds: timeoutSeconds
        ))
    }
}
