//
//  Models/WebViewStore.swift
//  swiftHTMLWebviewDemo
//
//  Created by KI-Generiert am 05.10.2023.
//  Korrektur: 02.04.2025 (Überflüssiges Nil Coalescing entfernt)
//

import Foundation
import WebKit
import Combine

@MainActor
class WebViewStore: NSObject, ObservableObject, WKNavigationDelegate { // NSObject und WKNavigationDelegate hinzugefügt
    var webView: WKWebView
    @Published var isLoading: Bool = false
    @Published var currentURLString: String? // @Published für UI-Updates, falls benötigt

    private var internalLoadAttempts = 0
    private let maxLoadAttempts = 5
    private var lastAttemptedURLString: String? // Um zu wissen, für welche URL wir Versuche zählen
// Neue Eigenschaften für URL-Switch-Handling
private var isSwitchingURL: Bool = false
private var hasReloadedFromOrigin: Bool = false

    override init() {
        self.webView = WKWebView() // Temporäre Initialisierung, wird in setupWebView überschrieben
        super.init()
        self.webView = createAndConfigureWebView() // Eigentliche Erstellung und Konfiguration
        
        // Initiales Laden der URL aus den AppSettings
        self.currentURLString = AppSettings.shared.serverURL
        attemptToLoad(urlToLoad: self.currentURLString)
    }

    private func createAndConfigureWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        configuration.userContentController = contentController
        configuration.allowsInlineMediaPlayback = true

