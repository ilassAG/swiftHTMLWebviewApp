# Android Portrait Capture Parity Plan

## Goal

Implement Android `portraitCapture` as a native controller that matches the
iOS portrait/pass-photo controller as closely as Android camera and ML Kit APIs
allow. The public JavaScript request and response contract must stay shared
across iOS and Android so web apps can use the same demo controls and the same
bridge action on both platforms.

## Implementation Status

- iOS implements `portraitCapture` with a full-screen native camera controller,
  face-count validation, countdown reset, burst capture, variant selection,
  optional selfie background removal, face-centered square cropping, and
  landscape-safe selection UI.
- Android now routes `portraitCapture` to `AndroidPortraitCaptureController`
  in the default build instead of the unavailable fallback.
- Android accepts the same request fields and legacy aliases as iOS through
  `AndroidPortraitCaptureRequest`.
- Android uses CameraX preview, image analysis, and still capture; ML Kit Face
  Detection for face-count validation; ML Kit Selfie Segmentation for optional
  background removal; and Android views for the icon-only controller UI.
- Unit tests cover request parsing, response metadata, and the face-completeness
  geometry policy.
- `./gradlew testDebugUnitTest` and `./gradlew assembleDebug` pass.
- Sunmi V2 install/start smoke passed over ADB TCP. USB-C Honor device smoke is
  still blocked until the Honor appears in `adb devices -l` as `device`.

## Public Contract To Match

The Android implementation should accept the same fields as iOS:

- `action`: `portraitCapture`
- `requestId`: optional bridge correlation id
- `camera`: `front` or `back`, default `front`
- `requiredFaces` or legacy `amountFaces`: integer, clamp `1...8`, default `1`
- `countdownSeconds` or legacy `secondsDelay`: double, clamp `0...15`, default
  `3`
- `variationCount` or legacy `withVariation`: integer, clamp `1...8`, default
  `4`
- `captureIntervalMs`, `burstIntervalMs`, or `variationIntervalMs`: double,
  clamp `50...2000`, default `200`
- `removeBackground`: boolean/string boolean, default `false`
- `outputType`: `png` or `jpeg`; force PNG when transparent background removal
  requires alpha
- `background`: `transparent` or `color`
- `backgroundColor`: `#RRGGBB`, default `#FFFFFF`
- `cropTransparent`: boolean/string boolean, default `false`
- `crop`: `squareFaceCentered` or `none`, default `squareFaceCentered`
- `mirrorOutput` or `mirror`: boolean/string boolean, default `false`.
  Front-camera preview remains mirrored, but final output is unmirrored by
  default so text remains readable. Set `true` for mirror-style selfie output.

The default demo request should therefore capture four variants at approximately
`-200ms`, `0ms`, `+200ms`, and `+400ms` relative to the visible countdown zero.

## Expected User Experience

- Present a full-screen native Android controller over the WebView.
- Use camera preview as the main screen content.
- Keep the controller text-free except for numeric counters/status, matching the
  iOS requirement.
- Show only icon buttons: cancel, capture, retake, confirm, and variant
  selection affordances.
- Show current face count as `detected/required`.
- Enable capture only when the exact required face count is detected and every
  detected face is considered complete.
- Once the user taps capture, run the countdown.
- If the detected face count changes while the countdown is running, reset the
  countdown to the configured start value, then restart only after the face
  count is valid again.
- Start the burst one interval before zero when more than one variant is
  requested, so the first image lands before zero and the default sequence is
  `-200/0/+200/+400`.
- If the face count changes during burst capture, cancel the burst, discard
  variants, and return to the ready/countdown state.
- After capturing, show the variants in a responsive grid that works in portrait
  and landscape.
- Default-select the image closest to countdown zero. For the default Android
  offset list this should be variant index `1`.

## Android Architecture

### 1. Request Model

Add `AndroidPortraitCaptureRequest`.

Responsibilities:

- Parse all public request fields and legacy aliases.
- Clamp numeric values to the same ranges as iOS.
- Normalize boolean/string booleans.
- Normalize output format and camera direction.
- Expose helper values in milliseconds for Android scheduling.

Tests:

- Defaults match iOS.
- Legacy aliases parse.
- String booleans parse.
- Values clamp at the same boundaries as iOS.
- Transparent background removal forces PNG response format.

### 2. Response Builder

Extend `AndroidCaptureResponseBuilder` or add
`AndroidPortraitCaptureResponseBuilder`.

