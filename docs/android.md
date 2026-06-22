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
  `printerEpsonHelloWorld`, plus Android/Sunmi `printerPrint` for generic
  text/QR payloads.
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
- Native SharedPreferences-backed startup URL settings with legacy-compatible
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

- ARKit-based `arOverlayOpen` / `arOverlayClose` and `arReplayOpen` / `arReplayClose` overlays. Android returns a structured unavailable response for those iOS-only actions.
- Background removal for `takePhoto` is available as an Android experimental
  ML Kit Selfie Segmentation path and should be treated as optional until a
  private variant validates it on target hardware.
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
adb shell am start -n com.ilass.swifthtmlwebviewapp/com.ilass.swifthtmlwebviewapp.MainActivity
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

The same SharedPreferences-backed runtime settings can be updated by Config QR
codes. JSON payloads accept `appConfig` or `store` objects; URL/query payloads
accept `store[key]=value` / `appConfig[key]=value` and `wifi[ssid]` plus
`wifi[pw]` / `wifi[password]` / `wifi[passphrase]`. `appConfig` is stored as a
persistent non-sensitive JSON object and returned by `settingsGet`.

The first-run defaults for `server_url_preference`,
`security_token_preference`, and `beacon_uuid` are variant metadata on the
Android `<application>` element:

```xml
<meta-data
    android:name="com.ilass.DEFAULT_SERVER_URL"
    android:value="https://example.invalid/mobile/" />
```

Use the same pattern for `com.ilass.DEFAULT_SECURITY_TOKEN` and
`com.ilass.DEFAULT_BEACON_UUID` when a variant needs app-specific defaults.
Recovery-page branding and copy can also be variant metadata:
`com.ilass.RECOVERY_SHORT_MARK`, `com.ilass.RECOVERY_TITLE`,
`com.ilass.RECOVERY_BODY`, `com.ilass.RECOVERY_SUCCESS_MESSAGE`, and
`com.ilass.RECOVERY_INVALID_QR_MESSAGE`.

## Bridge behavior

Android must keep the same public action names as iOS. Unsupported features should return a structured error or availability payload.

Example unsupported Tap to Pay availability response:

```json
{
  "platform": "android",
  "action": "tapToPayAvailability",
  "requestId": "...",
  "success": true,
  "available": false,
  "readerType": "android_tap_to_pay",
  "reason": "Android Tap to Pay bridge is not implemented in this wrapper build yet."
}
```
