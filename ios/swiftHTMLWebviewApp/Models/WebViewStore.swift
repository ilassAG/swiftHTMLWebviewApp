//
//  Models/WebViewStore.swift
//  swiftHTMLWebviewApp
//
//  This class acts as an ObservableObject to manage the state of the WKWebView.
//  It handles the creation, configuration, and loading of URLs for the WebView.
//  It also implements WKNavigationDelegate to manage navigation events (start, finish, fail)
//  and includes logic for retrying failed loads and switching to a default URL if necessary.
//  Communication from Swift to JavaScript (sending results/errors) is also managed here.
//

import Foundation
import WebKit
import Combine

@MainActor
class WebViewStore: NSObject, ObservableObject, WKNavigationDelegate {
    var webView: WKWebView
    @Published var isLoading: Bool = false
    @Published var currentURLString: String?

    private var internalLoadAttempts = 0
    private let maxLoadAttempts = 5
    private var lastAttemptedURLString: String?
    private var isSwitchingURL: Bool = false
    private var hasReloadedFromOrigin: Bool = false
    private var startupLoadCoordinator = StartupLoadCoordinator()
    private var currentCandidateSignature = ""
    private var failoverTimeoutWorkItem: DispatchWorkItem?
    private var hasStartedInitialLoad = false
    private var availabilityProbeTask: Task<Void, Never>?
    private var loadGeneration = UUID()
    private let recoveryDisplayName = "Server nicht erreichbar"

    override init() {
        self.webView = WKWebView()
        super.init()
        self.webView = createAndConfigureWebView()
    }

    var isShowingRecoveryPage: Bool {
        startupLoadCoordinator.isShowingRecovery
    }

    func loadConfiguredURLIfNeeded() {
        guard !hasStartedInitialLoad else {
            return
        }

        hasStartedInitialLoad = true
        beginLoading(candidates: AppSettings.shared.serverURLCandidates())
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

    private func beginLoading(candidates: [String]) {
        cancelFailoverTimeout()
        availabilityProbeTask?.cancel()
        _ = startupLoadCoordinator.start(
            candidates: candidates,
            highAvailabilityEnabled: AppSettings.shared.highAvailabilityEnabled
        )
        currentCandidateSignature = startupLoadCoordinator.currentSignature
        internalLoadAttempts = 0
        lastAttemptedURLString = nil
        isLoading = true
        currentURLString = startupLoadCoordinator.firstDisplayName

        let generation = UUID()
        loadGeneration = generation
        availabilityProbeTask = Task { [weak self] in
            await self?.loadFirstReachableCandidate(generation: generation)
        }
    }

    private func loadCandidate(at index: Int) {
        applyStartupLoadCommand(startupLoadCoordinator.selectCandidate(
            at: index,
            fallbackServerURL: AppSettings.shared.serverURL
        ))
    }

    private func loadCandidate(urlString candidate: String, scheduleTimeout: Bool) {
        currentURLString = startupLoadCoordinator.displayName(for: candidate)
        internalLoadAttempts = 0
        isSwitchingURL = true
        hasReloadedFromOrigin = false

        if Configuration.isLocalHTMLPath(candidate) {
            loadLocalHTML()
            return
        }

        guard let url = URL(string: candidate), url.scheme != nil else {
            print(String(format: NSLocalizedString("error.url.invalid", comment: "Invalid URL string error format"), candidate))
            loadNextCandidateOrDefault(reason: NSLocalizedString("error.url.invalid", comment: "Invalid configured URL reason for switching to default"))
            return
        }

        lastAttemptedURLString = candidate
        print(String(format: NSLocalizedString("status.url.loadingAttempt", comment: "Attempting to load URL status format"), url.absoluteString, internalLoadAttempts + 1))
        isLoading = true
        webView.stopLoading()
        if scheduleTimeout {
            scheduleFailoverTimeout(for: candidate)
        }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: requestTimeoutInterval)
        webView.load(request)
    }

