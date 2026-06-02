# iOS

The iOS app lives in `ios/`.

## Open in Xcode

```sh
open ios/swiftHTMLWebviewApp.xcodeproj
```

Select the `swiftHTMLWebviewApp` scheme and build for simulator or device.

Regenerate the Go mobile binding if `printercore` changed or if
`ios/Frameworks/Printercore.xcframework` is missing:

```sh
printercore/scripts/build_mobile.sh
```

## Default configuration

The iOS app loads its URL from `ios/swiftHTMLWebviewApp/Configuration.swift` and the Settings bundle.

## Optional Stripe Tap to Pay

The source contains `TapToPayBridge.swift`, but it is guarded with `#if canImport(StripeTerminal)`.

That means:

- The app builds without StripeTerminal.
- Web content can still call `tapToPayAvailability` and gets `available: false`.
- Adding StripeTerminal to the Xcode project enables the native Tap to Pay implementation.

See `docs/stripe-tap-to-pay.md`.

## Optional Epson Printer Smoke Test

`PrinterBridge.swift` is backed by `ios/Frameworks/Printercore.xcframework`.
Web content can call `printerEpsonHelloWorld` with an Epson printer host such as
`10.10.10.131`. The app includes `NSLocalNetworkUsageDescription` for LAN printer
access.