        let newWebView = WKWebView(frame: .zero, configuration: configuration)
        newWebView.allowsBackForwardNavigationGestures = false
        newWebView.navigationDelegate = self
        return newWebView
    }

    private func attemptToLoad(urlToLoad: String?, isRetry: Bool = false) {
        guard let urlString = urlToLoad, let url = URL(string: urlString) else {
            print(String(format: NSLocalizedString("error.url.invalid", comment: "Invalid URL string error format"), String(describing: urlToLoad)))
            // Wenn die konfigurierte URL ungültig ist, sofort zur Default-URL wechseln
            switchToDefaultURLAndLoad(reason: NSLocalizedString("error.url.invalid", comment: "Invalid configured URL reason for switching to default"))
            return
        }

        // Wenn es kein Wiederholungsversuch für *dieselbe* URL ist, oder die URL sich geändert hat
        if lastAttemptedURLString != urlString {
            internalLoadAttempts = 0
            lastAttemptedURLString = urlString
            isSwitchingURL = true
            hasReloadedFromOrigin = false
        }
        
        if internalLoadAttempts >= maxLoadAttempts {
            print(String(format: NSLocalizedString("error.url.maxLoadAttemptsReached", comment: "Max load attempts reached error format"), maxLoadAttempts, urlString))
            switchToDefaultURLAndLoad(reason: NSLocalizedString("error.url.maxLoadAttemptsReached", comment: "Max load attempts reached reason for switching to default"))
            return
        }

        print(String(format: NSLocalizedString("status.url.loadingAttempt", comment: "Attempting to load URL status format"), url.absoluteString, internalLoadAttempts + 1))
        isLoading = true
        self.webView.stopLoading() // Vorheriges Laden stoppen
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        self.webView.load(request)
    }

    private func switchToDefaultURLAndLoad(reason: String) {
        print(String(format: NSLocalizedString("error.url.switchToDefault.reason", comment: "Switching to default URL reason format"), reason))
        AppSettings.shared.resetToDefaultURL()
        let defaultUrlString = AppSettings.shared.serverURL
        self.currentURLString = defaultUrlString // UI informieren
        self.lastAttemptedURLString = defaultUrlString // Für nächste Versuche
        self.internalLoadAttempts = 0 // Versuche für Default URL zurücksetzen
        
        if let defaultUrl = URL(string: defaultUrlString) {
            print("Loading default URL: \(defaultUrl)")
            let request = URLRequest(url: defaultUrl)
            self.webView.load(request)
        } else {
            print(String(format: NSLocalizedString("error.url.defaultInvalid", comment: "Critical error: Default URL invalid format"), defaultUrlString))
            isLoading = false
            // Hier könnte man eine lokale Fehlerseite laden oder einen Alert anzeigen
        }
    }
    

    func reloadCurrentOrNewURL() {
        let newUrlString = AppSettings.shared.serverURL

        func normalizeUrl(_ url: String?) -> String? {
            guard let url = url else { return nil }
            return url.hasSuffix("/") ? String(url.dropLast()) : url
        }

        let normalizedNew = normalizeUrl(newUrlString)
        let normalizedCurrentWebViewURL = normalizeUrl(webView.url?.absoluteString)
        let normalizedCurrentStoreURL = normalizeUrl(self.currentURLString)

        // Prüfen, ob die URL in den Settings sich von der aktuell im Store hinterlegten URL unterscheidet
        // ODER ob die aktuell in der WebView geladene URL nicht der in den Settings entspricht.
        // Dies deckt den Fall ab, dass die App startet und die WebView noch keine URL hat,
        // oder wenn ein Fehler aufgetreten ist und die WebView eine andere URL anzeigt.
        if normalizedNew != normalizedCurrentStoreURL || normalizedNew != normalizedCurrentWebViewURL {
            print("URL change detected or mismatch. New settings URL: \(String(describing: normalizedNew)), Current stored URL: \(String(describing: normalizedCurrentStoreURL)), Current WebView URL: \(String(describing: normalizedCurrentWebViewURL))")
            
            isLoading = true // Ladezustand sofort setzen
            // WebView-Instanz neu erstellen und konfigurieren
            self.webView = createAndConfigureWebView()
            
            self.currentURLString = newUrlString // UI und internen Zustand informieren
            self.lastAttemptedURLString = newUrlString
            self.internalLoadAttempts = 0
            
            // Kurze Verzögerung, um der UI Zeit zum Aktualisieren zu geben (insbesondere für die Ladeanimation)
            // und um sicherzustellen, dass die neue webView-Instanz im View-System angekommen ist.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.attemptToLoad(urlToLoad: newUrlString)
            }
        } else {
            print("URL is the same and seems to be loaded: \(String(describing: normalizedNew))")
            // Wenn die URL gleich ist und isLoading false ist, muss nichts getan werden.
            // Wenn isLoading true ist, läuft bereits ein Ladevorgang.
            if !isLoading {
                 // Optional: Hier könnte man prüfen, ob die Seite wirklich geladen ist,
                 // falls es Fälle gibt, wo isLoading fälschlicherweise false ist.
                 // Fürs Erste belassen wir es dabei, um unnötige Ladevorgänge zu vermeiden.
            }
        }
    }

    // MARK: - WKNavigationDelegate Methods

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        print("WebView didStartProvisionalNavigation for: \(String(describing: webView.url))")
        isLoading = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("WebView didFinish navigation for: \(String(describing: webView.url))")
        if isSwitchingURL {
            webView.evaluateJavaScript("document.body.innerHTML") { [weak self] result, error in
                guard let self = self else { return }
                let body = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if body.isEmpty {
                    if !self.hasReloadedFromOrigin {
                        print("Blank content detected, reloading from origin")
                        self.hasReloadedFromOrigin = true
                        self.webView.reloadFromOrigin()
                    } else {
                        print("Still blank after reloadFromOrigin, stopping loading animation.")
                        self.isSwitchingURL = false
                        self.isLoading = false
                    }
                } else {
                    self.isSwitchingURL = false
                    self.isLoading = false
                }
            }
            // Fallback: Falls nach 3 Sekunden immer noch URL-Wechsel besteht, erzwinge einen Reload.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self = self, self.isSwitchingURL else { return }
                print("Fallback: still switching URL after 3 seconds, forcing reload")
                self.webView.reload()
                self.isSwitchingURL = false
                self.isLoading = false
            }
        } else {
            self.isLoading = false
            if webView.url?.absoluteString == self.lastAttemptedURLString {
                self.internalLoadAttempts = 0
                self.currentURLString = webView.url?.absoluteString
            }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("WebView didFailProvisionalNavigation for: \(String(describing: webView.url)) with error: \(error.localizedDescription)")
        handleLoadError(error: error, failedURL: webView.url?.absoluteString ?? lastAttemptedURLString)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("WebView didFail navigation for: \(String(describing: webView.url)) with error: \(error.localizedDescription)")
        // Dieser Fehler tritt auf, nachdem der Inhalt bereits teilweise geladen wurde.
        handleLoadError(error: error, failedURL: webView.url?.absoluteString ?? lastAttemptedURLString)
    }

    private func handleLoadError(error: Error, failedURL: String?) {
        isLoading = false
        
        // Nur Wiederholungsversuche für die 'lastAttemptedURLString'
        guard let currentAttemptUrl = lastAttemptedURLString, failedURL == currentAttemptUrl else {
            print("Load error for a URL (\(String(describing: failedURL))) that is not the last one attempted (\(String(describing: lastAttemptedURLString))). Ignoring retry logic for this specific error.")
            // Wenn die URL in den Settings geändert wurde, während ein Ladeversuch lief,
            // könnte dieser Fall eintreten. `reloadCurrentOrNewURL` sollte das dann handhaben.
            return
        }

        internalLoadAttempts += 1
        print("Load attempt \(internalLoadAttempts) failed for \(currentAttemptUrl). Error: \(error.localizedDescription)")

        if internalLoadAttempts < maxLoadAttempts {
            // Warte eine Sekunde und versuche es erneut
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                print("Retrying to load \(currentAttemptUrl)...")
                self?.attemptToLoad(urlToLoad: currentAttemptUrl, isRetry: true)
            }
        } else {
            print(String(format: NSLocalizedString("error.url.maxLoadAttemptsReached", comment: "Max retries reached for URL format"), currentAttemptUrl)) // Note: Using the same key as above but context is slightly different
            switchToDefaultURLAndLoad(reason: NSLocalizedString("error.url.maxLoadAttemptsReached", comment: "Max load attempts after error reason")) // Same key, different comment for clarity
        }
    }

    // MARK: - JavaScript Communication (bestehende Methoden)
    func sendResultToWebView(result: [String: Any]) {
        sendDataToWebView(data: result)
    }

    func sendErrorToWebView(action: String?, error: Error) {
        let appError: AppError
        if let knownError = error as? AppError {
            appError = knownError
        } else {
            appError = .internalError(error.localizedDescription)
        }

        // Korrektur: ?? entfernt, da localizedDescription nicht optional ist.
        var errorDict: [String: Any] = ["error": appError.localizedDescription]
        if let action = action {
            errorDict["action"] = action
        }
        sendDataToWebView(data: errorDict)
    }

    func sendDataToWebView(data: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            print(String(format: NSLocalizedString("error.internalError.jsonResponseFailed", comment: "Failed to serialize to JSON string error"), String(describing: data)))

            // Korrektur: ?? entfernt, da localizedDescription nicht optional ist.
            let fallbackErrorMessage = AppError.internalError(NSLocalizedString("error.internalError.jsonResponseFailed", comment: "Failed to create JSON response fallback message")).localizedDescription
            let fallbackError: [String: Any] = ["error": fallbackErrorMessage]

            let fallbackJson = try? JSONSerialization.data(withJSONObject: fallbackError)
            let fallbackString = String(data: fallbackJson ?? Data(), encoding: .utf8) ?? "{ \"error\": \"\(NSLocalizedString("error.internalError.criticalFailure", comment: "Critical internal Swift error fallback"))\" }"
            evaluateJavaScript(script: "window.handleNativeResult(\(fallbackString));")
            return
        }

        let javascript = "window.handleNativeResult(\(jsonString));"
        evaluateJavaScript(script: javascript)
    }

    func evaluateJavaScript(script: String) {
         self.webView.evaluateJavaScript(script) { response, error in
             if let error = error {
                 print("Error evaluating JavaScript: \(error.localizedDescription)")
             } else {
                 print("Successfully evaluated JavaScript.")
             }
         }
    }
}
