# Testing

This project is a reusable native WebView wrapper. Tests should protect the
shared bridge contract and app variant metadata before platform-specific UI
flows are refactored.

## Fast contract validation

Run from the repository root:

```sh
node tools/validate_contracts.js
```

Run the same contract checks plus every implemented variant's registered build
and test command:

```sh
node tools/validate_contracts.js --run-verification
```

This validates:

- `docs/bridge-contract.json` action names, platform support states, and native
  dispatch references. Native main dispatch actions must either exist in the
  contract or be listed as explicit internal actions such as `idleActivity`.
- Bridge response-shape basics, per-action response profiles, emitted event
  catalogs, compatibility aliases, and the separation of planned
  secure-document actions from the existing non-secure bridge.
- Recorded legacy response-shape exceptions, currently for iOS
  `scanDocument`, `takePhoto`, and one-shot `scanBarcode`, including test-file
  evidence for each exception.
- `docs/bridge-response-fixtures.json` profile-level success/error examples
  against every `responseProfile`, instantiated across every public bridge
  action so response-shape drift is caught without launching a platform build.
- `docs/app-variants.json` implemented app variants against Xcode, Gradle, and
  Android manifest metadata. Each implemented variant must record build and
  test commands plus variant boundary test coverage so new app variants stay
  independently verifiable.
- Planned app variants against the structured decision catalog, so sanitized
  private fixtures must list the concrete missing identity, branding, startup,
  capability, bridge-profile, and verification decisions.
- `tools/variant_readiness.js` filtering and readiness gates, so a planned
  private fixture is machine-reported as blocked until the required product
  decisions are filled. Readiness output also includes the target
  artifacts and structured answer fields for each blocking decision, so
  follow-up work can jump directly to the files and inputs that must change.
- `tools/variant_scaffold_plan.js` turns a planned variant into a concrete
  decision/input/file plan without editing platform files. With a filled
  decision template from `--file` or `--stdin`, it also emits the concrete iOS
  and Android scaffold artifact plan: registry patch operations, module/target
  files, source templates, and build/test commands.
- `tools/variant_decision_template.js` emits a fillable JSON template for the
  same decision fields, so product inputs can be collected without changing
  platform files first.
- `tools/variant_decision_check.js` validates a filled decision template and
  reports missing required answers before scaffold or registry edits begin.
- `tools/variant_registry_plan.js` turns a valid decision template into a
  deterministic registry-update plan with JSON-patch-style operations and
  refuses incomplete templates. For cross-platform placeholders, it also
  derives separate iOS and Android registry-entry
  candidates with bridge profiles inferred from `docs/bridge-contract.json`.
- `docs/variant-manifest.schema.json`, `docs/variant-manifest.example.json`, and
  `tools/variant_manifest_check.js` define and validate the private product
  `native/variant.json` contract before product-specific identity, branding,
  URLs, and assets are moved out of the open-source wrapper.
- `tools/generate_variant_workspace.js` validates a private product manifest
  and writes deterministic handoff files under `native/generated`: normalized
  workspace summary, decision template, scaffold plan, CI commands,
  `MIGRATION_STOP_GATE.json`, a copyable Phase 4 decision record template, and
  review next steps. It also emits `PRIVATE_PRODUCT_AGENTS_NATIVE_SECTION.md` so the
  private product repository can document ownership and generated-file rules
  consistently.
  It intentionally stops before moving existing private product logic or directly
  editing real iOS/Android project files.
- `tools/phase4_stop_gate_check.js` validates a generated handoff directory,
  the explicit Phase 4 stop gate, generated command coverage, and optional
  copied decision records before any wrapper-owned product footprint is moved.
- `tools/private_product_footprint_audit.js` scans the open-source wrapper for
  product markers. It allows only the documented temporary legacy
  footprint in `docs/private-product-footprint-allowlist.json` and fails on new
  product-specific identity, branding, or LAN startup URLs outside those paths.
- Planned app variants with `needed` decisions must not already contain the
  corresponding platform artifact fields, runtime defaults, bridge profiles, or
  verification commands. This keeps placeholders from looking implemented.
