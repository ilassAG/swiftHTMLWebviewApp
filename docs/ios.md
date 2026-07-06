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

The iOS app loads its startup URL from the Settings bundle. The demo wrapper
defaults to `local`, which loads the bundled demo page from
`ios/swiftHTMLWebviewApp/HTML/`. Remote URLs can still be configured through
Settings, QR configuration, or private app variants.

Runtime settings:

| Key | Default | Purpose |
| --- | --- | --- |
| `server_url_preference` | `local` | Primary web app URL. `local`, `bundle`, an empty value, and `about:local` all load the bundled HTML. |
| `security_token_preference` | empty | Optional token made available to native code that needs protected configuration updates. Protected writes require a non-empty stored token and matching request token. |
| `ha_enabled` | `false` | Enables legacy-compatible startup URL failover. |
| `ha_timeout` | `5` | Seconds to wait for a remote URL before the next candidate is tried. |
| `ha_url2` | empty | First fallback URL. |
| `ha_url3` | empty | Second fallback URL. |
| `ha_url4` | empty | Third fallback URL. |
| `active_server_url` | empty | Internal value updated after a successful load. |
| `last_server_url` | empty | Internal value updated with the last successful URL. |
| `beacon_uuid` | `00000000-0000-0000-0000-000000000000` | iBeacon Proximity UUID used by the continuous beacon bridge. |
| `app_uuid` | generated on first start | Read-only native app installation UUID. It is returned as `appUUID` and is not changed by Settings, QR config, or `settingsSet`. |
| `device_name` | empty | Deployment-specific display name for this wrapper install. |
| `device_uuid` | generated on first start | Writable deployment/station identifier exposed through settings APIs. |
| `device_location` | empty | Deployment-specific physical/logical location label. |

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
- `portraitCapture` for native pass-photo capture with face-count validation,
  burst variants, optional background removal, and face-centered square crop.
  Front-camera preview is mirrored, but final output is unmirrored by default;
  set `mirrorOutput: true` to request mirrored output.
- `dataScanStart` / `dataScanEnd`
- `loginScanStart` / `loginScanEnd`
- `previewBoxLocationUpdate`
- `nfcTagRead`
- `beaconsStart` / `beaconsStop`
- `beaconAdvertiseStart` / `beaconAdvertiseStop`
- `arPositionStart` / `arPositionStop`
- `roomPlanScanStart` / `roomPlanScanStop` / `roomPlanScanExport`

Continuous scanner events are delivered as `barcodeData` or `barcodeLogin`.
Beacon ranging events are delivered as `beacons`. All continuous events use the
same `window.handleNativeResult(...)` callback as one-shot bridge actions.
`beaconAdvertiseStart` uses CoreBluetooth to transmit as an iBeacon with the
configured or requested UUID plus the requested `major` and `minor` values.
Stop advertising with `beaconAdvertiseStop`.

`nfcTagRead` uses CoreNFC `NFCTagReaderSession` for one-shot tag reads. The app
needs `NFCReaderUsageDescription` and the Near Field Communication Tag Reading
capability with `NDEF`/`TAG` reader-session formats in the signing profile. The
default iOS reader polls ISO 14443 and ISO 15693 tags; FeliCa / ISO 18092 is not
enabled by default because Apple requires additional FeliCa system-code
entitlements for that polling mode.

## Optional Stripe Tap to Pay

The source contains `TapToPayBridge.swift`, but it is guarded with `#if canImport(StripeTerminal)`.

That means:

- The app builds without StripeTerminal.
- Web content can still call `tapToPayAvailability` and gets a normal bridge
  envelope with `success: true` and `available: false`.
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
It includes Bluetooth usage descriptions for the BLE config-pairing bridge and
iBeacon advertising.

## Runtime Diagnostics

iOS implements the shared runtime bridge actions:

- `deviceInfoGet`
- `settingsGet` / `settingsSet`
- `screenOrientationGet` / `screenOrientationSet`
- `wifiStatusGet` / `wifiConfigure`
- `screenshotGet`
- `geoLocationGet` / `geoLocationStart` / `geoLocationStop`
- `arPositionStart` / `arPositionStop`
- `arOverlayOpen` / `arOverlayClose`
- `roomPlanScanStart` / `roomPlanScanStop` / `roomPlanScanExport`
- `soundPlay`
- `notificationPermissionGet` / `notificationPermissionRequest`
- `notificationShow` / `notificationSchedule`
- `notificationCancel` / `notificationCancelAll` / `notificationList`
- `idleTimerStart` / `idleTimerReset` / `idleTimerStop`
- `sensorCapabilitiesGet` / `sensorStreamStart` / `sensorStreamStop`
- `screenStreamStart` / `screenStreamStop`
- `natsProvision` / `natsStatus` / `natsConnect` / `natsDisconnect` /
  `natsPublish`

Provisioned NATS clients use the Swift Package `nats.swift` and subscribe to
`swift.wrapper.<appUUID>.commands.*` for the generic remote management
commands. Remote QR image decoding replies with scanned QR payloads, and
`screenStreamStart` can publish JPEG app-surface frames over NATS subjects.
`.creds` material is stored in Keychain and written only to a private temporary
file while the iOS NATS client is connected.
- `nfcTagRead`
- `beaconAdvertiseStart` / `beaconAdvertiseStop`
- `configPairingShow` / `configPairingStop`
- `configPairingConnect` / `configPairingDisconnect`
- `configPairingSend`

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

Local notifications use `UNUserNotificationCenter`. The bridge can request
alert/sound/badge permission, show immediate notifications, schedule
time-interval notifications, cancel pending or delivered notifications, and
report notification opens back to the web app as `notificationOpened`.

## Config Pairing

iOS can act as both config target and config device. As target, it starts a
short-lived BLE GATT session and displays a QR code with
`configPairingShow`. The same UI opens through a two-finger long press in the
center of the WebView for about 1.5 seconds. As config device, it scans or
receives the QR payload, calls `configPairingConnect`, then sends
`configPairingSend` commands.

The pairing QR includes read-only `appUUID` plus `deviceName`, `deviceUUID`,
and `deviceLocation` from the target settings so the config device can identify
the target before sending commands. It does not include the persistent security
token.

Writable target commands require the current
`security_token_preference`. `wifiConfigure` still uses
`NEHotspotConfigurationManager`, so the target device shows Apple's system join
confirmation and needs the Hotspot Configuration capability.

Config QR codes can also set the same runtime settings directly. JSON payloads
accept `appConfig` or `store` objects; URL/query payloads accept
`store[key]=value` / `appConfig[key]=value` and `wifi[ssid]` plus
`wifi[pw]` / `wifi[password]` / `wifi[passphrase]`. `appConfig` is stored as a
persistent non-sensitive JSON object in `UserDefaults` and is returned by
`settingsGet`. `appUUID` values in incoming config payloads are ignored because
the native app owns that immutable installation identifier.
