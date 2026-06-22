# Wrapper Variant Architecture

The repository should make it fast to ship product-specific apps without
forking the native bridge contract. Real product identity, URLs, assets,
signing, and optional-module decisions live in private product repositories.

## Current implemented variants

The authoritative registry is `docs/app-variants.json`.

- Generic demo iOS: `com.ilass.swiftHTMLWebviewApp`, product name and display
  name `swiftHTMLWebviewApp`.
- Generic demo Android: Gradle module `:app`, application ID
  `com.ilass.swifthtmlwebviewapp`, label `swiftHTMLWebviewApp`.
- private product: migrated out of the open-source wrapper into its private
  repository through the Phase 4 pilot manifest.
- Product payment apps: migrated out of active wrapper code into private
  repositories; Stripe Tap to Pay is a private-product-owned optional module choice.
- Private Demo App: sanitized planning fixture for validator/generator coverage.

## Target shape

Keep these layers separate:

- Wrapper core: WebView setup, bridge dispatch, common settings, permissions,
  generic native capabilities, and structured unavailable responses.
- Optional modules: Stripe Tap to Pay, printer core, secure document module,
  and platform-specific capabilities.
- App variants: app name, bundle/application ID, icon, startup URL/default
  provisioning, release channel, feature flags, optional module selection,
  signing, and store metadata.

## Current guardrails

- `docs/bridge-contract.json` is the machine-readable bridge action registry,
  including per-action response profiles and emitted event catalogs.
- `docs/app-variants.json` records implemented and planned app variants plus
  runtime/recovery defaults and bridge capability profiles that must not drift
  during refactors. Planned variants also use a structured decision checklist
  from `plannedVariantDecisionCatalog`, so missing product inputs are explicit
  before platform files are scaffolded.
- `tools/validate_contracts.js` checks bridge dispatch references, generic app
  identity, Android runtime defaults, and optional-module boundaries. It also
  requires every implemented variant to declare both
  build/test commands, bridge capability coverage, and variant boundary test
  coverage in the registry. Production variants must not retain placeholder
  tokens or non-HTTPS startup URLs.
- `tools/variant_readiness.js` prints the current implemented variants and the
  open decision checklist for planned variants such as PrivateDemoApp. It
  also supports `--id <variant-id>` and `--require-ready` so automation can
  block scaffolding until identity, branding, startup, capability, bridge
  profile, and verification decisions are filled. Its JSON output includes the
  target artifacts and structured answer fields for each missing decision.
- `tools/variant_scaffold_plan.js` converts a planned variant into a concrete
  pre-scaffold plan with blocking decisions, answer fields, and target
  artifacts. With `--file` or `--stdin`, it converts a filled decision template
  into concrete iOS/Android scaffold artifact sections without editing files;
  it is the handoff between product intake and platform scaffolding.
- `tools/variant_decision_template.js` emits a fillable JSON decision template
  for those answer fields, so product input can be captured before platform
  targets or modules are created.
- `tools/variant_decision_check.js` validates a filled decision template and
  reports missing or invalid answers before registry or platform files are
  changed.
- `tools/variant_registry_plan.js` converts a valid decision template into a
  deterministic registry-update plan with JSON-patch-style operations. It
  refuses incomplete templates. For cross-platform product placeholders, it
  keeps the source variant as the decision record and derives iOS/Android
  platform registry-entry candidates with bridge profiles inferred from
  `docs/bridge-contract.json`.
- `docs/variant-manifest.schema.json` and `tools/variant_manifest_check.js`
  define the private product manifest contract. The manifest checker validates
  identity, branding, startup, bridge capabilities, optional modules, production
  safety, and can emit a decision-template object for the existing planning
  tools.
- `docs/private-product-footprint-allowlist.json` and
  `tools/private_product_footprint_audit.js` guard the temporary legacy footprint. New
  product-specific markers outside documented parity paths fail validation.
- `tools/generate_variant_workspace.js` turns a valid private manifest into a
  deterministic generated handoff under `native/generated`. It writes the
  workspace summary, decision template, scaffold plan, CI commands,
  `MIGRATION_STOP_GATE.json`, `PHASE4_DECISION_RECORD_TEMPLATE.md`, suggested
  private product `AGENTS.md` native-wrapper section, and review next steps, but does
  not yet move existing private product logic or directly edit real platform project
  files.
