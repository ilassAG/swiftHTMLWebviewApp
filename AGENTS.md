# Agent Notes for swiftHTMLWebviewApp

## Project Purpose
`swiftHTMLWebviewApp` is an open-source native WebView wrapper. The repository is structured as a multi-platform wrapper project:

- `ios/`: original SwiftUI/WKWebView app, currently the most complete platform.
- `android/`: Android implementation/scaffold for feature parity.
- `docs/`: platform and bridge documentation.
- `examples/`: web examples for bridge integrations.

The wrapper should expose native capabilities to web apps. Product-specific business logic must stay in the consuming web app/backend.

Product-specific native app identity, production URLs, icons, splash/loading
assets, signing references, store metadata, and release decisions belong in the
private product repositories. Keep this open-source wrapper generic: add shared
bridge behavior, optional native modules, demo/example config, validation tools,
and sanitized fixtures here. Do not add new real product data to this
repository unless the user explicitly asks for a temporary migration step.

## Downstream Product Sync

The ZeltPOS/Kassa native wrapper client is a separate product repository at
`/Users/raistlin/Dropbox/1 ilass AG/Projekte/KassaRunnigDevelopment/kassa-zeltpos-native-wrapper`.
It consumes this repository as a vendored/subtree-style upstream under
`vendor/swiftHTMLWebviewApp/` and keeps product-specific iOS/Android copies
under `native/kassa/ios/` and `native/kassa/android/`.

When shared wrapper behavior changes, make the generic change in this global
`ilassAG/swiftHTMLWebviewApp` repository first and commit it here. Then import
that commit into the product repository with the appropriate git vendor/subtree
sync and mirror it into the product copy. Do not leave shared wrapper fixes only
in a downstream product repo. Product repos should only own app identity,
bundle/application IDs, signing, store metadata, icons, splash/loading assets,
deployment URLs, and product configuration.

## iOS Device Screenshots

For screenshots from a USB-connected physical iPad/iPhone, prefer the DVT
screenshot path. `idevicescreenshot` / `screenshotr` can fail on iOS 17.x.

1. Get the USB UDID: `idevice_id -l`.
2. Start an RSD tunnel and keep it running:
   `sudo pymobiledevice3 remote start-tunnel --udid <UDID> --script-mode`.
   The command prints `<RSD_HOST> <RSD_PORT>`.
3. Capture the screenshot:
   `pymobiledevice3 developer dvt screenshot --rsd <RSD_HOST> <RSD_PORT> output/ipad-screenshots/<name>.png`.
4. Stop the tunnel with Ctrl-C.

If sudo is needed on this Mac, the local password is stored at
`/Users/raistlin/Dropbox/1 ilass AG/Projekte/natsViewer/sudo.txt`.

## Current Native Bridge Contract
Web apps call native features by posting messages into the platform bridge. Keep the web-facing API stable across iOS and Android.

Common actions:

- `scanDocument`
- `takePhoto`
- `scanBarcode`
- `launchConfetti`
- `tapToPayAvailability`
- `tapToPayCollect`

See `docs/native-bridge.md` and `docs/stripe-tap-to-pay.md` before changing bridge behavior.

## iOS Notes
The iOS app lives in `ios/`.

Open/build with:

```sh
open ios/swiftHTMLWebviewApp.xcodeproj
xcodebuild -project ios/swiftHTMLWebviewApp.xcodeproj -scheme swiftHTMLWebviewApp -destination 'generic/platform=iOS Simulator' build
```

Stripe Tap to Pay is optional source code. `TapToPayBridge.swift` uses `#if canImport(StripeTerminal)` so the generic wrapper still builds without linking StripeTerminal.

Do not make StripeTerminal a mandatory dependency unless explicitly requested.

## Android Notes
The Android app lives in `android/`.

Keep Android aligned with the same bridge action names as iOS. If a native feature is not implemented yet, return a structured unavailable/error payload instead of silently doing nothing.

## Repository Hygiene
- Do not commit generated build folders such as `build/`, `.gradle/`, `DerivedData/`, or Android Studio local files.
- Do not commit credentials, Stripe keys, provisioning files, or local signing keys.
- Prefer small, focused commits.
- Run platform builds after structural changes.

## Git Safety
Only commit or push when explicitly requested by the user.