    private func retryCurrentCandidate() {
        guard let currentAttemptUrl = lastAttemptedURLString else {
            loadNextCandidateOrDefault(reason: "No current URL is available for retry.")
            return
        }

        guard let url = URL(string: currentAttemptUrl) else {
            loadNextCandidateOrDefault(reason: NSLocalizedString("error.url.invalid", comment: "Invalid configured URL reason for switching to default"))
            return
        }

        print("Retrying to load \(currentAttemptUrl)...")
        isLoading = true
        scheduleFailoverTimeout(for: currentAttemptUrl)
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: requestTimeoutInterval)
        webView.load(request)
    }

    private func switchToDefaultURLAndLoad(reason: String) {
        print(String(format: NSLocalizedString("error.url.switchToDefault.reason", comment: "Switching to default URL reason format"), reason))
        applyStartupLoadCommand(startupLoadCoordinator.recover(reason: reason, fallbackServerURL: AppSettings.shared.serverURL))
    }

    func reloadCurrentOrNewURL() {
        guard hasStartedInitialLoad else {
            loadConfiguredURLIfNeeded()
            return
        }

        let newCandidates = AppSettings.shared.serverURLCandidates()
        let newSignature = startupLoadCoordinator.signature(for: newCandidates)
        let newUrlString = newCandidates.first ?? AppSettings.shared.serverURL

        if startupLoadCoordinator.isShowingRecovery {
            print("Recovery page is visible. Rechecking configured URLs: \(newCandidates)")
            beginLoading(candidates: newCandidates)
            return
        }

        if Configuration.isLocalHTMLPath(newUrlString) && newSignature == currentCandidateSignature {
            let isCurrentLocal = startupLoadCoordinator.isCurrentLocalPage(
                urlString: webView.url?.absoluteString,
                isFileURL: webView.url?.isFileURL == true
            )
            currentURLString = Configuration.localHTMLPathValue
            if isCurrentLocal {
                return
            }
            loadLocalHTML()
            return
        }

        if newSignature != currentCandidateSignature || webView.url == nil {
            print("URL settings changed or no page is loaded. New candidates: \(newCandidates)")

            isLoading = true
            beginLoading(candidates: newCandidates)
        } else {
            print("URL settings are unchanged and a page is already loaded.")
        }
    }

    func reloadCurrentPageFromUserAction() {
        guard hasStartedInitialLoad, webView.url != nil else {
            loadConfiguredURLIfNeeded()
            return
        }

        print("Reloading current web page natively: \(String(describing: webView.url))")
        hasReloadedFromOrigin = false
        webView.reload()
    }

    private func loadLocalHTML() {
        guard let url = Configuration.localHTMLURL() else {
            print(String(format: NSLocalizedString("error.webView.localHTMLNotFound", comment: "Local HTML file not found error format"), Configuration.localHTMLFileName))
            isLoading = false
            return
        }

        isLoading = true
        startupLoadCoordinator.clearRecovery()
        currentURLString = Configuration.localHTMLPathValue
        lastAttemptedURLString = url.absoluteString
        webView.stopLoading()
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        print(String(format: NSLocalizedString("status.webView.loadingLocalHTML", comment: "Loading local HTML fallback status format"), url.absoluteString))
    }

    private func loadFirstReachableCandidate(generation: UUID) async {
        var failedCandidates: [String] = []

        for index in startupLoadCoordinator.candidates.indices {
            guard !Task.isCancelled, generation == loadGeneration else {
                return
            }

            guard let candidate = startupLoadCoordinator.candidate(at: index) else {
                continue
            }
            currentURLString = startupLoadCoordinator.displayName(for: candidate)

            if Configuration.isLocalHTMLPath(candidate) {
                loadCandidate(at: index)
                return
            }

            guard URL(string: candidate)?.scheme != nil else {
                print(String(format: NSLocalizedString("error.url.invalid", comment: "Invalid URL string error format"), candidate))
                failedCandidates.append(candidate)
                continue
            }

            if await serverIsReachable(candidate) {
                guard !Task.isCancelled, generation == loadGeneration else {
                    return
                }
                loadCandidate(at: index)
                return
            }

            failedCandidates.append(candidate)
        }

        guard !Task.isCancelled, generation == loadGeneration else {
            return
        }

        applyStartupLoadCommand(startupLoadCoordinator.recover(
            reason: "No configured server URL is reachable.",
            fallbackServerURL: AppSettings.shared.serverURL,
            failedCandidates: failedCandidates.isEmpty ? startupLoadCoordinator.candidates : failedCandidates
        ))
    }

    private func serverIsReachable(_ candidate: String) async -> Bool {
        let timeout = StartupReachabilityPolicy.probeTimeout(seconds: AppSettings.shared.highAvailabilityTimeoutSeconds)
        for url in StartupReachabilityPolicy.probeURLs(for: candidate) {
            if await requestSucceeds(url: url, timeout: timeout) {
                return true
            }
        }
        return false
    }

    private func requestSucceeds(url: URL, timeout: TimeInterval) async -> Bool {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return true
            }
            return (200..<500).contains(httpResponse.statusCode)
        } catch {
            print("Availability probe failed for \(url.absoluteString): \(error.localizedDescription)")
            return false
        }
    }

    private func loadRecoveryHTML(failedCandidates: [String], reason: String) {
        cancelFailoverTimeout()
        availabilityProbeTask?.cancel()
        isSwitchingURL = false
        hasReloadedFromOrigin = false
        internalLoadAttempts = 0
        lastAttemptedURLString = nil
        currentURLString = recoveryDisplayName
        isLoading = true

        let html = RecoveryPageBuilder.html(config: RecoveryPageBuilder.Config(
            failedCandidates: failedCandidates,
            reason: reason,
            shortMark: AppSettings.shared.recoveryShortMark,
            title: AppSettings.shared.recoveryTitle,
            body: AppSettings.shared.recoveryBody,
            qrDetectedMessage: AppSettings.shared.recoveryQRCodeDetectedMessage
        ))

        webView.stopLoading()
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func scheduleFailoverTimeout(for urlString: String) {
        cancelFailoverTimeout()

        guard startupLoadCoordinator.hasRemainingCandidates else {
            return
        }

        let timeout = StartupReachabilityPolicy.failoverDelay(seconds: AppSettings.shared.highAvailabilityTimeoutSeconds)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard self.isLoading, self.lastAttemptedURLString == urlString else { return }

            print("High availability timeout reached for \(urlString). Trying next configured URL.")
            self.applyStartupLoadCommand(self.startupLoadCoordinator.timeout(fallbackServerURL: AppSettings.shared.serverURL))
        }

        failoverTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: workItem)
    }

    private func cancelFailoverTimeout() {
        failoverTimeoutWorkItem?.cancel()
        failoverTimeoutWorkItem = nil
    }

    private func loadNextCandidateOrDefault(reason: String) {
        cancelFailoverTimeout()
        applyStartupLoadCommand(startupLoadCoordinator.mainFrameFailed(
            reason: reason,
            fallbackServerURL: AppSettings.shared.serverURL
        ))
    }

    private func applyStartupLoadCommand(_ command: StartupLoadCoordinator.Command) {
        switch command {
        case let .load(urlString, _, scheduleTimeout):
            loadCandidate(urlString: urlString, scheduleTimeout: scheduleTimeout)
        case let .showRecovery(reason, failedCandidates):
            loadRecoveryHTML(failedCandidates: failedCandidates, reason: reason)
        case .none:
            return
        }
    }

    private var requestTimeoutInterval: TimeInterval {
        StartupReachabilityPolicy.loadTimeout(
            seconds: AppSettings.shared.highAvailabilityTimeoutSeconds,
            highAvailabilityEnabled: AppSettings.shared.highAvailabilityEnabled
        )
    }

    private func markFinishedLoad(for webView: WKWebView) {
        isSwitchingURL = false
        isLoading = false
        internalLoadAttempts = 0

        if startupLoadCoordinator.isShowingRecovery {
            currentURLString = recoveryDisplayName
            return
        }

        let activeURL = webView.url?.isFileURL == true
            ? Configuration.localHTMLPathValue
            : (webView.url?.absoluteString ?? currentURLString ?? AppSettings.shared.serverURL)

        currentURLString = startupLoadCoordinator.displayName(for: activeURL)
        AppSettings.shared.markActiveServerURL(currentURLString ?? activeURL)
    }

    // MARK: - WKNavigationDelegate Methods

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        print("WebView didStartProvisionalNavigation for: \(String(describing: webView.url))")
        isLoading = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("WebView didFinish navigation for: \(String(describing: webView.url))")
        cancelFailoverTimeout()
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
                        self.markFinishedLoad(for: webView)
                    }
                } else {
                    self.markFinishedLoad(for: webView)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self = self, self.isSwitchingURL else { return }
                print("Fallback: still switching URL after 3 seconds, forcing reload")
                self.webView.reload()
                self.markFinishedLoad(for: webView)
            }
        } else {
            markFinishedLoad(for: webView)
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
        cancelFailoverTimeout()

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            print("Ignoring cancelled navigation for \(String(describing: failedURL)).")
            return
        }

        isLoading = false

        guard let currentAttemptUrl = lastAttemptedURLString, failedURL == currentAttemptUrl else {
            print("Load error for a URL (\(String(describing: failedURL))) that is not the last one attempted (\(String(describing: lastAttemptedURLString))). Ignoring retry logic for this specific error.")
            return
        }

        internalLoadAttempts += 1
        print("Load attempt \(internalLoadAttempts) failed for \(currentAttemptUrl). Error: \(error.localizedDescription)")

        if startupLoadCoordinator.hasRemainingCandidates {
            loadNextCandidateOrDefault(reason: error.localizedDescription)
            return
        }

        if internalLoadAttempts < maxLoadAttempts {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.retryCurrentCandidate()
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
        sendDataToWebView(data: WebViewErrorPayload.response(action: action, error: error))
    }

    func sendDataToWebView(data: [String: Any]) {
        let scriptResult = BridgeScriptBuilder.nativeResultScript(payload: data)
        if scriptResult.kind == .fallback {
            print(String(format: NSLocalizedString("error.internalError.jsonResponseFailed", comment: "Failed to serialize to JSON string error"), String(describing: data)))
        }
        evaluateJavaScript(script: scriptResult.script)
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
