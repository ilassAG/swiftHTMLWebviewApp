# Native Bridge

The wrapper exposes native features to web content through WebKit message handlers.

## Message handler

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'scanBarcode',
  requestId: crypto.randomUUID()
});
```

Native code answers by calling:

```js
window.handleNativeResult(result)
```

Each request should include a `requestId` when the web app needs to correlate asynchronous responses.

## Common response shape

Success:

```json
{
  "action": "scanBarcode",
  "requestId": "...",
  "code": "..."
}
```

Error:

```json
{
  "action": "scanBarcode",
  "requestId": "...",
  "error": "Human-readable error"
}
```

## Built-in actions

- `scanDocument`
- `takePhoto`
- `scanBarcode`
- `nfcTagRead`
- `continuousScanStart` / `continuousScanStop`
- `dataScanStart` / `dataScanEnd` (Kassa-compatible continuous scanner aliases)
- `loginScanStart` / `loginScanEnd` (Kassa-compatible continuous scanner aliases)
- `previewBoxLocationUpdate`
- `beaconsStart` / `beaconsStop`
- `beaconAdvertiseStart` / `beaconAdvertiseStop`
- `deviceInfoGet`
- `settingsGet` / `settingsSet`
- `screenOrientationGet` / `screenOrientationSet`
- `wifiStatusGet` / `wifiConfigure`
- `screenshotGet`
- `geoLocationGet` / `geoLocationStart` / `geoLocationStop`
- `soundPlay`
- `idleTimerStart` / `idleTimerReset` / `idleTimerStop`
- `sensorCapabilitiesGet` / `sensorStreamStart` / `sensorStreamStop`
- `screenStreamStart` / `screenStreamStop`
- `configPairingShow` / `configPairingStop`
- `configPairingConnect` / `configPairingDisconnect`
- `configPairingSend`
- `launchConfetti`
- `tapToPayAvailability` (optional Stripe module)
- `tapToPayCollect` (optional Stripe module)
- `printerDiscover` (optional Go printer core)
- `printerHelloWorld` (selected-printer smoke test)
- `printerEpsonHelloWorld` (optional Go printer core)

## Native runtime configuration

Startup URL and iBeacon region settings are native app configuration, not bridge
actions. On iOS they live in Settings.bundle:

- `server_url_preference`: primary web app URL, or `local` for bundled HTML.
- `ha_enabled`: enables Kassa-compatible URL failover.
- `ha_timeout`: seconds to wait before trying the next configured URL.
- `ha_url2`, `ha_url3`, `ha_url4`: fallback URLs.
- `beacon_uuid`: iBeacon Proximity UUID used by the continuous beacon bridge
  when that native module is enabled.
- `device_name`: deployment-specific display name for this wrapper install.
- `device_uuid`: persistent per-install identifier. Native code generates one
  on first start if the value is empty.
- `device_location`: deployment-specific physical/logical location label.

Web apps should not hard-code these values. They should treat the native wrapper
as the owner of startup URL selection and beacon-region selection.

## External config pairing

iOS and Android expose a small BLE-based configuration transport so one
installed wrapper can configure another nearby wrapper without changing the
hosted web app. The target device can start pairing either through the bridge or
by a two-finger long press in the center of the WebView for about 1.5 seconds:

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'configPairingShow'
});
```

The native app displays a QR code containing an ephemeral
`swifthtml-config://pair?...` payload and advertises a BLE GATT service. The QR
payload contains only a short-lived session id, BLE service UUID, and random
session secret. It does not contain the persistent `security_token_preference`.
After the first config device connects and subscribes for responses, the target
closes the QR pairing UI and stops advertising so another device cannot start a
parallel pairing attempt. Close the target pairing UI manually with
`configPairingStop`.

The configuring device scans or receives the QR payload, connects, and sends
commands:

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'configPairingConnect',
  payload: 'swifthtml-config://pair?...'
});

