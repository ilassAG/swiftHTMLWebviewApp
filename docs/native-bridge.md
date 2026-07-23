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

The machine-readable registry in `docs/bridge-contract.json` assigns each
public action a `responseProfile`. Profiles describe broad delivery semantics
such as one-shot callback responses, command acknowledgements, stream control
with follow-up events, Tap to Pay flows, and printer jobs. The profiles are
intentionally compatible with current legacy responses; `platform`, `requestId`,
and `success` remain recommended fields until all older bridge paths are fully
normalized. Actions that can produce asynchronous follow-up messages also list
their concrete `emits` event actions. Those events are cataloged separately from
public commands so wrapper variants can expose streams and sessions without
guessing their callback names.

Known legacy response omissions are recorded under
`legacyCompatibility.actions` in the machine-readable contract. Current iOS
`scanDocument`, `takePhoto`, and one-shot `scanBarcode` success payloads keep
their existing field shape for compatibility with deployed web apps; new bridge
code should use the common `platform` / `requestId` / `success` envelope unless
an exception is explicitly recorded there.

Profile-level success/error examples live in
`docs/bridge-response-fixtures.json`. `tools/validate_contracts.js` validates
those fixtures against every public action so response-shape changes are caught
before platform builds.

## Built-in actions

- `scanDocument`
- `takePhoto`
- `portraitCapture`
- `scanBarcode`
- `nfcTagRead`
- `continuousScanStart` / `continuousScanStop`
- `dataScanStart` / `dataScanEnd` (legacy-compatible continuous scanner aliases)
- `loginScanStart` / `loginScanEnd` (legacy-compatible continuous scanner aliases)
- `previewBoxLocationUpdate`
- `beaconsStart` / `beaconsStop`
- `beaconAdvertiseStart` / `beaconAdvertiseStop`
- `deviceInfoGet`
- `settingsGet` / `settingsSet`
- `storageGet` / `storageSet` / `storageRemove` / `storageClear`
- `filesystemWrite` / `filesystemRead` / `filesystemList` / `filesystemDelete`
- `sqliteExecute` / `sqliteDeleteDatabase`
- `kioskReloadControlSet`
- `screenOrientationGet` / `screenOrientationSet`
- `wifiStatusGet` / `wifiConfigure`
- `screenshotGet`
- `geoLocationGet` / `geoLocationStart` / `geoLocationStop`
- `arPositionStart` / `arPositionStop` (iOS ARKit local position stream)
- `arOverlayOpen` / `arOverlayClose` (iOS ARKit generic 3D overlay; `arReplayOpen` is a compatibility alias)
- `arGuidedMeasurementStart` / `arGuidedMeasurementSetAnchors` / `arGuidedMeasurementUpdateStats` / `arGuidedMeasurementStop` (iOS ARKit guided start-arrow measurement)
- `roomPlanScanStart` / `roomPlanScanStop` / `roomPlanScanExport` (iOS RoomPlan/LiDAR room scan)
- `soundPlay`
- `notificationPermissionGet` / `notificationPermissionRequest`
- `notificationShow` / `notificationSchedule`
- `notificationCancel` / `notificationCancelAll` / `notificationList`
- `idleTimerStart` / `idleTimerReset` / `idleTimerStop`
- `sensorCapabilitiesGet` / `sensorStreamStart` / `sensorStreamStop`
- `screenStreamStart` / `screenStreamStop`
- `natsProvision` / `natsStatus` / `natsConnect` / `natsDisconnect` /
  `natsPublish`
- `configPairingShow` / `configPairingStop`
- `configPairingConnect` / `configPairingDisconnect`
- `configPairingSend`
- `configDeviceScanStart` / `configDeviceScanStop`
- `configDeviceConnect` / `configDeviceDisconnect`
- `configDeviceSend`
- `reload`
- `launchConfetti`
- `tapToPayAvailability` (optional Stripe module)
- `tapToPayCollect` (optional Stripe module)
- `printerDiscover` (optional Go printer core)
- `printerHelloWorld` (selected-printer smoke test)
- `printerPrint` (Android/Sunmi generic QR/text print payload)
- `printerEpsonHelloWorld` (optional Go printer core)

## NATS remote management