- `tools/phase4_stop_gate_check.js` validates generated handoff directories,
  required Phase 4 evidence IDs, generated command coverage, and copied
  decision-record placement before wrapper-owned product footprint is moved.
- `swiftHTMLWebviewAppTests` currently covers private iOS product identity,
  Settings.bundle/default alignment, isolated `AppSettings` behavior, HA URL
  de-duplication, generated device UUIDs, reset behavior, token redaction, and
  isolated settings bridge, startup URL resolver, recovery QR parser/handler,
  and shared capture response builder / bridge response shape / dispatcher
  behavior.
- iOS one-shot barcode response payloads are isolated in
  `BarcodeResponseBuilder` with unit tests outside `ContentView`.
- iOS native-result JavaScript generation and invalid-payload fallback are
  isolated in `BridgeScriptBuilder` with unit tests outside `WebViewStore`.
- iOS bridge action names and alias groups are cataloged in
  `BridgeActionCatalog` with unit tests; `ContentView` checks the built router
  against that catalog so action-contract drift is caught before further router
  extraction.
- iOS WebView error payload normalization is isolated in `WebViewErrorPayload`
  and uses the shared `BridgeResponse.error` envelope.
- iOS recovery-page HTML generation is isolated in `RecoveryPageBuilder` with
  unit tests, while `WebViewStore` owns only navigation and load state.
- iOS startup reachability probe URLs and HA timeout clamps are isolated in
  `StartupReachabilityPolicy` with unit tests outside `WebViewStore`.
- iOS startup candidate selection, HA advancement, and recovery-state fallback
  are isolated in `StartupLoadState` with unit tests outside `WebViewStore`.
- iOS startup load, timeout failover, main-frame failure, recovery, and reload
  reset decisions are isolated in `StartupLoadCoordinator`; `WebViewStore`
  applies the returned commands to WebKit.
- iOS one-shot capture request parsing and image format policy are isolated in
  `CaptureRequest` with unit tests outside `ContentView`.
- iOS continuous scanner request normalization, preview rectangle clamping, and
  stream control payloads are isolated in `ContinuousScannerResponseBuilder`
  with unit tests outside `ContentView`.
- iOS continuous scanner event payloads are isolated in
  `ContinuousScannerEventBuilder` with unit tests outside the scanner view.
- iOS ARKit local-position interval normalization, start/pending/stop/error
  responses, interruption events, and `arPosition` stream event envelopes are
  isolated in `ARPositionPayload` with unit tests; `ARPositionBridge` keeps
  ARSession, camera permission, tracking-state adaptation, and matrix
  extraction.
- iOS guided AR interval, world-map, and start-anchor request normalization,
  start/pending/acknowledgement/error responses, relocalization events,
  position stream events, and start/capture anchor event envelopes are isolated
  in `ARGuidedMeasurementPayload` with unit tests; `ARGuidedMeasurementBridge`
  keeps camera permission, ARKit frame adaptation, world-map loading, SceneKit
  rendering, start-arrow placement, alignment, and controller lifecycle.
- iOS RoomPlan start/stop/state/error responses, result envelopes, world-map
  metadata merging, and export payloads are isolated in `RoomPlanPayload` with
  unit tests; `RoomPlanBridge` keeps the RoomPlan scanner, ARWorldMap archiving,
  normalized room geometry, preview SVG generation, and capture lifecycle.
- iOS AR overlay open/close/error responses, replay action aliases,
  relocalization and item-selected event envelopes, and generic/floor-plan/
  legacy overlay scene normalization are isolated in `AROverlayPayload`
  with unit tests; `AROverlayBridge` keeps camera permission, ARKit world-map
  relocalization, SceneKit rendering, and controller lifecycle.
- iOS device capability maps, Wi-Fi status/configure payloads, Wi-Fi error
  messages, Wi-Fi info shape, and `soundPlay` request/response normalization
  are isolated in `DeviceBridgePayload` with unit tests; `DeviceBridge` keeps
  UIKit, NetworkExtension, WebKit, and audio session work.
