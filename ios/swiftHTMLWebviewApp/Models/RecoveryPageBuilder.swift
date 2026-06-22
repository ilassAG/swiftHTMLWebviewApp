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
        let checkedAddressLabel = config.failedCandidates.count == 1 ? "Gepruefte Adresse" : "Gepruefte Adressen"

        return """
        <!doctype html>
        <html lang="de">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
          <title>\(recoveryTitle) Verbindung</title>
          <style>
            :root { color-scheme: dark; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; background: #07110c; color: #f4fff2; }
            * { box-sizing: border-box; }
            body { margin: 0; min-height: 100vh; display: grid; place-items: center; padding: 28px; background: radial-gradient(circle at 50% 0%, #173326 0, #07110c 52%, #030604 100%); }
            main { width: min(520px, 100%); display: grid; gap: 18px; }
            .logo { width: 72px; height: 72px; border-radius: 20px; display: grid; place-items: center; background: linear-gradient(135deg, #a7ef6f, #66d0b3); color: #07110c; font-size: 34px; font-weight: 900; }
            h1 { margin: 0; font-size: 32px; line-height: 1.08; letter-spacing: 0; }
            p { margin: 0; color: rgba(244, 255, 242, 0.74); font-size: 16px; line-height: 1.45; }
            ul { margin: 4px 0 0; padding: 0; list-style: none; display: grid; gap: 8px; }
            li { padding: 10px 12px; border: 1px solid rgba(244, 255, 242, 0.13); border-radius: 10px; background: rgba(255, 255, 255, 0.04); overflow-wrap: anywhere; }
            code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; color: #b7f58b; font-size: 13px; }
            .actions { display: grid; gap: 10px; }
            button { width: 100%; min-height: 54px; border: 0; border-radius: 14px; background: #a7ef6f; color: #07110c; font: 800 17px -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; }
            button.secondary { background: rgba(255, 255, 255, 0.08); color: #f4fff2; border: 1px solid rgba(244, 255, 242, 0.16); }
            .meta { color: rgba(244, 255, 242, 0.52); font-size: 13px; }
            #status { min-height: 18px; color: rgba(244, 255, 242, 0.66); font-size: 14px; }
          </style>
        </head>
        <body>
          <main>
            <div class="logo">\(recoveryShortMark)</div>
            <h1>Server nicht erreichbar</h1>
            <p>\(recoveryBody)</p>
            <div class="actions">
              <button type="button" onclick="scanQR()">QR-Code scannen</button>
              <button class="secondary" type="button" onclick="retry()">Erneut pruefen</button>
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
              setStatus('Scanner wird geoeffnet...');
              bridge?.postMessage({ action: 'scanBarcode', source: 'recovery', types: ['qr'] });
            }
            function retry() {
              setStatus('Server wird erneut geprueft...');
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