- Variant bridge capability profiles, including enabled optional modules and
  platform-specific unavailable actions, against `docs/bridge-contract.json`.
- Release-channel guardrails so production variants cannot keep placeholder
  tokens or non-HTTPS startup URLs in their registered defaults.
- Generic iOS `AppVariant` defaults against Settings.bundle defaults.
- Android manifest metadata runtime defaults for the generic demo wrapper.
- Optional module hooks stay generic; product-selected implementations such as
  Stripe Tap to Pay live in private product repositories.
- Android JUnit test presence for generic wrapper variant boundaries.
- Android Tap to Pay host-interface wiring, including no direct `MainActivity`
  dependency from the optional Stripe bridge.
- Android Tap to Pay / printer host base and error envelopes through
  `AndroidHostBridgePayload`.
- Android Tap to Pay no-Stripe fallback availability/error envelopes for the
  generic wrapper.
- Planned secure document actions remain explicitly planned instead of being
  confused with the existing cleartext `scanDocument` / `takePhoto` actions.
  While planned, no `secure*` action may be registered in native dispatch or
  exposed from the bundled demo scripts.

## Current build checks

```sh
go test ./...
```

from `printercore/`.

```sh
go test ./...
```

from `tools/screenstreamviewer/`.

```sh
xcodebuild -project ios/swiftHTMLWebviewApp.xcodeproj -scheme swiftHTMLWebviewApp -destination 'generic/platform=iOS Simulator' build
```

from the repository root.

```sh
xcodebuild -project ios/swiftHTMLWebviewApp.xcodeproj -scheme swiftHTMLWebviewApp -destination 'platform=iOS Simulator,name=iPhone 17' test
```