- iOS iBeacon ranging start/stop responses, `beacons` event envelopes, beacon
  object payloads, advertiser request normalization, and advertiser state
  events are isolated in `BeaconPayload` with unit tests; `BeaconBridge` and
  `BeaconAdvertiserBridge` keep CoreLocation/CoreBluetooth lifecycle work.
- iOS idle timer request normalization, start/stop/reset response envelopes,
  and `idleTick` / `idleTimeout` event payloads are isolated in
  `IdleTimerPayload` with unit tests; `IdleTimerBridge` keeps timer state and
  WebView activity-shim injection.
- iOS local-notification permission envelopes, payload defaults, cancel ID
  normalization, schedule acknowledgements, and opened-event envelopes are
  isolated in `NotificationPayload` with unit tests; `NotificationBridge`
  keeps UserNotifications permission, scheduling, and delegate work.
- iOS screen-stream request normalization, start/stop acknowledgements,
  metadata, stats, and stream event envelopes are isolated in
  `ScreenStreamPayload` with unit tests; `ScreenStreamBridge` keeps WebSocket,
  WebKit snapshot, image scaling, timer, and send lifecycle work.
- iOS config-pairing target parsing, QR payloads, command normalization,
  response/event envelopes, and BLE chunk payloads are isolated in
  `ConfigPairingPayload` with unit tests; `ConfigPairingBridge` keeps
  CoreBluetooth manager/delegate work, QR image generation, secret creation,
  settings application, Wi-Fi configuration, reload handling, and overlay
  state.
- iOS native command acknowledgements such as `reload` and `launchConfetti` are isolated in
  `NativeCommandPayload`, so callback-profile commands return a success
  envelope before the WebView performs side effects.
- iOS Tap to Pay availability, collect success, cancel, and error envelopes are
  isolated in `TapToPayPayload`, so the wrapper reports a consistent bridge
  response even when StripeTerminal is not linked.
- iOS NFC response envelopes, tag identifier payloads, NDEF metadata, and
  record text/URI/MIME decoding are isolated in `NFCPayload` with unit tests;
  `NFCTagReaderBridge` keeps CoreNFC session, polling, connect, timeout, and
  tag technology adapters.
- iOS sensor capability responses, stream request normalization, start/stop
  acknowledgements, errors, and batched `sensorData` event envelopes are
  isolated in `SensorPayload` with unit tests; `SensorBridge` keeps CoreMotion
  manager registration, timers, snapshot collection, and shutdown lifecycle.
- iOS geolocation response envelopes, location payload nullability, start/stop
  acknowledgements, permission errors, and distance normalization are isolated
  in `LocationPayload` with unit tests; `LocationBridge` keeps CoreLocation
  permission, manager, delegate, and `CLLocation` adapter work.
- iOS screen-orientation mode/alias normalization and response envelopes are
  isolated in `OrientationPayload` with unit tests; `OrientationController`
  keeps UIKit orientation masks, active scene lookup, geometry updates, and
  device orientation side effects.
- iOS printer kind/label routing, Epson request parsing, discovery JSON,
  printercore JSON parsing, unavailable responses, and Epson job response
  merging are isolated in `PrinterPayload` with unit tests; `PrinterBridge`
  keeps optional `Printercore` linkage, Go binding calls, and background/main
  queue handoff.
- Android JVM tests currently cover generic Android identity, Android manifest
  metadata defaults, and absence of product-selected Stripe Terminal
  implementation from the open-source wrapper.
- Android Tap to Pay is now loaded through `TapToPayBridgeHost`, so private
  optional implementations do not depend directly on `MainActivity`; host
  base/error envelopes are isolated in `AndroidHostBridgePayload`.
- Android no-Stripe Tap to Pay fallback responses are isolated in
  `AndroidTapToPayPayload`; private product repositories supply product
  implementations when needed.
- Android startup URL/HA candidate resolution is isolated in
  `StartupUrlResolver` with pure JVM tests.
- Android configured startup loading, HA failover, timeout fallback, reload
  reset, and recovery command selection are isolated in
  `AndroidStartupLoadCoordinator` with pure JVM tests; `MainActivity` only
  executes WebView loads, timeout scheduling, and recovery-page rendering.
