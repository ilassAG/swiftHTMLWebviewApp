# Android

The Android app is a native WebView wrapper that mirrors the iOS web-facing bridge shape.

## Current state

Implemented:

- Android Gradle project under `android/`.
- Native `WebView` container.
- Local smoke-test page in `app/src/main/assets/index.html`.
- iOS-compatible JavaScript shim:
  `window.webkit.messageHandlers.swiftBridge.postMessage(...)`.
- Structured native responses through `window.handleNativeResult(...)`.
- Stub bridge actions for features that still need native Android implementations.

Not implemented yet:

- Camera/photo capture.
- Barcode scanning.
- Document scanning.
- Android Tap to Pay / Stripe Terminal.

## Build

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
