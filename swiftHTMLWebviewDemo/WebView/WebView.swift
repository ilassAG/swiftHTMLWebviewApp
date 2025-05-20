//
//  WebView/WebView.swift
//  swiftHTMLWebviewDemo
//
//  Created by KI-Generiert am 05.10.2023.
//  Korrektur: 02.04.2025 (Nil Coalescing entfernt)
//

import SwiftUI
@preconcurrency import WebKit

struct WebView: UIViewRepresentable {
    @ObservedObject var webViewStore: WebViewStore
    var onScriptMessage: ([String: Any]) -> Void

    let htmlFileName: String = Configuration.localHTMLFileName

    func makeUIView(context: Context) -> WKWebView {
        let webView = webViewStore.webView

        webView.configuration.userContentController.removeScriptMessageHandler(forName: Configuration.messageHandlerName)
        webView.configuration.userContentController.add(context.coordinator, name: Configuration.messageHandlerName)

        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        // Versuche, die Remote-HTML-Seite zu laden
        if let remoteURL = URL(string: Configuration.serverHTMLPath) {
            let request = URLRequest(url: remoteURL)
            webView.load(request)
            print(String(format: NSLocalizedString("status.webView.loadingRemoteHTML", comment: "Loading remote HTML status format"), remoteURL.absoluteString))
        } else {
            loadLocalHTML(in: webView)
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Sicherstellen, dass die Delegaten und der Script Handler auf die aktuelle Instanz zeigen,
        // falls die uiView nicht die Instanz aus dem webViewStore ist (z.B. nach Neuerstellung im Store).
        // Normalerweise sollte makeUIView dies handhaben, aber als Absicherung:
        if uiView !== webViewStore.webView {
            // Dieser Fall sollte idealerweise nicht oft eintreten, wenn SwiftUI die View korrekt neu erstellt.
            // Wenn er eintritt, bedeutet das, dass die uiView (alt) und webViewStore.webView (neu) divergieren.
            // Wir wollen, dass die uiView die neue webViewStore.webView widerspiegelt.
            // Das direkte Ersetzen der uiView hier ist nicht der Standardweg.
            // Stattdessen stellen wir sicher, dass die Konfiguration der webViewStore.webView aktuell ist.
            // Die makeUIView sollte die korrekte, neue Instanz zurückgeben.
            // Diese updateUIView dient eher dazu, die Konfiguration der *aktuell angezeigten* uiView
            // mit dem Coordinator zu synchronisieren, falls SwiftUI die uiView Instanz wiederverwendet.

            // Entferne alte Handler und Delegaten von der uiView, falls sie noch gesetzt sind
            // und nicht dem aktuellen Coordinator entsprechen.
            uiView.configuration.userContentController.removeScriptMessageHandler(forName: Configuration.messageHandlerName)
            
            // Füge Handler und Delegaten zur webViewStore.webView hinzu (die die neue Instanz sein sollte)
            // Dies wird eigentlich in makeUIView gemacht. Wenn updateUIView mit einer alten uiView aufgerufen wird,
            // während webViewStore.webView neu ist, ist das ein Zeichen, dass makeUIView bald folgen sollte.
        }

        // Stelle sicher, dass der Coordinator korrekt für die aktuelle webView im Store gesetzt ist.
        // Dies ist wichtig, falls die webView-Instanz im Store ausgetauscht wurde.
        // makeUIView wird dies für die *initiale* Erstellung tun.
        // updateUIView kann helfen, dies für nachfolgende Updates zu synchronisieren,
        // obwohl der Austausch der Instanz selbst eher ein Fall für eine Neukonstruktion der View ist.

        // Die Kernlogik ist: makeUIView liefert die konfigurierte webViewStore.webView.
        // Wenn webViewStore.webView ersetzt wird, sollte makeUIView neu aufgerufen werden.
        // Wir fügen hier eine minimale Synchronisation der Delegaten hinzu, falls SwiftUI die uiView wiederverwendet.
        if uiView.navigationDelegate !== context.coordinator {
            uiView.navigationDelegate = context.coordinator
        }
        if uiView.uiDelegate !== context.coordinator {
            uiView.uiDelegate = context.coordinator
        }
        // Prüfe, ob der ScriptMessageHandler korrekt gesetzt ist.
        // Dies ist etwas komplexer, da wir den Handler nicht direkt vergleichen können.
        // Wir verlassen uns darauf, dass makeUIView dies korrekt setzt.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func loadLocalHTML(in webView: WKWebView) {
        if let url = Bundle.main.url(forResource: htmlFileName, withExtension: "html", subdirectory: "HTML") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            print(String(format: NSLocalizedString("status.webView.loadingLocalHTML", comment: "Loading local HTML fallback status format"), url.absoluteString))
        } else {
            print(String(format: NSLocalizedString("error.webView.localHTMLNotFound", comment: "Local HTML file not found error format"), htmlFileName))
            // Der HTML-String selbst wird hier nicht lokalisiert, da er eine Fallback-Fehlerseite ist.
            // Eine vollständig lokalisierte Fehlerseite wäre aufwändiger.
            let errorHTML = """
            <html><head><title>Error</title></head><body style='font-family: sans-serif; padding: 20px;'>
            <h1>Error</h1>
            <p>The required HTML file could not be loaded.</p>
            <p>Please ensure that '\(htmlFileName).html', 'style.css', and 'script.js' are in the 'HTML' folder and added to the bundle.</p>
            </body></html>
            """
            webView.loadHTMLString(errorHTML, baseURL: nil)
        }
    }

    @MainActor
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
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
                // Korrektur: ?? entfernt, da localizedDescription nicht optional ist
                let errorPayload: [String: Any] = [
                    "error": AppError.invalidRequest(NSLocalizedString("error.webView.jsParseError.generic", comment: "Generic JS message parse error")).localizedDescription
                ]
                parent.webViewStore.sendDataToWebView(data: errorPayload)
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            print("WebView started loading.")
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("WebView finished loading.")
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("WebView failed loading: \(error.localizedDescription)")
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("Remote page failed loading: \(error.localizedDescription)")
            if let localURL = Bundle.main.url(forResource: parent.htmlFileName, withExtension: "html", subdirectory: "HTML") {
                webView.loadFileURL(localURL, allowingReadAccessTo: localURL.deletingLastPathComponent())
                print(String(format: NSLocalizedString("status.webView.loadingLocalHTML", comment: "Loading local HTML fallback status format"), localURL.absoluteString))
            } else {
                print(String(format: NSLocalizedString("error.webView.localHTMLNotFound", comment: "Local HTML file not found error format"), parent.htmlFileName))
                // Der HTML-String selbst wird hier nicht lokalisiert, da er eine Fallback-Fehlerseite ist.
                let errorHTML = """
                <html><head><title>Error</title></head><body style='font-family: sans-serif; padding: 20px;'>
                <h1>Error</h1>
                <p>The required HTML file could not be loaded.</p>
                <p>Please ensure that '\(parent.htmlFileName).html', 'style.css', and 'script.js' are in the 'HTML' folder and added to the bundle.</p>
                </body></html>
                """
                webView.loadHTMLString(errorHTML, baseURL: nil)
            }
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            print("JavaScript Alert: \(message)")
            completionHandler()
        }
    }
}