- Android native-result JavaScript generation is isolated in
  `AndroidBridgeScriptBuilder` with pure JVM tests; `MainActivity` only
  evaluates the generated script.
- Android WebView bridge shims for the iOS-compatible postMessage facade and
  idle activity events are isolated in `AndroidBridgeShimBuilder` with pure JVM
  tests.
- Android recovery QR startup URL parsing is isolated in
  `AndroidRecoveryConfigParser`; barcode-level config/recovery decisions,
  token checks, and `defaultServerUrl` alias handling are isolated in
  `AndroidBarcodeConfigHandler` with pure JVM tests.
- Android recovery-page HTML generation is isolated in
  `AndroidRecoveryPageBuilder` with pure JVM tests, while variant-specific
  recovery copy stays in manifest metadata.
- Android capture success envelopes, document image/PDF metadata, photo
  response payloads, and photo format selection for `scanDocument` and
  `takePhoto` are isolated in `AndroidCaptureResponseBuilder` with pure JVM
  tests.
- Android one-shot barcode success envelopes, response payloads, recovery
  persistence metadata, config-change acknowledgements, and scanner format names
  are isolated in `AndroidBarcodeResponseBuilder` with pure JVM tests.
- Android `screenshotGet` request normalization and response metadata are
  isolated in `AndroidScreenshotPayload` with pure JVM tests; `MainActivity`
  keeps bitmap capture, scaling, and JPEG encoding.
- Android continuous scanner request normalization, preview rectangle clamping,
  stream start/stop/error/closed-by-user payloads, and scanner barcode format
  selection are isolated in `AndroidContinuousScannerConfig` with pure JVM
  tests.
- Android continuous scanner event payloads are isolated in
  `AndroidContinuousScannerEventBuilder` with pure JVM tests.
- Android `settingsGet` / `settingsSet` response and token gate are isolated in
  `AndroidSettingsBridge`; persisted config reads/writes, aliases, startup URL
  candidate resolution, and device UUID normalization live in
  `AndroidSettingsStore` with pure JVM tests.
- Android `deviceInfoGet` capability payload construction is isolated in
  `AndroidDeviceCapabilities` with pure JVM tests, while `MainActivity` only
  supplies runtime NFC, Tap to Pay, and beacon support flags.
- Android `deviceInfoGet` diagnostics response assembly is isolated in
  `AndroidDeviceInfoPayload` with pure JVM tests; `MainActivity` still owns the
  Android framework queries and passes a snapshot into the payload helper.
- Android `deviceInfoGet` battery, screen, and memory diagnostic sub-payloads
  are also assembled by `AndroidDeviceInfoPayload`; `MainActivity` supplies only
  battery extras, display metrics, and `ActivityManager` memory values.
- Android `deviceInfoGet` camera and sensor diagnostic item payloads are also
  assembled by `AndroidDeviceInfoPayload`; `MainActivity` owns only the camera
  and sensor manager queries.
- Android Config Pairing device-summary payloads are also assembled by
  `AndroidDeviceInfoPayload`; `MainActivity` supplies only runtime values and
  Wi-Fi status.
- Android runtime permission policy for camera, location, notifications,
  iBeacon ranging/advertising, and config pairing is isolated in
  `AndroidPermissionPolicy` with pure JVM tests; `MainActivity` and Beacon
  lifecycle bridges only request or check the centralized permission sets.
- Android `soundPlay` request clamping and response construction are isolated
  in `AndroidSoundPayload` with pure JVM tests; `MainActivity` keeps only tone
  playback.
- Android iBeacon ranging start/stop responses, `beacons` event envelopes,
  stable beacon objects, proximity labels, advertiser request normalization,
  and advertiser state events are isolated in `AndroidBeaconPayload` with pure
  JVM tests; the ranging and advertiser bridges keep only AltBeacon,
  Bluetooth, permission, and lifecycle work.
- Android printer actions are isolated in `AndroidPrinterBridge`; printercore
  routing helpers, discovery target options, Epson request parsing,
  discovery/unavailable response envelopes, Epson job response merging, Sunmi
  job response envelopes, and Sunmi discovery entries are isolated in
  `AndroidPrinterPayload` with pure JVM tests.
