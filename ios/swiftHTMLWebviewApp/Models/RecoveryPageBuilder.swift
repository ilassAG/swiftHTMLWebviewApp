//
//  RecoveryPageBuilder.swift
//  swiftHTMLWebviewApp
//
//  Builds the startup recovery page HTML outside WebView navigation state.
//

import Foundation

enum RecoveryPageBuilder {
    struct Config {
        var failedCandidates: [String] = []
        var reason: String = ""
        var shortMark: String = ""
        var title: String = ""
        var body: String = ""
        var qrDetectedMessage: String = ""
    }

    static func html(config: Config) -> String {
        let candidateItems = config.failedCandidates
            .map { "<li><code>\(escapedHTML($0))</code></li>" }
            .joined(separator: "")
        let recoveryShortMark = escapedHTML(config.shortMark)
        let recoveryTitle = escapedHTML(config.title)
        let recoveryBody = escapedHTML(config.body)
        let recoveryQRCodeDetectedMessage = escapedJavaScriptString(config.qrDetectedMessage)
        let checkedAddressLabel = config.failedCandidates.count == 1 ? "Geprüfte Adresse" : "Geprüfte Adressen"

        return """
        <!doctype html>
        <html lang="de">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
          <title>\(recoveryTitle) Verbindung</title>
          <style>
            :root { color-scheme: light; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; background: #f4f8ff; color: #14213d; }
            * { box-sizing: border-box; }
            body { margin: 0; min-height: 100vh; display: grid; place-items: center; padding: 28px; background: linear-gradient(180deg, #eef6ff 0%, #ffffff 48%, #f7fbff 100%); }
            main { width: min(520px, 100%); display: grid; gap: 18px; }
            .logo { width: 76px; height: 76px; border-radius: 22px; display: grid; place-items: center; background: #ffffff; border: 1px solid #d8e7ff; box-shadow: 0 18px 38px rgba(10, 132, 255, 0.18); }
            .logo svg { width: 56px; height: 56px; display: block; }
            .sr-only { position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px; overflow: hidden; clip: rect(0, 0, 0, 0); white-space: nowrap; border: 0; }
            h1 { margin: 0; font-size: 32px; line-height: 1.08; letter-spacing: 0; }
            p { margin: 0; color: #4f5f76; font-size: 16px; line-height: 1.45; }
            ul { margin: 4px 0 0; padding: 0; list-style: none; display: grid; gap: 8px; }
            li { padding: 10px 12px; border: 1px solid #d8e7ff; border-radius: 10px; background: #ffffff; overflow-wrap: anywhere; }
            code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; color: #0a63ce; font-size: 13px; }
            .actions { display: grid; gap: 10px; }
            button { width: 100%; min-height: 54px; border: 0; border-radius: 14px; background: #0a84ff; color: #ffffff; font: 800 17px -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; }
            button.secondary { background: #ffffff; color: #0a63ce; border: 1px solid #b9d7ff; }
            .meta { color: #6d7d93; font-size: 13px; }
            #status { min-height: 18px; color: #0a63ce; font-size: 14px; font-weight: 700; }
          </style>
        </head>
        <body>
          <main>
            <div class="logo" aria-label="\(recoveryShortMark)">
              <svg viewBox="0 0 64 64" aria-hidden="true">
                <path fill="#ff6b2b" d="M49.5 13.5c6.4 7.7 8.5 17.8 4.7 26.7-4 9.4-13.3 14.7-25.8 14.7-9 0-16.7-3.1-22.4-8.8 6.9 2.7 14.7 2.1 20.7-1.4C17.7 38 10.8 29.5 6.8 19.4c7.4 6.8 15.3 12.1 23.8 15.8C22.8 27 17.1 18.7 13.4 10.1c9.4 10.5 19.6 18.2 30.8 23.3 1.7-6.6.1-13.1-4.2-19.6 3.4 1.3 6.6 3 9.5 5.1z"/>
                <path fill="#0a84ff" d="M13 46.3c8.8 5.2 19.4 5.5 29.4 1.1-3.9 5.4-10.7 8.6-19.3 8.6-7.2 0-13.5-2.7-18.1-7.2 2.7.2 5.4-.6 8-2.5z"/>
              </svg>
              <span class="sr-only">\(recoveryShortMark)</span>
            </div>
            <h1>\(recoveryTitle)</h1>
            <p>\(recoveryBody)</p>
            <div class="actions">
              <button type="button" onclick="scanQR()">QR-Code scannen</button>
              <button class="secondary" type="button" onclick="retry()">Erneut prüfen</button>
            </div>
            <p id="status"></p>
            <section>
              <p class="meta">\(checkedAddressLabel)</p>
              <ul>\(candidateItems)</ul>
            </section>
            <p class="meta">Grund: \(escapedHTML(config.reason))</p>
          </main>
          <script>
            const bridge = window.webkit?.messageHandlers?.swiftBridge;
            const status = document.getElementById('status');
            function setStatus(text) { status.textContent = text || ''; }
            function scanQR() {
              setStatus('Scanner wird geöffnet...');
              bridge?.postMessage({
                action: 'continuousScanStart',
                purpose: 'configPairing',
                source: 'recovery',
                camera: 'front',
                types: ['qr'],
                showFlipButton: true,
                repeatDelaySeconds: 1
              });
            }
            function retry() {
              setStatus('Server wird erneut geprüft...');
              bridge?.postMessage({ action: 'reload', source: 'recovery' });
            }
            window.handleNativeResult = function(result) {
              if (result?.error) {
                setStatus(result.error);
              } else if (result?.action === 'scanBarcode') {
                setStatus('\(recoveryQRCodeDetectedMessage)');
              }
            };
          </script>
        </body>
        </html>
        """
    }

    static func escapedHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    static func escapedJavaScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "<", with: "\\u003C")
            .replacingOccurrences(of: ">", with: "\\u003E")
            .replacingOccurrences(of: "&", with: "\\u0026")
    }
}
