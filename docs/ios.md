# iOS

The iOS app lives in `ios/`.

## Open in Xcode

```sh
open ios/swiftHTMLWebviewApp.xcodeproj
```

Select the `swiftHTMLWebviewApp` scheme and build for simulator or device.

## Default configuration

The iOS app loads its URL from `ios/swiftHTMLWebviewApp/Configuration.swift` and the Settings bundle.

## Optional Stripe Tap to Pay

The source contains `TapToPayBridge.swift`, but it is guarded with `#if canImport(StripeTerminal)`.

That means:

- The app builds without StripeTerminal.
- Web content can still call `tapToPayAvailability` and gets `available: false`.
- Adding StripeTerminal to the Xcode project enables the native Tap to Pay implementation.

See `docs/stripe-tap-to-pay.md`.