- Android screen-orientation bridge actions are isolated in
  `AndroidScreenOrientationBridge` with pure JVM tests for mode mapping and
  response payloads; `MainActivity` only applies the requested orientation.
- Android idle-timer request normalization, start/stop/reset responses, and
  emitted `idleTick` / `idleTimeout` event payloads are isolated in
  `AndroidIdleTimerPayload` with pure JVM tests; `AndroidIdleTimerBridge` keeps
  timer state and scheduling, while `MainActivity` only supplies scheduling and
  touch/activity hooks.
- Android native command acknowledgements such as `reload` and `launchConfetti`
  are isolated in `AndroidNativeCommandPayload` with pure JVM tests, while
  `MainActivity` keeps URL reload scheduling and overlay attachment.
- Android Wi-Fi status payload construction, status/configure responses,
  configure error envelopes, provisioning URL persistence markers, request
  normalization, SSID redaction, and legacy quoting are isolated in
  `AndroidWifiBridge` with pure JVM tests; `MainActivity` keeps only Android OS
  permission, dialog, network-address, and `WifiManager` calls.
- Android config-pairing URL payloads, target parsing, internal UI request
  construction, command request construction, show/connect acknowledgements,
  send/error response envelopes, event envelopes, and BLE chunk reassembly state
  are isolated in
  `AndroidConfigPairingProtocol` with pure JVM tests; the BLE bridge keeps
  platform GATT/scanner/advertising work.
- Android local-notification permission, command, list, and opened-event
  envelopes, payload defaults, cancel ID normalization, and data parsing are
  isolated in `AndroidNotificationPayload` with pure JVM tests;
  `AndroidNotificationBridge` keeps OS permission, alarm, and notification
  manager work.
- Android geolocation response envelopes, stream start/stop acknowledgements,
  error envelopes, and location payload nullability are isolated in
  `AndroidLocationPayload` with pure JVM tests; `MainActivity` keeps OS
  permission, provider, and listener management.
- Android screen-stream request normalization, acknowledgements, metadata,
  stats, and stream event envelopes are isolated in
  `AndroidScreenStreamPayload` with pure JVM tests; `AndroidScreenStreamBridge`
  keeps WebSocket, capture, encoding, and scheduling work.
- Android sensor response envelopes, sensor type aliases, capability payloads,
  and `sensorData` event payloads are isolated in `AndroidSensorPayload` with
  pure JVM tests; `AndroidSensorBridge` keeps `SensorManager` registration,
  throttling, and listener lifecycle work.
- Android NFC response envelopes, tag identifier/technology payloads,
  technology-detail field mapping, NDEF metadata, and record text/URI/MIME
  decoding are isolated in `AndroidNfcPayload` with pure JVM tests;
  `AndroidNfcTagReaderBridge` keeps `NfcAdapter` reader mode, timeout, and
  concrete tag technology access.
- Shared Android bridge base/error/unavailable response shape is centralized in
  `BridgeResponse` and covered by pure JVM tests; `MainActivity` delegates
  through the helper instead of owning private error-envelope builders.
- Android ARKit/RoomPlan unavailable response payloads are isolated in
  `AndroidUnavailableBridge` and covered by pure JVM tests.
- Android JS action parsing plus missing/unknown action responses are isolated
  in `BridgeDispatcher` and covered by pure JVM tests.
- Android raw JS message routing plus registered native action dispatch is
  isolated in `AndroidBridgeRouter`; `MainActivity.NativeBridge` only delegates
  `postMessage`.
- Android bridge action names and alias groups are cataloged in
  `AndroidBridgeActionCatalog`; `MainActivity` checks the built router against
  the catalog before exposing it to the WebView bridge.
- iOS JS action parsing plus missing/unknown action responses are isolated in
  `BridgeDispatcher`, and raw JS message routing is isolated in `BridgeRouter`;
  `ContentView.handleScriptMessage` only delegates into the router.

## Android direction

Move toward:

```text
android/
  wrapper-core/              # Android library with shared WebView bridge
  app/                       # generic demo app variant
```