window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'configPairingSend',
  command: 'settingsSet',
  token: 'current-security-token',
  settings: {
    serverURL: 'https://example.invalid/app/',
    highAvailabilityEnabled: true,
    highAvailabilityTimeoutSeconds: 5,
    highAvailabilityURL2: 'https://backup-1.example.invalid/app/',
    highAvailabilityURL3: '',
    highAvailabilityURL4: '',
    beaconUUID: '7763A937-B779-4D31-A20C-49E83047048F',
    deviceName: 'Kasse AP03',
    deviceLocation: 'Zelt A / Eingang'
  }
});
```

Large target responses are split into `configPairingChunk` BLE notifications by
native code and reassembled before the web app receives the final
`configPairingResponse`.

Supported `configPairingSend.command` values:

- `statusGet`: returns settings plus platform device status/details.
- `settingsGet`: returns non-sensitive native settings.
- `settingsSet`: updates URL/HA/beacon/device identity settings and optionally
  rotates the security token through `settings.newSecurityToken`. The current
  token is still required in `token`.
- `wifiConfigure`: asks the target OS to add/join a WLAN with `ssid` and
  `passphrase`.
- `reload`: reloads the target wrapper from its configured startup URL.

`settingsSet`, `wifiConfigure`, and `reload` require the current security token
in `token` or `securityToken`. Platform WLAN rules still apply: iOS and modern
Android show system confirmation UI, so WLAN changes are not silent.

The local demo page includes a `Config Pairing` panel for both roles: show the
target QR, scan a pairing QR, connect, fetch status/settings, set URL/HA/beacon
settings, configure target WLAN, and reload the target.

The same settings are available locally through direct JS bridge actions:

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'settingsGet'
});

window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'settingsSet',
  token: 'current-security-token',
  settings: {
    deviceName: 'Kasse AP03',
    deviceUUID: '4EF955C4-DC2B-4328-9B4D-1D0341B9DF90',
    deviceLocation: 'Zelt A / Eingang'
  }
});
```

`settingsGet` returns non-sensitive values plus `securityTokenSet`.
`settingsSet` requires the current security token. If `deviceUUID` is omitted,
the existing UUID is kept. If it is explicitly set to an empty string, native
code generates and stores a new UUID.

## Continuous scanner

iOS exposes an embedded long-running scanner with camera selection and a
relative preview rectangle. The Kassa-compatible `dataScanStart` and
`loginScanStart` aliases are supported by the same implementation.

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'dataScanStart',
  camera: 'back',
  mode: 'data',
  repeatDelaySeconds: 1.2,
  types: ['qr', 'ean13', 'ean8', 'code128', 'datamatrix'],
  previewRect: { top: 0.18, left: 0.1, width: 0.8, height: 0.36 }
});
```

The preview rectangle accepts relative values from `0` to `1`. Percent-like
values from `0` to `100` are also accepted by the native iOS bridge.

Scanner events are pushed through `window.handleNativeResult(...)`:

```json
{
  "action": "barcodeData",
  "sourceAction": "dataScanStart",
  "mode": "data",
  "camera": "back",
  "format": "qr",
  "code": "..."
}
```

For login mode the event action is `barcodeLogin`. Stop the scanner with
`dataScanEnd`, `loginScanEnd`, or `continuousScanStop`. Move the active preview
with `previewBoxLocationUpdate`.

Android uses CameraX and ML Kit for the same continuous scanner action names.

## NFC tag reading

`nfcTagRead` starts one native NFC reader session and returns when the user
presents a tag, cancels, or the session times out. The first implementation
focuses on tag metadata and NDEF payloads. Platform privacy and tag-technology
limits apply: iOS exposes only the identifiers and data allowed by CoreNFC, and
Android exposes technology-specific details only when the tag/driver provides
them.

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'nfcTagRead',
  requestId: crypto.randomUUID(),
  timeoutSeconds: 30
});
```

Typical response:

```json
{
  "platform": "ios",
  "action": "nfcTagRead",
  "success": true,
  "tag": {
    "type": "miFare",
    "identifierHex": "04A1B2C3D4E5F6",
    "identifierBase64": "BKGyw9Tl9g==",
    "ndefAvailable": true,
    "ndefWritable": true,
    "ndefStatus": "readWrite",
    "ndefCapacityBytes": 512
  },
  "ndef": {
    "available": true,
    "status": "readWrite",
    "recordCount": 1,
    "records": [
      {
        "index": 0,
        "typeNameFormat": "nfcWellKnown",
        "type": "T",
        "text": "Hallo NFC",
        "languageCode": "de",
        "payloadBase64": "..."
      }
    ]
  }
}
```

On Android the `tag.technologies` array may include values such as `NfcA`,
`IsoDep`, `Ndef`, `MifareUltralight`, or `NfcV`. On iOS the app must be signed
with the Near Field Communication Tag Reading capability and the
`com.apple.developer.nfc.readersession.formats` entitlement for `NDEF`/`TAG`.
The bundled demo page exposes this through `NFC Tag lesen`.