Response fields should align with the iOS `portraitCapture` result:

- `platform: "android"`
- `action: "portraitCapture"`
- `requestId`
- `success: true`
- `format`
- `imageData`
- `backgroundRemoved`
- `background`
- `backgroundColor`
- `cropped`
- `camera`
- `detectedFaces`
- `selectedIndex`
- `variantsCaptured`

Tests:

- Success envelope matches existing bridge style.
- Error envelope still uses `BridgeResponse.error` or equivalent shared helper.
- Response metadata is present for both background-removal and non-removal
  paths.

### 3. Native Controller

Add `AndroidPortraitCaptureController`.

Recommended implementation:

- Use CameraX `Preview`, `ImageAnalysis`, and `ImageCapture`.
- Reuse the lifecycle binding pattern from
  `ContinuousBarcodeScannerController`.
- Keep all camera/controller state out of `MainActivity`.
- Define a small listener interface:
  - `onPortraitCaptureResult(JSONObject payload)`
  - `onPortraitCaptureError(JSONObject payload)` or string error plus request
  - `onPortraitCaptureClosedByUser()`
- Let `MainActivity` only route permission and bridge calls.

State machine:

- `idle`
- `ready`
- `countingDown`
- `burstCapturing`
- `selectingVariant`
- `finishing`

Important rules:

- A new `start()` call while active should stop the old session first or return
  a structured busy error.
- Back/cancel button closes the native controller and returns a structured user
  cancellation error.
- `shutdown()` must unbind CameraX and close ML Kit clients.
- Orientation/layout changes should update overlay layout without losing the
  active controller state.

### 4. Face Detection

Add ML Kit Face Detection dependency:

```gradle
implementation 'com.google.mlkit:face-detection:16.1.7'
```

Use `ImageAnalysis` with `InputImage.fromMediaImage(image, rotationDegrees)`.

Face completeness policy should approximate iOS:

- Count only faces with enough bounds inside the frame.
- Reject faces touching or crossing frame edges.
- Reject very small faces.
- Prefer landmarks/classification when available to ensure eyes, nose/mouth
  signals exist.
- If one complete face is present and another partial face is visible, report
  an invalid count so `1/1` is not shown.

This is important for parity with the iOS behavior: when `requiredFaces = 1`,
the UI must not show `1/1` if another face is partially visible.

Tests:

- Pure JVM tests for face-count policy using synthetic normalized rectangles
  and landmark flags.
- Instrumented/manual validation for ML Kit real camera observations, because
  ML Kit face objects are not practical to construct directly in unit tests.

### 5. Countdown And Burst Timing

Use `Handler(Looper.getMainLooper())` for UI countdown timing and scheduled
capture callbacks.

Timing behavior:

- Visible countdown target is `now + countdownSeconds`.
- Pre-capture lead is `captureIntervalMs` when `variationCount > 1`, otherwise
  `0`.
- Begin burst when `remaining <= preCaptureLead`.
- Burst offsets are `0, interval, interval * 2, ...`.
- For default `variationCount = 4` and `captureIntervalMs = 200`, the burst
  begins around `-200ms` and captures `-200, 0, +200, +400`.
- Reset countdown to the configured full countdown if the detected face count
  changes while counting down.

Tests:

- Pure JVM scheduler/state-machine tests using an injectable clock.
- Verify reset-to-full-countdown after a face-count change.
- Verify default offset list.
- Verify default selected index is the image closest to zero.

### 6. Image Capture And Processing

Use CameraX `ImageCapture` for still images.

Processing pipeline:

1. Capture still bitmap for each burst variant.
2. Rotate according to EXIF/CameraX metadata; mirror final output only when
   `mirrorOutput = true`.
3. Re-run or reuse face bounds for the selected frame.
4. If `crop = squareFaceCentered`, crop a square image with the head/face
   centered.
5. If `removeBackground = true`, run ML Kit selfie segmentation.
6. Apply `background = transparent` or `background = color`.
7. If `cropTransparent = true`, trim transparent bounds after background
   removal.
8. Encode as PNG/JPEG according to the same format policy as iOS.
9. Return data URL through the bridge.

Implementation detail:

- The current Android `takePhoto` background-removal code in `MainActivity`
  should be extracted into a reusable helper such as
  `AndroidBackgroundRemovalProcessor` before portrait capture uses it.
- Keep bitmap manipulation in a testable utility, for example
  `AndroidPortraitImageProcessor`.

