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
        timeoutSeconds = max(1, doubleValue(request["timeoutSeconds"]) ?? 30)
        intervalSeconds = max(0.25, doubleValue(request["intervalSeconds"]) ?? 1)
        resetActivity()
        injectActivityShim(into: webView)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        var response = baseResponse(request: request, action: "idleTimerStart")
        response["success"] = true
        response["timeoutSeconds"] = timeoutSeconds
        response["intervalSeconds"] = intervalSeconds
        return response
    }

    func stop(request: [String: Any]) -> [String: Any] {
        timer?.invalidate()
        timer = nil
        var response = baseResponse(request: request, action: "idleTimerStop")
        response["success"] = true
        return response
    }

    func reset(request: [String: Any]) -> [String: Any] {
        resetActivity()
        var response = baseResponse(request: request, action: "idleTimerReset")
        response["success"] = true
        return response
    }

    func recordActivity() {
        resetActivity()
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
        eventHandler?([
            "platform": "ios",
            "action": action,
            "success": true,
            "idleSeconds": idleSeconds,
            "timeoutSeconds": timeoutSeconds
        ])
    }

    private func baseResponse(request: [String: Any], action: String) -> [String: Any] {
        var response: [String: Any] = [
            "platform": "ios",
            "action": action
        ]
        if let requestId = request["requestId"] {
            response["requestId"] = requestId
        }
        return response
    }
}