## iBeacon ranging

iOS and Android can range the configured iBeacon Proximity UUID and push
continuous events to the web app. Android uses the AltBeacon library.

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'beaconsStart'
});
```

To override the native Settings value for one session:

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'beaconsStart',
  uuid: '7763A937-B779-4D31-A20C-49E83047048F'
});
```

Typical event:

```json
{
  "action": "beacons",
  "success": true,
  "uuid": "7763A937-B779-4D31-A20C-49E83047048F",
  "count": 1,
  "beacons": [
    {
      "proximityUUID": "7763A937-B779-4D31-A20C-49E83047048F",
      "major": 1,
      "minor": 7,
      "proximity": "near",
      "accuracy": 0.42,
      "rssi": -61
    }
  ]
}
```

Stop ranging with `beaconsStop`.

## iBeacon advertising

`beaconAdvertiseStart` makes the device transmit as an iBeacon while the native
app is running. The web app can pass a Proximity UUID plus `major` and `minor`.
If `uuid` is omitted, native code uses the configured `beacon_uuid` setting.
`major` and `minor` default to `1` and must be in the iBeacon range `0...65535`.

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'beaconAdvertiseStart',
  uuid: '7763A937-B779-4D31-A20C-49E83047048F',
  major: 3,
  minor: 17
});
```

Typical response:

```json
{
  "platform": "ios",
  "action": "beaconAdvertiseStart",
  "success": true,
  "provider": "ios_corebluetooth",
  "state": "starting",
  "uuid": "7763A937-B779-4D31-A20C-49E83047048F",
  "major": 3,
  "minor": 17
}
```

The native advertiser also sends a follow-up result with the same action when
the platform confirms `state: "advertising"` or reports an advertising error.
Stop transmitting with:

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'beaconAdvertiseStop'
});
```

iOS uses CoreBluetooth and can advertise while the app is foregrounded. Android
uses the AltBeacon transmitter and requires BLE advertising support on the
device plus `BLUETOOTH_ADVERTISE` permission on Android 12+.

## Device, runtime, and diagnostics

`deviceInfoGet` returns best-effort device metadata: OS/version, app version,
screen size, battery/power state, memory, cameras, sensors, network/IP data,
and capability flags. Platform privacy rules apply. iOS does not expose a
serial number to normal apps. Android returns `unavailable` when serial access
is blocked by the OS.

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'deviceInfoGet',
  requestId: crypto.randomUUID()
});
```

`screenOrientationSet` accepts `unlocked`, `portrait`, `landscape`, or `locked`.
`locked` keeps the current orientation when the platform supports it.

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'screenOrientationSet',
  mode: 'landscape'
});
```

`screenshotGet` captures the app/WebView surface and returns a JPEG data URL.
It is not a system-wide screenshot.

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'screenshotGet',
  maxWidth: 720,
  quality: 75
});
```

`soundPlay` emits a short tone on the normal media output/speaker path:

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'soundPlay',
  frequencyHz: 880,
  durationMs: 260,
  volume: 0.85
});
```

## Wi-Fi setup

`wifiStatusGet` returns best-effort current network details. iOS and Android
return the same core fields when the OS exposes them: `ssidAvailable`, `ssid`,
`bssid`, `securityType`, `securityTypeRawValue`, all detected `ipAddresses`,
and `wifiIpAddresses` for the Wi-Fi interface. SSID visibility is restricted by
platform privacy rules and may be `unavailable`; in that case the response also
contains `ssidAvailable: false` and `unavailableReason`.

`wifiConfigure` asks the OS to add/join a known Wi-Fi network. It is not a
silent system-wide switch:

- iOS uses `NEHotspotConfigurationManager` and requires the Hotspot
  Configuration capability plus user approval. `wifiStatusGet` can expose the
  current SSID only when the App ID/profile also includes Access WiFi
  Information. Without the Hotspot Configuration entitlement, iOS can return an
  `internal error.`; the bridge includes native error domain/code and a
  `capabilityRequired` hint in the response.
- Android uses the Android 11+ add-network system dialog when available,
  `WifiNetworkSuggestion` on Android 10, and the legacy configuration path on
  older devices. Android also needs location permission before it exposes
  SSID/BSSID details through `wifiStatusGet`; the bridge requests it on demand.

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'wifiConfigure',
  ssid: 'Standort-WLAN',
  passphrase: 'long-password',
  joinOnce: false
});
```

The bundled demo page exposes this as SSID/password inputs plus a
`Mit WLAN verbinden` button. Leave the password empty for open test networks.

## Location, idle, sensors

`geoLocationGet` returns a one-shot location after platform permission. Start
continuous events with `geoLocationStart`; events use action `geoLocation`.

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'geoLocationStart',
  intervalMs: 3000,
  minDistanceMeters: 0
});
```