Tests:

- Pure JVM tests for format decisions and response metadata.
- Bitmap processor tests where feasible with small synthetic bitmaps.
- Manual device tests for actual CameraX orientation, mirroring, and
  segmentation quality.

### 7. Selection UI

Build the native selection overlay in Android views:

- Root `FrameLayout` full-screen over `MainActivity`.
- `PreviewView` fills the background.
- Bottom overlay with face counter, large numeric countdown, and icon-only
  capture button.
- Top-right icon-only cancel button.
- Selection overlay with thumbnail buttons and icon-only retake/confirm
  actions.
- In landscape, switch the grid to a horizontal layout with smaller thumbnails
  so buttons remain visible.

No visible explanatory text should be added inside the controller.

### 8. Bridge Wiring

MainActivity changes:

- Replace `sendPortraitCaptureUnavailable` route with
  `startPortraitCapture(message)`.
- Add request code for portrait camera permission or reuse the camera
  permission path carefully without colliding with `takePhoto`.
- Instantiate `AndroidPortraitCaptureController`.
- Forward lifecycle `onDestroy`/shutdown to the controller.
- Keep `AndroidUnavailableBridge.portraitCapture` only for builds that
  explicitly disable the feature, or remove it from the active route once the
  controller is default.

Bridge catalog:

- Keep `portraitCapture` in `AndroidBridgeActionCatalog`.
- Keep `docs/bridge-contract.json` action metadata stable unless response
  fields need documentation updates.

### 9. Demo Page

The current demo page already sends the desired fields. Android work should
reuse it unchanged unless a bug appears.

Required demo smoke path:

1. Open demo.
2. Set portrait capture defaults:
   - front camera
   - one face
   - countdown `3`
   - variants `4`
   - burst interval `200`
   - background removal enabled
   - square face-centered crop
3. Start `portraitCapture`.
4. Move a second/partial face into frame during countdown and verify countdown
   resets to `3`.
5. Capture, select a variant, and verify the web page receives the Android
   response payload.

### 10. Verification Plan

Run before device smoke:

```sh
cd android
./gradlew testDebugUnitTest
./gradlew assembleDebug
```

Run generic wrapper contract validation from repo root:

```sh
node tools/validate_contracts.js
```

Device smoke:

- Android emulator: basic launch, permission prompt, bridge response.
- Physical USB-C Honor phone: front/back camera, rotation, background removal,
  countdown reset, partial-face rejection, and final bridge response.
- Sunmi V2: install, launch, camera availability, landscape/portrait behavior.

Expected limitations to document:

- ML Kit selfie segmentation may differ from Apple's background removal.
- ML Kit face landmarks and Apple Vision landmarks will not be pixel-identical.
- Image quality may differ because iOS uses AVFoundation and Android uses
  CameraX.

## Implementation Order

1. Add `AndroidPortraitCaptureRequest` and unit tests.
2. Add portrait response builder tests.
3. Extract Android background-removal/image-encoding helpers out of
   `MainActivity`.
4. Add CameraX portrait controller skeleton with preview, cancel, permission,
   and structured cancellation/error responses.
5. Add ML Kit face detection and face-completeness policy with tests.
6. Add countdown reset and burst timing state machine with tests.
7. Add still image capture and variant storage.
8. Add face-centered square crop.
9. Add background removal/color/transparent processing for selected image.
10. Add variant selection UI, including landscape layout.
11. Wire `MainActivity` bridge route from unavailable to controller.
12. Run Android unit tests and debug build.
13. Run emulator/device smoke.
14. Update `docs/android.md`, `docs/native-bridge.md`, and README if the
    Android feature graduates from planned to implemented.

## Stop Gates

Do not mark Android `portraitCapture` as implemented until all of these are
true:

- `portraitCapture` no longer returns `AndroidUnavailableBridge` in the default
  Android build.
- Android accepts all iOS request fields and aliases.
- Countdown reset behavior matches iOS.
- Default burst timing matches `-200/0/+200/+400`.
- One complete face plus one partial face is not accepted as `1/1`.
- Portrait and landscape layouts are usable.
- Unit tests cover request parsing, response shape, state timing, and face
  completeness policy.
- `./gradlew testDebugUnitTest` and `./gradlew assembleDebug` pass.
- A real Android device smoke test has been recorded, starting with the USB-C
  Honor phone when `adb devices -l` reports it as `device`.
