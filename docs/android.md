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
- Google ML Kit Document Scanner UI for `scanDocument`, returning JPEG image data URLs or PDF data URLs.

Not implemented yet:

- Android Stripe Terminal / Tap to Pay.
- iOS-style background removal options for `takePhoto`.
- OCR text extraction for document scans.

## Build

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