`natsProvision` stores non-secret NATS settings and saves secret material only
in native secret storage: Keychain on iOS, Android Keystore-backed encrypted
storage on Android. `natsStatus`, `natsConnect`, `natsDisconnect`, and
`natsPublish` expose the local control plane to web content without returning
credentials. When NATS is enabled and credentials are present, the wrapper
auto-connects on app launch/resume and publishes best-effort telemetry to
`swift.wrapper.<appUUID>.telemetry.status`.

After a successful native connection the wrapper subscribes to:

```text
swift.wrapper.<appUUID>.commands.*
```

The first supported remote command set is deliberately small and scoped:
`status`/`deviceInfoGet`, `settings`/`settingsGet`, `settingsSet`,
`screenshot`/`screenshotGet`, `qrScan`/`qrScanImage`, `qrScanJob`,
`screenStreamStart`, `screenStreamStop`, `reload`, and `natsStatus`. Command
responses are published to the NATS message reply subject, an explicit JSON
`replyTo`, or the configured default response subject
`swift.wrapper.<appUUID>.events.responses`.

`qrScanImage` accepts an image as `imageBase64`, `imageData`, `dataURL`, or
`image` and replies with the first decoded QR value as `code` plus a `codes`
array. Job metadata fields such as `jobId`, `scanJobId`, `taskId`, and
`distributionId` are echoed and the reply includes `workerAppUUID`. The image
payload is not persisted or returned.

`screenStreamStart` over NATS publishes JPEG frame bytes to
`swift.wrapper.<appUUID>.screen.frames` by default, JSON metadata to
`.screen.meta`, and stream events/stats to `.screen.events`. WebSocket streaming
remains available for local tools. `source: "app"` captures the wrapper
app/WebView surface. `source: "device"` is reserved for future ReplayKit /
MediaProjection support and returns a structured unavailable response in this
generic build.

## ARKit guided measurement

iOS can show a native AR scene with a tappable 3D start arrow before a web
measurement begins:

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'arGuidedMeasurementStart',
  sessionId: 'sess_...',
  floorPlanId: 'floor_...',
  startAnchor: { id: 'anchor_...', kind: 'start', planX: 1.2, planY: 0.8, yawRadians: 0 },
  anchors: [],
  worldMapUrl: 'http://host/api/floor-plans/floor_.../world-map',
  worldMapFormat: 'arkit-arworldmap-keyedarchive-v1',
  intervalMs: 500
});
```

Native events are delivered through `window.handleNativeResult(result)`.
Important event actions are `arGuidedReady`, `arGuidedPosition`,
`arGuidedRelocalizing`, `arGuidedRelocalized`,
`arGuidedStartAnchorConfirmed`, `arGuidedAnchorCaptured`, and
`arGuidedError`. When `worldMapUrl` or `worldMapBase64` is supplied, iOS starts
world tracking with `initialWorldMap` and does not place the start arrow until
ARKit has relocalized to the saved physical space. Positions use ARKit
gravity-aligned local meters with
`position.x/y/z` and `orientation.pitch/yaw/roll`.

## ARKit generic overlay

iOS can show a generic product-defined 3D overlay in ARKit. The wrapper only
renders neutral scene primitives; the web app owns domain semantics such as
measurement points, inspection markers, work orders, assets, or navigation
targets.

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'arOverlayOpen',
  requestId: crypto.randomUUID(),
  title: 'Room inspection',
  worldMapUrl: 'http://host/api/spaces/space_123/world-map',
  worldMapFormat: 'arkit-arworldmap-keyedarchive-v1',
  coordinateSystem: 'arkit-gravity-local',
  items: [
    {
      id: 'marker_1',
      kind: 'point',
      title: 'Marker 1',
      detail: 'Optional product-defined detail text',
      position: { x: 1.2, y: 0.1, z: -0.4 },
      color: 'green',
      radius: 0.06,
      payload: { domainId: 'abc' }
    }
  ],
  lines: [
    {
      id: 'path_1',
      color: 'blue',
      points: [
        { x: 1.2, y: 0.06, z: -0.4 },
        { x: 1.6, y: 0.06, z: -0.8 }
      ]
    }
  ]
});
```