from the repository root. The current iOS tests cover private product variant
identity, Settings.bundle/default alignment, isolated `AppSettings` defaults,
HA URL de-duplication, reset behavior, generated device UUIDs, and token
redaction in public settings snapshots, plus variant-driven loading image and
recovery copy. `SettingsBridgeTests` cover the JS `settingsGet` / `settingsSet`
response shape, token enforcement, and nested settings application outside
`ContentView`. `NativeCommandPayloadTests` cover iOS `reload` and
`launchConfetti` acknowledgements so callback commands return a native-command
envelope before the WebView performs side effects. `TapToPayPayloadTests` cover
iOS Tap to Pay availability and collect error envelopes, including builds where
StripeTerminal is not linked. `StartupURLResolverTests`
cover local URL aliases, HA candidate
de-duplication, and local fallback behavior outside `AppSettings`.
`BridgeScriptBuilderTests` cover iOS native-result JavaScript generation,
JSON escaping, and fallback payloads outside `WebViewStore`.
`WebViewErrorPayloadTests` cover iOS WebView error responses through the shared
bridge error envelope outside `WebViewStore`.
`BridgeActionCatalogTests` cover the complete iOS bridge action surface and
alias groups outside `ContentView`, while `ContentView` checks the built router
against the catalog during router installation.
`StartupReachabilityPolicyTests` cover iOS startup health-probe URL generation
and HA timeout clamping outside `WebViewStore`.
`StartupLoadStateTests` cover iOS startup candidate selection, HA advancement,
local-page detection, and recovery-state fallback outside `WebViewStore`.
`StartupLoadCoordinatorTests` cover iOS startup load, timeout failover,
main-frame failure, recovery, and reload reset decisions outside `WebViewStore`.
`RecoveryConfigParserTests` cover recovery QR startup URL extraction,
normalization, source detection, invalid-response creation, and settings
persistence decisions outside `ContentView`.
`RecoveryPageBuilderTests` cover recovery-page HTML, escaping, and bridge
actions outside `WebViewStore`.
`CaptureRequestTests` cover `scanDocument`, `takePhoto`, and `scanBarcode`
request parsing, camera selection, and capture output-format policy outside
`ContentView`.
`CaptureResponseBuilderTests` cover action-specific `scanDocument` and
`takePhoto` response payload fields outside `ContentView`.
`BarcodeResponseBuilderTests` cover action-specific `scanBarcode` success,
QR-configuration-change acknowledgements before reload, and recovery error
payload fields outside `ContentView`.
`ContinuousScannerResponseBuilderTests` cover continuous scanner request
normalization, preview rectangle clamping, scanner frame calculation, and
stream start/stop payloads outside `ContentView`.
`ContinuousScannerEventBuilderTests` cover `barcodeData` / `barcodeLogin`
event payload fields outside the scanner view.
`ARPositionPayloadTests` cover `arPositionStart` interval normalization,
start/pending/stop/error responses, interruption events, and cataloged
`arPosition` stream event payloads outside `ARPositionBridge`.
`ARGuidedMeasurementPayloadTests` cover guided AR interval/world-map/start
anchor request normalization, start/pending/acknowledgement/error responses,
position and relocalization events, and start/capture anchor events outside
`ARGuidedMeasurementBridge`.
`RoomPlanPayloadTests` cover `roomPlanScanStart` / `roomPlanScanStop`,
`roomPlanScanState`, `roomPlanScanResult`, `roomPlanScanExport`, world-map
metadata merging, and RoomPlan error envelopes outside `RoomPlanBridge`.
`AROverlayPayloadTests` cover `arOverlayOpen` / `arReplayOpen`, pending
permission and close acknowledgements, relocalization and item-selected event
envelopes, plus generic, floor-plan, and legacy overlay scene
normalization outside `AROverlayBridge`.
`DeviceBridgePayloadTests` cover `deviceInfoGet` capability maps, Wi-Fi
status/configure payloads, Wi-Fi error normalization, Wi-Fi info shape, and
`soundPlay` request clamping outside `DeviceBridge`.
`BeaconPayloadTests` cover iBeacon ranging UUID fallback, start/stop response
envelopes, `beacons` event shape, advertiser config aliases and invalid
parameter rejection, advertiser state events, and advertise stop/error
responses outside CoreLocation/CoreBluetooth bridges.
`IdleTimerPayloadTests` cover `idleTimerStart` request clamping,
start/stop/reset response envelopes, and cataloged `idleTick` / `idleTimeout`
event payloads outside `IdleTimerBridge`.
`NotificationPayloadTests` cover notification permission envelopes, payload
defaults, cancel ID normalization, schedule acknowledgements, and opened-event
payloads outside `NotificationBridge`.
`ScreenStreamPayloadTests` cover `screenStreamStart` request normalization,
start/stop acknowledgements, metadata, stats, and stream events outside
`ScreenStreamBridge`.
`ConfigPairingPayloadTests` cover config-pairing QR payload roundtrips, target
parsing with aliases and duplicate query keys, command normalization,
response/event envelopes, and chunk reassembly/validation outside
`ConfigPairingBridge`.
`NFCPayloadTests` cover `nfcTagRead` response envelopes, tag payload
identifiers, NDEF metadata, text/URI/MIME record decoding, and unknown TNF
fallback outside `NFCTagReaderBridge`.
`SensorPayloadTests` cover `sensorCapabilitiesGet`, `sensorStreamStart` /
`sensorStreamStop`, interval normalization, errors, and batched `sensorData`
events outside `SensorBridge`.
`LocationPayloadTests` cover `geoLocationGet` / `geoLocation` response
envelopes, location field nullability, start/stop acknowledgements, permission
errors, and distance normalization outside `LocationBridge`.
`OrientationPayloadTests` cover `screenOrientationSet` mode/alias
normalization and `screenOrientationGet` / `screenOrientationSet` response
envelopes outside `OrientationController`.
`PrinterPayloadTests` cover printer kind/label routing, Epson request parsing,
discovery JSON serialization, printercore JSON parsing, unavailable envelopes,
unsupported iOS printer kinds, and Epson job response merging outside
`PrinterBridge`.
`BridgeResponseTests` cover shared base, error, and unavailable response shape.
`BridgeDispatcherTests` cover JS action extraction and structured missing /
unknown action responses outside `ContentView`.
`BridgeRouterTests` cover raw JS message routing into registered native action
handlers outside `ContentView`.

```sh
cd android
./gradlew :app:assembleDebug
./gradlew :app:testDebugUnitTest
```

Use the variant-readiness CLI before scaffolding another app wrapper:

```sh
node tools/variant_readiness.js
node tools/variant_readiness.js --id private-demo-app --require-ready
```