Near-term extraction points from `MainActivity`:

1. Keep product strings/defaults, including recovery-page branding and copy, in
   resources or manifest metadata instead of `MainActivity`.
2. Continue extracting shared WebView, settings persistence, and the already
   isolated bridge dispatch helpers into `:wrapper-core`.
3. Keep product-selected Stripe implementations in private product repositories or a
   future sanitized optional module, not in a product-named wrapper app.

## iOS direction

Move toward:

```text
ios/
  swiftHTMLWebviewApp.xcodeproj
  swiftHTMLWebviewApp/       # Shared wrapper core code
  Variants/                  # Per-app config, assets, and xcconfig files
```

Near-term extraction points from `ContentView`:

1. Keep `AppVariant` / `AppSettings` tests green while moving more defaults out
   of hard-coded UI and recovery HTML. Loading image plus recovery branding and
   copy are read from `AppVariant` through `AppSettings`.
2. Keep `settingsGet` / `settingsSet` isolated in the testable
   `SettingsBridge`.
3. Keep startup URL/HA candidate resolution isolated in the pure
   `StartupURLResolver`.
4. Keep recovery QR startup URL parsing and recovery barcode persistence
   decisions isolated in `RecoveryConfigParser` / `RecoveryBarcodeHandler`.
5. Continue moving feature-specific action handlers out from `ContentView`
   behind the already isolated `BridgeRouter`.
6. Move recovery page text and loading image names behind `AppVariant`.
7. Add xcconfig-based variant settings only after current private product identity
   tests cover the baseline.

## Rules for new variants

1. Add the variant to `docs/app-variants.json`.
2. For planned variants, start with
   `node tools/variant_plan.js --id <variant-id> --name <display-name> --platform <ios|android|cross-platform>`.
3. Fill `requiredDecisionIds` and `decisionChecklist`
   from `plannedVariantDecisionCatalog` until identity, branding, startup
   provisioning, native capabilities, bridge profile, and verification are
   decided. Keep each checklist item's `targetArtifacts` aligned with the
   platform-filtered catalog so readiness output points at the files that must
   change next. Path placeholders such as `<variant>` must be resolved to the
   concrete variant id. `cross-platform` planned variants keep both iOS and
   Android target artifacts. Use the catalog's `answerFields` as the
   machine-readable intake shape for each decision instead of collecting
   free-form product notes.
4. Add a `bridgeProfile` with the platform contract, enabled optional modules,
   and expected platform-unavailable actions.
5. Set the `releaseChannel`; use `production` only when startup URLs and
   secrets are production-safe.
6. Add or update icons and app metadata in the platform-specific variant module
   or target.
7. Keep product-specific URLs, labels, and recovery text out of wrapper core
   where possible.
8. Run `node tools/validate_contracts.js` before platform builds.
9. Run `node tools/validate_contracts.js --run-verification` when you want the
   registry to execute every implemented variant's build/test command.
10. Run `node tools/variant_readiness.js` when you need a quick overview of
   existing wrapper consumers and the decisions still blocking planned apps.
11. Run
   `node tools/variant_readiness.js --id <variant-id> --require-ready` before
   scaffolding platform files for a planned variant. A non-zero exit means the
   app is known but not ready to implement.
12. Run `node tools/variant_scaffold_plan.js --id <variant-id>` to get the
   concrete pre-scaffold checklist of answer fields and target artifacts.
13. Run `node tools/variant_decision_template.js --id <variant-id>` when you
   need a fillable JSON document for collecting the required product decisions.
14. Run
   `node tools/variant_decision_check.js --file <decision-template.json>` after
   filling the template. A non-zero exit means required answers are still
   missing or invalid.
15. Run
   `node tools/variant_registry_plan.js --file <decision-template.json>` to
   review deterministic registry fields, patch operations, derived
   platform-entry candidates for cross-platform variants, and unresolved
   follow-up work before editing `docs/app-variants.json` or platform files.
16. Run
   `node tools/variant_scaffold_plan.js --file <decision-template.json>` to
   review the concrete platform scaffold artifacts, source templates, and
   build/test commands that should be created from the approved decisions.