When `worldMapUrl` or `worldMapBase64` is supplied, iOS starts world tracking
with `initialWorldMap` and renders the overlay only after ARKit relocalizes to
the saved physical space. Supported item colors include `green`, `yellow`,
`orange`, `red`, `violet`, `cyan`, `blue`, `gray`, and CSS-style `#RRGGBB`.
Tapping a rendered item emits `arOverlayItemSelected` with the item's id,
position, detail, and original `payload`.

For geographic asset finders, use `coordinateSystem: 'wgs84'`, provide the
device location as `origin`, and put a `geoPosition` on each item. iOS aligns
the AR world to gravity and magnetic heading. Targets farther away than
`maxDisplayDistanceMeters` are rendered as direction markers at that radius
while their label and selection event keep the real geographic distance.

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'arOverlayOpen',
  requestId: crypto.randomUUID(),
  title: 'Asset finder',
  coordinateSystem: 'wgs84',
  maxDisplayDistanceMeters: 15,
  origin: {
    latitude: 48.13155,
    longitude: 11.54965,
    altitudeMeters: 520
  },
  items: [
    {
      id: 'asset-1',
      kind: 'asset',
      title: 'Asset 1',
      geoPosition: {
        latitude: 48.13155,
        longitude: 11.55005,
        altitudeMeters: 520
      },
      color: 'blue',
      payload: { domainId: 'asset-1' }
    }
  ]
});
```

`arReplayOpen` and `arReplayClose` are compatibility aliases for existing web
apps. New integrations should prefer `arOverlayOpen` and pass generic `items`
and `lines`. For legacy overlay payloads, iOS also accepts an `overlay`
object with `tracePoints`, `txPoints`, `speedPoints`, and `floorPlan.planJson`
and maps those to generic lines and markers.

## Native runtime configuration

Startup URL and iBeacon region settings are native app configuration, not bridge
actions. On iOS the editable values live in Settings.bundle:

- `server_url_preference`: primary web app URL, or `local` for bundled HTML.
- `ha_enabled`: enables legacy-compatible URL failover.
- `ha_timeout`: seconds to wait before trying the next configured URL.
- `ha_url2`, `ha_url3`, `ha_url4`: fallback URLs.
- `beacon_uuid`: iBeacon Proximity UUID used by the continuous beacon bridge
  when that native module is enabled.
- `appUUID`: read-only native app installation UUID. Native code generates one
  on first start and ignores attempts to set it through config QR,
  `settingsSet`, or pairing commands.
- `device_name`: deployment-specific display name for this wrapper install.
- `device_uuid`: persistent per-install identifier. Native code generates one
  on first start if the value is empty. Unlike `appUUID`, this remains writable
  for product/station/terminal identity.
- `device_location`: deployment-specific physical/logical location label.
- `appConfig`: a persistent app-private JSON object for non-sensitive product or
  deployment values such as site keys, terminal identifiers, tenant labels, or
  feature flags. It is returned by `settingsGet` and merged by `settingsSet`.

Web apps should not hard-code these values. They should treat the native wrapper
as the owner of startup URL selection and beacon-region selection.

## App-private persistence

The wrapper exposes three persistence layers for web apps that need reliable
offline behavior beyond normal browser storage:

- Use `storageGet`, `storageSet`, `storageRemove`, and `storageClear` for small
  native preferences or deployment values. Values are stored app-privately in a
  namespaced key/value store. This is the general-purpose replacement for
  product-specific `appConfig` fields.
- Use `filesystemWrite`, `filesystemRead`, `filesystemList`, and
  `filesystemDelete` for app-private JSON, text, or binary files. The
  `directory` field can be `data`, `cache`, or `temporary`; paths are always
  resolved below the wrapper-owned app-private directory.
- Use `sqliteExecute` and `sqliteDeleteDatabase` for structured offline data,
  local queues, and transaction logs. SQL statements accept positional `args`
  and return `rows`, `changes`, and `lastInsertRowId`.

Recommended storage split:

- Small configuration and per-device preferences: native storage bridge.
- Web-owned cache and UI state: IndexedDB when a browser-native database is
  sufficient.
- Transactional offline domain data, sync queues, or cash-register state:
  SQLite bridge.
- Photos, exports, import payloads, and larger JSON/binary documents:
  filesystem bridge.

Examples:

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'storageSet',
  namespace: 'terminal',
  key: 'siteKey',
  value: 'demo-site'
});

window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'filesystemWrite',
  directory: 'data',
  path: 'sync/outbox.json',
  data: JSON.stringify({ pending: [] }),
  encoding: 'utf8'
});

window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'sqliteExecute',
  database: 'offline.sqlite',
  sql: 'INSERT INTO events (id, payload) VALUES (?, ?)',
  args: ['evt_1', JSON.stringify({ total: 12.5 })]
});
```

