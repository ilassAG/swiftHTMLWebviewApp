# Android

Android support is intentionally scaffolded but not implemented yet.

The goal is feature parity with the iOS WebView container through the same JavaScript bridge shape:

- WebView loading local or remote HTML
- Camera/photo actions
- Barcode/QR scanning
- Native confetti
- Optional payment bridge capabilities where the platform supports them

Tap to Pay is platform-specific. Android should expose the same web-facing bridge actions as iOS, but the native implementation will use Android-compatible Stripe Terminal APIs and Android app permissions/capabilities.
