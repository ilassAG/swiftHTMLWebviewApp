# Android

The Android app is a native WebView wrapper that mirrors the iOS web-facing bridge shape.

## Current state

Implemented:

- Android Gradle project under `android/`.
- Native `WebView` container.
- Local iOS-parity demo page in `app/src/main/assets/index.html`.
- iOS-compatible JavaScript shim:
  `window.webkit.messageHandlers.swiftBridge.postMessage(...)`.
- Structured native responses through `window.handleNativeResult(...)`.
- Native Android confetti overlay.
- Photo capture through Android camera intent.
- Barcode/QR scanning through Google Code Scanner.
- Document scanning through Google ML Kit Document Scanner with JPEG/PDF result handling.
- Embedded continuous QR/barcode scanning through CameraX and ML Kit.
- iBeacon ranging through AltBeacon.
- Optional printer discovery and Epson Hello World printing through the Go `printercore` AAR.
- Sunmi internal-printer discovery and Hello World printing when the Sunmi AIDL service is installed.
- Runtime diagnostics: device info, app screenshot, orientation lock, sound,
  idle timer, location, sensors, Wi-Fi setup/status, and app-screen JPEG
  streaming over WebSocket.

Not implemented yet:

- Android Tap to Pay / Stripe Terminal.
- Background removal for captured photos.
- OCR text extraction for scanned documents.
- Full device-screen capture through MediaProjection.

## Build

The generated `app/libs/printercore.aar` is optional and ignored by git. A clean
checkout builds without it; run `../printercore/scripts/build_mobile.sh` when
you want the Go printer core packaged into the Android app.

```sh
cd android
./gradlew assembleDebug
```

## Install on USB device

```sh
cd android
./gradlew installDebug
```

If the device shows as `unauthorized`, unlock it and accept the USB debugging prompt.

## Bridge contract

Keep action names compatible with iOS. Unsupported actions must return a structured error or availability payload instead of doing nothing.