## Kiosk reload control

`kioskReloadControlSet` shows or hides a small native reload button centered on
the left edge of the screen. It is disabled by default. A tap reloads the
current WebView. A long press terminates the app process so kiosk launchers or
MDM policies can restart it.

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'kioskReloadControlSet',
  enabled: true,
  opacity: 0.1,
  longPressSeconds: 2
});
```

On Android these values are stored in app-private SharedPreferences. Android
does not provide an iOS Settings.bundle equivalent where arbitrary app settings
automatically appear inside the system Settings app. Change them through the
local JS bridge, the bundled demo/settings UI, BLE Config Pairing, or through
Android Enterprise/MDM managed configurations when the device fleet is managed.

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
payload contains a short-lived session id, BLE service UUID, random session
secret, and the target identity fields `appUUID`, `deviceName`, `deviceUUID`,
and `deviceLocation` so the config device can show which wrapper it is about to
configure. It does not contain the persistent `security_token_preference`.
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
    deviceName: 'Demo Tablet 03',
    deviceLocation: 'Hall A / Entrance'
  }
});
```

Large commands and large target responses are split into `configPairingChunk`
BLE messages by native code and reassembled by the receiving side before the web
app receives the final `configPairingResponse`.

## Persistent ESP device configuration

iOS can also discover and select permanently advertising ESP devices. This mode
uses the dedicated service UUID `6D8E0F22-9C2D-4E8E-A7D7-2B1D49F48B01` so an
ESP cannot be mistaken for a short-lived wrapper QR-pairing target. Command and
response characteristics, chunk envelopes, and response delivery remain shared
with Config Pairing.

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'configDeviceScanStart'
});

// Choose scanId from a configDeviceEvent/discovered event.
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'configDeviceConnect',
  scanId: 'CORE-BLUETOOTH-PERIPHERAL-UUID'
});

window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'configDeviceSend',
  command: 'wifiConfigure',
  token: 'optional-current-device-token',
  ssid: 'Workshop',
  passphrase: 'secret',
  persist: true
});
```

Discovery emits `configDeviceEvent` values with `event: "discovered"`, a native
`scanId`, name, and RSSI. Connection emits `connected`, then `ready` after the
response notification subscription is active. ESP responses use
`configPairingResponse` with `role: "persistentDevice"` and are forwarded to
`window.handleNativeResult`.

Supported ESP commands are device-defined. The reference ESP implementation
supports `statusGet`, `settingsGet`, `settingsSet`, `identify`,
`wifiConfigure`, `factoryResetWifi`, and `reload`. Android currently returns a
structured unavailable response for the five `configDevice*` actions.

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
settings, configure target WLAN, and reload the target. When a pairing QR is
scanned or pasted, the demo copies `appUUID`, `deviceName`, `deviceUUID`, and
`deviceLocation` from the QR into the config fields before connecting.

The same settings are available locally through direct JS bridge actions:

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'settingsGet'
});

window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'settingsSet',
  token: 'current-security-token',
  settings: {
    deviceName: 'Demo Tablet 03',
    deviceUUID: '4EF955C4-DC2B-4328-9B4D-1D0341B9DF90',
    deviceLocation: 'Hall A / Entrance'
  }
});
```

`settingsGet` returns non-sensitive values plus `securityTokenSet`.
`settingsSet` requires the current security token. If `deviceUUID` is omitted,
the existing UUID is kept. If it is explicitly set to an empty string, native
code generates and stores a new UUID. `settings.appConfig` or `settings.store`
is merged into the persistent `appConfig` object instead of replacing the whole
object. `appUUID` is read-only and is ignored by `settingsSet` and config QR
payloads.

