# iOS

The iOS app lives in `ios/`.

## Open in Xcode

```sh
open ios/swiftHTMLWebviewApp.xcodeproj
```

Select the `swiftHTMLWebviewApp` scheme and build for simulator or device.

The Go mobile binding is optional. A clean checkout builds without
`ios/Frameworks/Printercore.xcframework`; printer actions then return a
structured unavailable response. Generate and link the binding when enabling the
shared Go printer core:

```sh
printercore/scripts/build_mobile.sh
```

## Default configuration

The iOS app loads its startup URL from the Settings bundle. The value `local`
loads the bundled demo page from `ios/swiftHTMLWebviewApp/HTML/`.

Runtime settings:

| Key | Default | Purpose |
| --- | --- | --- |
| `server_url_preference` | `local` | Primary web app URL. `local`, `bundle`, an empty value, and `about:local` all load the bundled HTML. |
| `security_token_preference` | `change-me-before-production` | Optional token made available to native code that needs protected configuration updates. |
| `ha_enabled` | `false` | Enables Kassa-compatible startup URL failover. |
| `ha_timeout` | `5` | Seconds to wait for a remote URL before the next candidate is tried. |
| `ha_url2` | empty | First fallback URL. |
| `ha_url3` | empty | Second fallback URL. |
| `ha_url4` | empty | Third fallback URL. |
| `active_server_url` | empty | Internal value updated after a successful load. |
| `last_server_url` | empty | Internal value updated with the last successful URL. |
| `beacon_uuid` | `7763A937-B779-4D31-A20C-49E83047048F` | iBeacon Proximity UUID used by the continuous beacon bridge. |

When HA is enabled, the app tries `server_url_preference` first, then `ha_url2`,
`ha_url3`, and `ha_url4` in order. If every configured remote URL fails, the app
falls back to `local` so the wrapper remains usable. Without HA, the existing
single-URL behavior is preserved.

`beacon_uuid` is an iBeacon Proximity UUID, not a cryptographic hash. iOS and
Android can only range iBeacons for a configured UUID/region, so deployments
that use their own beacon fleet must change this value before starting beacon
scanning.

## Continuous Scanner and Beacons

The iOS wrapper includes:

- `continuousScanStart` / `continuousScanStop`
- `dataScanStart` / `dataScanEnd`
- `loginScanStart` / `loginScanEnd`
- `previewBoxLocationUpdate`
- `beaconsStart` / `beaconsStop`

Continuous scanner events are delivered as `barcodeData` or `barcodeLogin`.
Beacon ranging events are delivered as `beacons`. All continuous events use the
same `window.handleNativeResult(...)` callback as one-shot bridge actions.

## Optional Stripe Tap to Pay

The source contains `TapToPayBridge.swift`, but it is guarded with `#if canImport(StripeTerminal)`.

That means:

- The app builds without StripeTerminal.
- Web content can still call `tapToPayAvailability` and gets `available: false`.
- Adding StripeTerminal to the Xcode project enables the native Tap to Pay implementation.

See `docs/stripe-tap-to-pay.md`.

## Optional Printer Core

`PrinterBridge.swift` is backed by `ios/Frameworks/Printercore.xcframework`.
Web content can call `printerDiscover` to scan the local IPv4 network for Epson
ePOS-Print endpoints and probable raw ESC/POS TCP printers. It can call
`printerHelloWorld` for selected Epson targets or `printerEpsonHelloWorld` with
an Epson printer host such as `192.0.2.10`.
The generic Xcode project does not hard-link the generated XCFramework, so add
it to the app target after running `printercore/scripts/build_mobile.sh` if
Epson printer support should be active in that build.
The app includes `NSLocalNetworkUsageDescription` for LAN printer access.
It also includes `NSLocationWhenInUseUsageDescription` so the iBeacon ranging
bridge can request the permission that iOS requires for beacon ranging.

## Runtime Diagnostics

iOS implements the shared runtime bridge actions:

- `deviceInfoGet`
- `screenOrientationGet` / `screenOrientationSet`
- `wifiStatusGet` / `wifiConfigure`
- `screenshotGet`
- `geoLocationGet` / `geoLocationStart` / `geoLocationStop`
- `soundPlay`
- `idleTimerStart` / `idleTimerReset` / `idleTimerStop`
- `sensorCapabilitiesGet` / `sensorStreamStart` / `sensorStreamStop`
- `screenStreamStart` / `screenStreamStop`

`wifiConfigure` uses `NEHotspotConfigurationManager` and needs Apple's Hotspot
Configuration capability for production use. `wifiStatusGet` uses
`NEHotspotNetwork.fetchCurrent` and can expose the current SSID, BSSID, and
security type only when the App ID/profile also contains the Access WiFi
Information capability and iOS grants access to the current network details. The
user still approves the join in the system UI. If the app is not signed with the
Hotspot Configuration capability, iOS can return an
`internal error.` from `NEHotspotConfiguration`; the bridge exposes the native
error domain/code and reports the missing capability hint.

`screenStreamStart` currently captures the app/WebView surface with
`WKWebView.takeSnapshot` and streams JPEG frames to a WebSocket target. It does
not start a system-wide ReplayKit broadcast.
