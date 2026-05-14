# Android

Android support is scaffolded in `android/` but not implemented yet.

Target parity:

- WebView container
- Same JavaScript bridge API shape as iOS
- Camera/photo/barcode features where supported
- Optional payment module with the same web-facing actions

Tap to Pay on Android must use the Android-compatible Stripe Terminal APIs and platform permissions. The web-facing bridge should stay compatible with iOS:

- `tapToPayAvailability`
- `tapToPayCollect`
