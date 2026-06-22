# Open-Source Wrapper Migration Plan

This plan keeps `swiftHTMLWebviewApp` as a reusable open-source WebView wrapper
while private products own their product-specific native packaging.

## Wrapper Responsibilities

The open-source repository owns:

- iOS and Android WebView shells with generic demo identity.
- The JavaScript/native bridge contract.
- Shared bridge implementations and optional module interfaces.
- Generic demo HTML and sanitized examples.
- Private variant schemas, validators, generators, and stop-gate tooling.
- Tests for bridge behavior, platform parity, and generated scaffold plans.

The open-source repository must not permanently own:

- product names, bundle IDs, application IDs, icons, splash/loading assets;
- production URLs, tenant/customer configuration, signing references;
- store metadata, release channels, screenshots, or product-specific copy;
- private credentials, provisioning profiles, API keys, or Stripe secrets.

## Private Product Responsibilities

Each private product repository owns:

- `native/variant.json`
- `native/wrapper-version.txt`
- `native/assets/`
- `native/ios/overrides/`
- `native/android/overrides/`
- CI build/test commands and deploy notes.
- Hardware smoke-test ownership for camera, NFC, Bluetooth, printing, AR,
  RoomPlan, Tap to Pay, and other device-only flows.

## Variant Manifest Flow

From a private product repository:

```sh
WRAPPER_ROOT=/path/to/swiftHTMLWebviewApp
node "$WRAPPER_ROOT/tools/variant_manifest_check.js" \
  --file native/variant.json
node "$WRAPPER_ROOT/tools/generate_variant_workspace.js" \
  --variant native/variant.json \
  --output native/generated
node "$WRAPPER_ROOT/tools/phase4_stop_gate_check.js" \
  --generated native/generated
```

Copy `native/generated/PHASE4_DECISION_RECORD_TEMPLATE.md` to a product-owned
path before recording repository, CI, parity-test, and hardware-smoke evidence.
Do not edit generated files by hand.

## Public Documentation Rule

Public wrapper documentation should describe:

- supported features;
- JavaScript action names;
- request, response, and event payload shapes;
- platform availability;
- optional module setup;
- generic private product integration mechanics.

It should not list real private product names, local repo paths, real hosts,
production IDs, or business-specific implementation plans.