The idle timer is native-counted and reset by WebView touch/key/scroll activity.
It emits `idleTick` and one `idleTimeout` event after the configured timeout.

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'idleTimerStart',
  timeoutSeconds: 30,
  intervalSeconds: 1
});
```

Sensor streaming returns platform sensor snapshots/events through `sensorData`.
Use `sensorCapabilitiesGet` first when the web app needs a device-specific UI.

## Screen stream

`screenStreamStart` starts native app-surface capture and streams JPEG frames to
a target WebSocket URL. Frames do not pass through the JavaScript bridge. The
bridge only controls start/stop and receives status/stats events.

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'screenStreamStart',
  transport: 'websocket',
  targetUrl: 'ws://<viewer-host>:18090/screen',
  format: 'jpeg',
  fps: 2,
  maxWidth: 720,
  quality: 65
});
```

The included viewer shows stream size and latest frame:

```sh
cd tools/screenstreamviewer
go run . -addr :18090
```

This first implementation is intentionally an app-screen diagnostic stream. A
future full device-screen stream should use ReplayKit/Broadcast Extension on iOS
and MediaProjection plus a foreground service on Android.

## Printer discovery

`printerDiscover` scans either explicit `hosts`/`cidrs` from the request or,
when none are provided, the local IPv4 `/24` networks reported by the device.
The shared Go core detects Epson ePOS-Print XML endpoints and probable raw
ESC/POS TCP printers. Android adds a local `sunmi_internal` target when the
Sunmi printer AIDL service is available.

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'printerDiscover',
  requestId: crypto.randomUUID(),
  timeoutMs: 700,
  httpTimeoutMs: 1000,
  concurrency: 96,
  scanEpson: true,
  scanEscpos: true
});
```

Typical response:

```json
{
  "platform": "android",
  "action": "printerDiscover",
  "success": true,
  "goCoreVersion": "0.1.0",
  "cidrs": ["192.0.2.0/24"],
  "scans": ["epson_epos_xml", "escpos_raw"],
  "printers": [
    {
      "id": "epson_epos_xml-192.0.2.10-80",
      "kind": "epson_epos_xml",
      "label": "Epson ePOS-Print",
      "host": "192.0.2.10",
      "port": 80,
      "confidence": "confirmed"
    },
    {
      "id": "escpos_raw-192.0.2.10-9100",
      "kind": "escpos_raw",
      "label": "ESC/POS Raw TCP",
      "host": "192.0.2.10",
      "port": 9100,
      "confidence": "probable"
    }
  ]
}
```

## Printer smoke test

`printerHelloWorld` sends one small smoke-test job to the selected printer. Epson
ePOS-Print targets go through the shared Go `printercore` package. Android/Sunmi
targets go through the Sunmi AIDL service. Raw ESC/POS printing is discovered but
not printed by this demo action yet.

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'printerHelloWorld',
  requestId: crypto.randomUUID(),
  printer: {
    id: 'sunmi-internal',
    kind: 'sunmi_internal',
    label: 'Sunmi interner Drucker',
    local: true
  },
  kind: 'sunmi_internal',
  title: 'Hallo Welt',
  subtitle: 'swiftHTMLWebviewApp',
  body: 'Bridge test'
});
```

`printerEpsonHelloWorld` remains supported as the legacy Epson-only action.

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'printerEpsonHelloWorld',
  requestId: crypto.randomUUID(),
  host: '192.0.2.10',
  devid: 'local_printer',
  timeoutMs: 20000,
  title: 'Hallo Welt',
  subtitle: 'swiftHTMLWebviewApp',
  body: 'Bridge test'
});
```

Typical success response:

```json
{
  "platform": "ios",
  "action": "printerEpsonHelloWorld",
  "success": true,
  "host": "192.0.2.10",
  "devid": "local_printer",
  "goCoreVersion": "0.1.0",
  "status": "251658262"
}
```

Regenerate the mobile bindings after changing `printercore`:

```sh
printercore/scripts/build_mobile.sh
```

Platform implementations should keep this web-facing API stable even when native code differs between iOS and Android.