The second command intentionally exits with code `2` while required decisions
are still missing. That makes the difference between "known future app" and
"safe to implement now" explicit. The JSON output includes
`missingDecisions[].targetArtifacts` and `blockingTargetArtifacts` for planned
variants. For platform-specific planned variants, `targetArtifacts` are filtered
to the relevant iOS or Android files and `<variant>` path placeholders are
resolved to the concrete variant id; `cross-platform` variants keep both
platforms' target artifacts.

After those decisions are filled, `tools/variant_registry_plan.js` keeps the
cross-platform source variant as the product-decision record and emits
JSON-patch-style `add` operations for the platform-specific registry entries.
Those entries are still planned until the Xcode target, Gradle module, assets,
and variant-boundary tests exist and pass.

Use the filled template with `tools/variant_scaffold_plan.js --file` or
`--stdin` to review the platform scaffold artifacts before writing files. For
cross-platform apps, the output includes separate iOS and Android scaffold
sections so private products can follow the same
repeatable sequence.

The current Android JVM tests cover:

- `:app` identity as the generic demo wrapper.
- Absence of Stripe Terminal from `:app`.
- private product runtime defaults declared as variant manifest metadata.
- private product recovery metadata kept out of shared `MainActivity`
  HTML.
- private product recovery-page HTML and escaping covered outside
  `MainActivity`.
- Android startup URL candidate resolution covered as a pure JVM test.
- Android configured startup loading, HA failover, timeout fallback, reload reset,
  and recovery command selection covered as pure JVM tests outside
  `MainActivity`.
- Android native-result JavaScript generation and JSON escaping covered in
  `AndroidBridgeScriptBuilderTest` outside `MainActivity`.
- Android iOS-compatible postMessage facade and idle-activity WebView shims
  covered in `AndroidBridgeShimBuilderTest` outside `MainActivity`.
- Android recovery QR startup URL extraction and normalization covered as pure
  JVM tests outside `MainActivity`.
- Android `scanDocument` and `takePhoto` success envelopes, response payload
  fields, document image metadata, and photo format selection covered as pure
  JVM tests outside `MainActivity`.
- Android `scanBarcode` success envelopes, response payload fields, recovery
  persistence metadata, config-change acknowledgements, scanner format names,
  config QR token checks, and recovery QR decision handling covered as pure JVM
  tests outside `MainActivity`.
- Android `deviceInfoGet` diagnostics envelope, runtime snapshot field mapping,
  battery/screen/memory diagnostic payloads, camera and sensor diagnostic
  payloads, and Config Pairing device-summary shape covered as pure JVM tests
  outside `MainActivity`.
- Android `screenshotGet` max-width/quality normalization and diagnostics
  response metadata covered as pure JVM tests outside `MainActivity`.
- Android continuous scanner request normalization, preview rectangle clamping,
  stream start/stop/error/closed-by-user payloads, and scanner barcode format
  selection covered as pure JVM tests outside
  `ContinuousBarcodeScannerController`.
- Android continuous scanner `barcodeData` / `barcodeLogin` event payloads
  covered as pure JVM tests outside `ContinuousBarcodeScannerController`.
- Android `geoLocationStart` / `geoLocationStop` stream-control
  acknowledgements and location error envelopes covered as pure JVM tests
  outside `MainActivity`.
- Android `settingsGet` / `settingsSet` response, public settings snapshot
  shape, token handling, persisted config aliases, startup URL candidate
  resolution, and device UUID normalization covered as pure JVM tests outside
  `MainActivity`.
- Android shared base, error, and unavailable response shape covered as pure
  JVM tests; variant tests keep private error-envelope builders out of
  `MainActivity`.
- Android host base/error response normalization for optional bridge hosts is
  covered in `AndroidHostBridgePayloadTest` outside `MainActivity`.
- Android ARKit/RoomPlan unavailable response payloads are isolated in
  `AndroidUnavailableBridge` and covered as pure JVM tests outside
  `MainActivity`.
- Android device capability payloads covered as pure JVM tests outside
  `MainActivity`, including common wrapper capabilities, Android-unavailable
  AR/RoomPlan actions, and runtime optional module flags.
