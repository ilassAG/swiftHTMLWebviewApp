# swiftHTMLWebviewApp

`swiftHTMLWebviewApp` is a native WebView app wrapper for HTML/JavaScript applications that need access to device features such as camera, barcode scanning, document scanning, PDF generation, confetti, and optional payment capabilities.

The project started as an iOS wrapper. The repository is now structured to support iOS and Android with a shared web-facing bridge contract.
Printer smoke tests share a small Go core that can be bound into both mobile platforms.

![App Screenshot](media/v8screenshot.png)

## Repository Layout

```text
swiftHTMLWebviewApp/
  ios/                         # iOS Xcode project
    swiftHTMLWebviewApp.xcodeproj
    swiftHTMLWebviewApp/
  android/                     # Android WebView wrapper
  docs/                        # Platform and bridge documentation
  examples/                    # Web examples for wrapper features
  media/                       # Screenshots and documentation assets
  printercore/                 # Shared Go printer core and CLI smoke test
```

## Features

### iOS

- Secure WebView container for remote or local HTML/JS content.
- Native camera/photo capture.
- Document scanning.
- QR/barcode scanning.
- Embedded continuous QR/barcode scanning for web-app workflows.
- Continuous iBeacon ranging events using the configured Proximity UUID.
- PDF generation.
- Native confetti burst from JavaScript.
- QR-code based configuration for server URL and security token.
- Settings bundle for runtime configuration, including local/remote startup URL,
  optional high-availability fallback URLs, and the iBeacon Proximity UUID.
- Optional Stripe Terminal / Tap to Pay bridge.
- Optional Epson network-printer smoke test through the Go printer core.

### Android

Android support lives in `android/` as a native WebView wrapper with the same web-facing bridge shape. The implementation includes the WebView container, local smoke-test page, camera/scanner bridge features, and structured bridge responses. The Go printer core is linked as a generated AAR for Epson network-printer smoke tests.

## Getting Started: iOS

Prerequisites:

- Xcode 15 or later
- iOS 17.6+ for the base app
- A real iPhone for Tap to Pay tests

Open the project:

```sh
open ios/swiftHTMLWebviewApp.xcodeproj
```

Build the `swiftHTMLWebviewApp` scheme.

## JavaScript Bridge

Web content sends messages through WebKit:

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'scanBarcode',
  requestId: crypto.randomUUID()
});
```

Native code responds by calling:

```js
window.handleNativeResult = function(result) {
  console.log(result);
};
```

See `docs/native-bridge.md` for the bridge contract.

## Built-in Bridge Actions

- `scanDocument`
- `takePhoto`
- `scanBarcode`
- `continuousScanStart` / `continuousScanStop`
- `dataScanStart` / `dataScanEnd` (Kassa-compatible aliases)
- `loginScanStart` / `loginScanEnd` (Kassa-compatible aliases)
- `previewBoxLocationUpdate`
- `beaconsStart` / `beaconsStop`
- `deviceInfoGet`
- `screenOrientationGet` / `screenOrientationSet`
- `wifiStatusGet` / `wifiConfigure`
- `screenshotGet`
- `geoLocationGet` / `geoLocationStart` / `geoLocationStop`
- `soundPlay`
- `idleTimerStart` / `idleTimerReset` / `idleTimerStop`
- `sensorCapabilitiesGet` / `sensorStreamStart` / `sensorStreamStop`
- `screenStreamStart` / `screenStreamStop`
- `launchConfetti`
- `tapToPayAvailability` (optional Stripe module)
- `tapToPayCollect` (optional Stripe module)
- `printerDiscover` (optional Go printer core)
- `printerHelloWorld` (routes to the selected discovered printer)
- `printerEpsonHelloWorld` (optional Go printer core)

## Printer Core Smoke Test

The shared Go printer core can be tested before rebuilding the mobile apps:

```sh
cd printercore
go test ./...
go run ./cmd/pmprint -dry-run
go run ./cmd/pmprint -host <printer-ip>
```

The mobile demo page can call `printerDiscover` to scan the local IPv4 `/24`
network for Epson ePOS-Print endpoints and probable raw ESC/POS TCP printers.
On Android/Sunmi devices the native bridge adds the internal printer when the
Sunmi AIDL service is visible.

The generated mobile bindings are optional and ignored by git. A clean checkout
still builds without them; printer actions then return a structured unavailable
response except for Android/Sunmi internal printing.

Generate or refresh the Android AAR and iOS XCFramework when enabling the Go
printer core in a local app build:

```sh
printercore/scripts/build_mobile.sh
```

## Screen Stream Viewer

The demo screen-stream bridge sends app-screen JPEG frames over WebSocket. A
small Go viewer can receive the stream and show total bytes, throughput, FPS,
and the latest frame:

```sh
cd tools/screenstreamviewer
go run . -addr :18090
```

Open `http://<mac-ip>:18090/` in a browser and set the app demo page target to
`ws://<mac-ip>:18090/screen`.

`RUNNING_URLS.md` can be used locally to record current LAN/test URLs, but it is
ignored by git and should not be committed.

## Optional Stripe Tap to Pay

Stripe/Tap-to-Pay support is included as optional source code.

Important behavior:

- The app builds without StripeTerminal linked.
- Without StripeTerminal, `tapToPayAvailability` returns `available: false`.
- When StripeTerminal is linked and Apple capabilities are configured, `tapToPayCollect` can start a native Tap to Pay flow.

See `docs/stripe-tap-to-pay.md` for setup, entitlements, backend requirements, and JS payload examples.

## Platform Docs

- `docs/ios.md`
- `docs/android.md`
- `docs/native-bridge.md`
- `docs/stripe-tap-to-pay.md`

## Configuration via QR Code

The app can update its server URL and security token by scanning a QR code containing:

```json
{
  "toolmode": "changeConfig",
  "defaultServerUrl": "https://your.server.url/",
  "securityToken": "YOUR_TOKEN"
}
```

The iOS Settings app also supports a local page mode (`local`), an optional
high-availability URL list (`ha_enabled`, `ha_timeout`, `ha_url2`, `ha_url3`,
`ha_url4`), and an iBeacon Proximity UUID (`beacon_uuid`). The HA keys are kept
compatible with the existing Kassa iOS naming so deployments can reuse the same
configuration model.

Optional token rotation:

```json
{
  "toolmode": "changeConfig",
  "defaultServerUrl": "https://your.server.url/",
  "securityToken": "CURRENT_TOKEN",
  "newSecurityToken": "NEW_TOKEN"
}
```

## Design Principle

The wrapper exposes native capabilities. Product-specific logic should stay in the consuming web app and backend:

- Tenant/customer configuration
- Stripe account selection
- Payment/session state
- SMS/receipt workflows
- Business-specific screens

## License

See `LICENSE`.