The same configuration can be provisioned by scanning a QR code. JSON payloads
use the same key names as `settingsSet`; `wifi` optionally triggers
`wifiConfigure` after settings are stored:

```json
{
  "toolmode": "changeConfig",
  "securityToken": "current-security-token",
  "defaultServerUrl": "https://example.invalid/app/",
  "appConfig": {
    "siteKey": "Demo Site",
    "terminalId": "A1"
  },
  "wifi": {
    "ssid": "Demo WLAN",
    "pw": "demo-password"
  }
}
```

For smaller QR codes, use query parameters. Known top-level setting names update
native settings, `store[key]` and `appConfig[key]` merge into `appConfig`, and
`wifi[ssid]` plus `wifi[pw]` / `wifi[password]` / `wifi[passphrase]` trigger
Wi-Fi configuration:

```text
swifthtml-config://set?token=current-security-token&serverURL=https%3A%2F%2Fexample.invalid%2Fapp%2F&store%5BsiteKey%5D=Demo%20Site&wifi%5Bssid%5D=Demo%20WLAN&wifi%5Bpw%5D=demo-password
```

Config QR writes and QR-triggered Wi-Fi setup require `token` or
`securityToken`. Plain recovery QR codes that only carry a server URL keep their
existing recovery behavior.

The same QR payloads can be consumed through the continuous scanner by starting
it with `purpose: 'configPairing'`. In that mode iOS and Android default to the
front camera, restrict scanning to QR codes unless `types` is explicitly set,
show a native camera-flip icon below the preview, and apply the first valid
config QR natively before reloading the configured URL:

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'continuousScanStart',
  purpose: 'configPairing',
  camera: 'front',
  types: ['qr'],
  showFlipButton: true,
  previewRect: { top: 0.18, left: 0.1, width: 0.8, height: 0.36 }
});
```

## Portrait capture

`portraitCapture` opens a native pass-photo controller on iOS and Android. The
front-camera preview is mirrored for familiar selfie framing, but the returned
image is not mirrored by default so text remains readable like in the system
camera app.

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'portraitCapture',
  camera: 'front',
  requiredFaces: 1,
  countdownSeconds: 3,
  variationCount: 4,
  captureIntervalMs: 200,
  removeBackground: true,
  background: 'transparent',
  crop: 'squareFaceCentered',
  mirrorOutput: false
});
```

Supported request fields:

- `camera`: `front` or `back`, default `front`.
- `requiredFaces` or legacy `amountFaces`: integer `1...8`, default `1`.
- `countdownSeconds` or legacy `secondsDelay`: seconds `0...15`, default `3`.
- `variationCount` or legacy `withVariation`: integer `1...8`, default `4`.
- `captureIntervalMs`, `burstIntervalMs`, or `variationIntervalMs`:
  milliseconds `50...2000`, default `200`.
- `removeBackground`: boolean/string boolean, default `false`.
- `outputType`: `png` or `jpeg`; transparent background removal returns PNG.
- `background`: `transparent` or `color`.
- `backgroundColor`: `#RRGGBB`, default `#FFFFFF`.
- `cropTransparent`: boolean/string boolean, default `false`.
- `crop`: `squareFaceCentered` or `none`, default `squareFaceCentered`.
- `mirrorOutput` or legacy-short `mirror`: boolean/string boolean, default
  `false`. Set `true` only when the web app explicitly wants a mirror-style
  selfie result.

## Continuous scanner

