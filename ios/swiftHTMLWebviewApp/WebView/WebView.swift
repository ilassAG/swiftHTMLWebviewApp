//
//  WebView/WebView.swift
//  swiftHTMLWebviewApp
//
//  This file defines the `WebView` struct, a SwiftUI `UIViewRepresentable` that wraps a `WKWebView`.
//  It's responsible for displaying web content, either from a remote server or local HTML files.
//  WebViewStore owns navigation/loading state; the Coordinator owns JavaScript
//  message handling and UI delegate callbacks.
//

import SwiftUI
@preconcurrency import WebKit

struct WebView: UIViewRepresentable {
    @ObservedObject var webViewStore: WebViewStore
    var onScriptMessage: ([String: Any]) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let webView = webViewStore.webView

        webView.configuration.userContentController.removeScriptMessageHandler(forName: Configuration.messageHandlerName)
        webView.configuration.userContentController.add(context.coordinator, name: Configuration.messageHandlerName)

        webView.navigationDelegate = webViewStore
        webView.uiDelegate = context.coordinator
        DispatchQueue.main.async {
            webViewStore.loadConfiguredURLIfNeeded()
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView !== webViewStore.webView {
            uiView.configuration.userContentController.removeScriptMessageHandler(forName: Configuration.messageHandlerName)
        }

        if uiView.navigationDelegate !== webViewStore {
            uiView.navigationDelegate = webViewStore
        }
        if uiView.uiDelegate !== context.coordinator {
            uiView.uiDelegate = context.coordinator
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    class Coordinator: NSObject, WKUIDelegate, WKScriptMessageHandler {
        var parent: WebView

        init(_ parent: WebView) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Configuration.messageHandlerName else { return }

            if let body = message.body as? [String: Any] {
                print("Received message from JS: \(body)")
                parent.onScriptMessage(body)
            } else {
                print(String(format: NSLocalizedString("error.webView.jsParseError", comment: "JS message parse error format"), String(describing: message.body)))

                let errorPayload: [String: Any] = [
                    "error": AppError.invalidRequest(NSLocalizedString("error.webView.jsParseError.generic", comment: "Generic JS message parse error")).localizedDescription
                ]
                parent.webViewStore.sendDataToWebView(data: errorPayload)
            }
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            print("JavaScript Alert: \(message)")
            completionHandler()
        }
    }
}