- Android permission policy for camera, location, notifications, iBeacon
  ranging/advertising, and config pairing covered as pure JVM tests outside
  `MainActivity` and the Beacon lifecycle bridges.
- Android `soundPlay` request clamping and native-command response envelopes
  covered as pure JVM tests outside `MainActivity`.
- Android iBeacon ranging/advertising payloads covered as pure JVM tests
  outside the AltBeacon and Bluetooth lifecycle bridges, including UUID
  fallback/normalization, advertiser aliases, invalid parameter rejection,
  start/stop acknowledgements, advertiser state events, `beacons` event
  envelopes, and legacy-compatible beacon maps.
- Android printer routing helpers, discovery target options, printer discovery
  response envelopes, Epson request parsing, Sunmi internal discovery entries,
  printercore unavailable envelopes, and Epson/Sunmi job response envelopes
  covered as pure JVM payload tests outside `MainActivity`, outside
  `AndroidPrinterBridge`, and outside Android framework dependencies.
- Android screen-orientation mode mapping and response payloads covered as pure
  JVM tests outside `MainActivity`.
- Android idle timer request normalization, start/stop/reset responses, and
  `idleTick` / `idleTimeout` event payloads covered as pure JVM payload tests
  outside `AndroidIdleTimerBridge`; bridge tests cover scheduling and timeout
  state outside `MainActivity`.
- Android native-command payloads for `reload` and `launchConfetti` are covered
  as pure JVM tests outside `MainActivity`.
- Android Wi-Fi status/configure response shape, SSID/passphrase normalization,
  configure error envelopes, status defaults, SSID redaction, server URL
  persistence markers, method-specific Android configure responses, and legacy
  quote escaping covered as pure JVM tests outside `MainActivity`.
- Android config-pairing QR payload parsing, internal UI request construction,
  command construction, show/connect acknowledgements, send/error response
  envelopes, unknown-action error envelopes, event envelopes, and BLE chunk
  reassembly state covered as pure JVM tests outside
  `AndroidConfigPairingBridge`.
- Android local-notification permission, command, list, and opened-event
  envelopes, payload defaults, and cancel ID normalization covered as pure JVM
  tests outside `AndroidNotificationBridge`.
- Android `geoLocationGet` / `geoLocation` location payload envelopes and
  optional signal nullability covered as pure JVM tests outside `MainActivity`.
- Android `screenStreamStart` / `screenStreamStop` request normalization,
  acknowledgement payloads, metadata, stats, and stream events covered as pure
  JVM tests outside `AndroidScreenStreamBridge`.
- Android `sensorCapabilitiesGet` / `sensorStreamStart` response payloads,
  sensor type aliases, and `sensorData` event envelopes covered as pure JVM
  tests outside `AndroidSensorBridge`.
- Android `nfcTagRead` response envelopes, tag identifier/technology payloads,
  technology-detail fields, NDEF metadata, and record text/URI/MIME decoding
  covered as pure JVM tests outside `AndroidNfcTagReaderBridge`.
- Android JS action extraction and structured missing / unknown action responses
  covered as pure JVM tests outside `MainActivity`.
- Android bridge action names and alias groups are cataloged in
  `AndroidBridgeActionCatalog` with pure JVM tests; `MainActivity` checks the
  built router against the catalog during router installation.
- Android bridge routing from raw JS messages into registered native action
  handlers covered as pure JVM tests outside `MainActivity`.
- Absence of product-selected Stripe Terminal implementation from the
  open-source wrapper.
- Tap to Pay no-Stripe fallback envelopes covered as pure JVM tests outside
  `MainActivity`.

## Test priorities

1. Native implementation parity tests for action-specific response payloads
   beyond the profile-level fixtures in `docs/bridge-response-fixtures.json`.
2. Variant registry tests for every implemented app in `docs/app-variants.json`.
3. Pure settings, startup failover, and QR configuration tests for URL, HA,
   beacon, and device identity fields.
4. Structured unavailable-response tests for platform-specific features such as
   ARKit, RoomPlan, and optional Tap to Pay.
5. Simulator/emulator smoke tests for local demo page boot and JS bridge
   availability.