iOS exposes an embedded long-running scanner with camera selection and a
relative preview rectangle. The legacy-compatible `dataScanStart` and
`loginScanStart` aliases are supported by the same implementation.
Config-pairing flows use the same scanner with `purpose: 'configPairing'`.

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'dataScanStart',
  camera: 'back',
  mode: 'data',
  repeatDelaySeconds: 1.2,
  showCloseButton: true,
  types: ['qr', 'ean13', 'ean8', 'code128', 'datamatrix'],
  previewRect: { top: 0.18, left: 0.1, width: 0.8, height: 0.36 }
});
```

The preview rectangle accepts relative values from `0` to `1`. Percent-like
values from `0` to `100` are also accepted by the native iOS bridge.
`showCloseButton` controls whether the scanner can be stopped from its native
overlay and defaults to `true`; the legacy alias `closeButton` is also accepted.

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

## Local notifications

Local notifications are part of the default wrapper on iOS and Android. Remote
push notifications are intentionally not part of the core bridge; add them as an
optional module when APNs/FCM infrastructure is available.

Android 13 and newer require the runtime `POST_NOTIFICATIONS` permission. On
Android 12 and older, `notificationPermissionRequest` resolves as authorized
without showing a system prompt because notifications do not use a runtime
permission there. Android uses a high-importance default channel
(`swift_html_alerts`) so immediate demo notifications can appear as visible
alerts instead of only as notification-shade entries. If a web app passes its
own `channelId`, Android keeps that channel's existing system importance.

Request or inspect permission first:

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'notificationPermissionRequest'
});
```

Show an immediate local notification:

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'notificationShow',
  id: 'print-job-123',
  title: 'Druckjob fertig',
  body: 'Der Bon wurde gedruckt.',
  sound: true,
  data: { jobId: '123' }
});
```

Schedule one for later:

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'notificationSchedule',
  id: 'idle-warning',
  title: 'Sitzung laeuft ab',
  body: 'Seit 30 Sekunden keine Aktivitaet.',
  seconds: 10,
  data: { reason: 'idle' }
});
```

Cancel by `id`, cancel all, or list pending requests with `notificationCancel`,
`notificationCancelAll`, and `notificationList`. When the user opens a local
notification, native code emits a `notificationOpened` event through
`window.handleNativeResult(...)`. iOS can also emit `notificationReceived` while
the app is in the foreground.

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

On ARKit-capable iOS devices, `arPositionStart` starts a local world-tracking
stream. Events use action `arPosition` and include `position.x/y/z` in meters,
Euler `orientation`, `trackingState`, and `coordinateSystem:
arkit-gravity-local`. This is a local odometry stream, not GPS and not a room
plan.

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'arPositionStart',
  intervalMs: 500
});
```

## RoomPlan scan

On RoomPlan-capable iOS devices, `roomPlanScanStart` presents Apple's native
RoomPlan/LiDAR scanner. When the user finishes the scan, native code emits
`roomPlanScanResult` with a normalized 2D meter model plus a preview SVG.

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'roomPlanScanStart',
  requestId: crypto.randomUUID()
});
```

Result shape:

```json
{
  "action": "roomPlanScanResult",
  "success": true,
  "source": "roomplan",
  "coordinateSystem": "roomplan-local-meter",
  "normalizedPlan": {
    "bounds": {"minX": 0, "minY": 0, "maxX": 5, "maxY": 3},
    "walls": [],
    "openings": [],
    "objects": []
  },
  "previewSvg": "<svg ...></svg>",
  "worldMapAvailable": true,
  "worldMapFormat": "arkit-arworldmap-keyedarchive-v1",
  "worldMapBase64": "...",
  "worldMapByteCount": 123456,
  "raw": {}
}
```

Unsupported devices return `success:false`, `supported:false`, and `error`.
Android exposes the same action names with a structured unavailable response.

## Screen stream

`screenStreamStart` starts native app-surface capture and streams JPEG frames to
a target WebSocket URL or to NATS. Frames do not pass through the JavaScript
bridge. The bridge only controls start/stop and receives status/stats events.

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'screenStreamStart',
  source: 'app',
  transport: 'websocket',
  targetUrl: 'ws://<viewer-host>:18090/screen',
  format: 'jpeg',
  fps: 2,
  maxWidth: 720,
  quality: 65
});
```

NATS transport uses device-scoped subjects:

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'screenStreamStart',
  source: 'app',
  transport: 'nats',
  subject: 'swift.wrapper.<appUUID>.screen.frames',
  metaSubject: 'swift.wrapper.<appUUID>.screen.meta',
  eventSubject: 'swift.wrapper.<appUUID>.screen.events',
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

`printerPrint` is currently an Android/Sunmi-specific generic print action for
simple text/QR payloads. iOS returns a structured unavailable response for this
action; use `printerHelloWorld` or `printerEpsonHelloWorld` for cross-platform
smoke tests.

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
