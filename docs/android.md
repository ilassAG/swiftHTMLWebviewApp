# Android

The Android app lives in `android/`.

## Current implementation

Implemented:

- Android Gradle project with wrapper scripts.
- Native Java `Activity` hosting an Android `WebView`.
- Local iOS-parity demo page at `app/src/main/assets/index.html`.
- iOS-compatible JavaScript shim for:
  `window.webkit.messageHandlers.swiftBridge.postMessage(...)`.
- Structured responses into `window.handleNativeResult(...)`.
- Start URL override through an Android launch intent data URL.
- Native Android confetti overlay for `launchConfetti`.
- Android camera photo capture for `takePhoto`.
- Google Code Scanner UI for `scanBarcode`.
- Android NFC reader-mode bridge for `nfcTagRead` with tag metadata and NDEF
  record decoding when the device has NFC hardware.
- CameraX + ML Kit embedded continuous scanner for `continuousScanStart`,
  `dataScanStart`, `loginScanStart`, and preview updates.
- AltBeacon iBeacon ranging for `beaconsStart` / `beaconsStop`.
- AltBeacon iBeacon advertising for `beaconAdvertiseStart` /
  `beaconAdvertiseStop` when the device supports BLE advertising.
- Google ML Kit Document Scanner UI for `scanDocument`, returning JPEG image data URLs or PDF data URLs.
- Go `printercore` AAR bridge for `printerDiscover`, `printerHelloWorld`, and
  `printerEpsonHelloWorld`.
- Sunmi internal-printer discovery and Hello World printing when
  `woyou.aidlservice.jiuiv5` is visible.
- Android supplies the active IPv4 `/24` network as a discovery hint before
  calling the Go core, because Go's interface enumeration can be blocked by
  Android netlink restrictions in app sandboxes.
- Device diagnostics through `deviceInfoGet`, app screenshot capture,
  orientation lock, sound output, idle timer, location, sensor streaming,
  Wi-Fi status/setup, and app-screen JPEG streaming over WebSocket.
- Local notifications through Android `NotificationManager`, high-importance
  default notification channel creation, Android 13+ `POST_NOTIFICATIONS`
  permission, and `AlarmManager` time-based scheduling. Android 12 and older do
  not show a runtime notification prompt and are reported as authorized.
- Native SharedPreferences-backed startup URL settings with Kassa-compatible
  failover fields (`server_url_preference`, `ha_enabled`, `ha_timeout`,
  `ha_url2`, `ha_url3`, `ha_url4`), `beacon_uuid`, and deployment identity
  fields (`device_name`, `device_uuid`, `device_location`). `device_uuid` is
  generated on first start if it is empty.
- BLE config pairing as target and config device through `configPairingShow`,
  `configPairingConnect`, and `configPairingSend`.
- `wifiStatusGet` mirrors the iOS response shape for `ssidAvailable`, `ssid`,
  `bssid`, `securityType`, `securityTypeRawValue`, `ipAddresses`, and
  `wifiIpAddresses`. Android requires location permission before SSID/BSSID
  details are exposed, so the bridge requests it when the web app asks for Wi-Fi
  status.

Not implemented yet:

- Android Stripe Terminal / Tap to Pay.
- iOS-style background removal options for `takePhoto`.
- OCR text extraction for document scans.
- Full system-screen streaming through MediaProjection/foreground service. The
  current `screenStreamStart` bridge streams the app surface only.

## Build

The Go mobile binding is optional. A clean checkout builds without
`android/app/libs/printercore.aar`; Epson printer discovery/printing then
returns a structured unavailable response while Sunmi internal printing can
still work on Sunmi devices. Generate the binding when enabling the shared Go
printer core:

```sh
printercore/scripts/build_mobile.sh
```

```sh
cd android
./gradlew assembleDebug
```

On machines where Java 11 is the default, use a JDK 17+ for the build:

```sh
JAVA_HOME=/path/to/jdk17 ANDROID_HOME=$HOME/Library/Android/sdk ./gradlew assembleDebug
```

## Install and launch on USB device

```sh
cd android
ANDROID_HOME=$HOME/Library/Android/sdk ./gradlew installDebug
adb shell am start -n com.ilass.swifthtmlwebviewapp/.MainActivity
```

If the device shows as `unauthorized`, unlock it and approve the USB debugging prompt.

The local demo page contains a printer-search button plus a Hello World print
button. Search calls `printerDiscover`; the print button calls
`printerHelloWorld` and routes by the selected printer kind. Epson targets use
the Go ePOS path, while Sunmi internal targets use the Sunmi AIDL service.

The demo page also contains a `Config Pairing` panel. On Android 12+ the app
requests `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, and
`BLUETOOTH_ADVERTISE` as needed. The target pairing UI can also be opened with
a two-finger long press in the center of the WebView for about 1.5 seconds.
The pairing QR includes `deviceName`, `deviceUUID`, and `deviceLocation` from
the target settings so the config device can identify the target before sending
commands. It does not include the persistent security token. Large config
commands and responses are transported as BLE chunks and reassembled natively.
Writable config commands require the current stored security token. WLAN setup
uses Android's user-approved add-network/suggestion APIs, so it cannot silently
change the system Wi-Fi on modern Android.

Android does not have an iOS Settings.bundle equivalent for arbitrary app
settings in the system Settings app. The wrapper stores startup URL and related
values in app-private SharedPreferences; expose editable controls in the app,
use Config Pairing, or use Android Enterprise managed configurations for MDM
fleets.

## Bridge behavior

Android must keep the same public action names as iOS. Unsupported features should return a structured error or availability payload.

Example unsupported Tap to Pay availability response:

```json
{
  "platform": "android",
  "action": "tapToPayAvailability",
  "requestId": "...",
  "available": false,
  "readerType": "android",
  "reason": "Android Tap to Pay bridge is not implemented in this wrapper build yet."
}
```
