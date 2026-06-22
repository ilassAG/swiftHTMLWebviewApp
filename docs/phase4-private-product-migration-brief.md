# Phase 4 Private Product Migration Brief

Phase 4 is the stop point before moving product-specific native integration
material into private product repositories. This brief is generic and should not
name real apps or private repository paths.

## Current Stop Point

The wrapper can prepare private handoff workspaces without editing real iOS or
Android project files:

```sh
node path/to/swiftHTMLWebviewApp/tools/variant_manifest_check.js \
  --file native/variant.json
node path/to/swiftHTMLWebviewApp/tools/generate_variant_workspace.js \
  --variant native/variant.json \
  --output native/generated
```

The generated `native/generated/MIGRATION_STOP_GATE.json` is the required review
checklist before product data moves. Do not fill evidence into generated files
by hand; copy `native/generated/PHASE4_DECISION_RECORD_TEMPLATE.md` to a private
product path such as `native/phase4-migration-decision.md`.

## Recommended Integration Model

Use the open-source wrapper as the reusable upstream framework/tooling source,
not as a copied product fork.

```text
private-product/
  native/
    wrapper-version.txt
    variant.json
    assets/
      icon.png
      splash.png
    ios/
      overrides/
    android/
      overrides/
    generated/
```

The private product owns `native/variant.json`, assets, overrides, CI wiring,
release decisions, and device-smoke ownership. The open-source wrapper owns
bridge contracts, native capability implementations, optional module contracts,
validators, and generators.

## Decisions Needed Before Any Move

- Wrapper pinning: tag, branch, commit SHA, submodule, or build-script checkout.
- Generated output policy: committed generated files, CI-generated files, or a
  hybrid.
- Platform materialization strategy: generator creates full iOS/Android files,
  or generator emits plans plus product-owned overrides.
- Private asset source format and required dimensions.
- Signing policy: store only CI variable names, Keychain labels, or vault paths.
- Store metadata policy: where screenshots, descriptions, and privacy text live.
- CI gate: exact commands for manifest validation, generation, build, tests, and
  generated-drift checks.
- Manual/device smoke owners for camera, NFC, Bluetooth/beacons, printing, AR,
  RoomPlan, and Tap to Pay.
- Legacy bridge compatibility policy for public aliases and historical payload
  shapes.

## Per-Product Sequence

1. Confirm the private repository and native root path.
2. Add or update the private `native/` area from
   `docs/private-product-native-integration-template.md`.
3. Add `native/wrapper-version.txt`.
4. Add `native/variant.json` with identity, startup, branding, feature,
   bridge-profile, and verification data.
5. Add source icon and loading/splash assets under `native/assets/`.
6. Run `variant_manifest_check.js`.
7. Run `generate_variant_workspace.js`.
8. Review `native/generated/MIGRATION_STOP_GATE.json`.
9. Copy the generated decision-record template to a product-owned path and fill
   in target repo/path, CI, parity, and smoke-test owners.
10. Run `phase4_stop_gate_check.js --generated native/generated
    --decision-record native/phase4-migration-decision.md
    --require-filled-decision-record`.
11. Wire generated build/test commands into private product CI.
12. Prove platform build/test parity.
13. Run or assign hardware smoke tests.
14. Only after parity, replace any wrapper-owned product entries with generic
    demo variants or sanitized fixtures.
15. Tighten `docs/private-product-footprint-allowlist.json` after each removal.

## Minimum Parity Evidence

- Manifest validates.
- Generated workspace can be recreated deterministically.
- iOS Info.plist or Android manifest identity matches `native/variant.json`.
- App label/display name matches.
- Startup URL/provisioning defaults match.
- Enabled optional modules match.
- Platform-unavailable bridge actions match.
- Variant-boundary tests pass.
- Platform build passes.
- Device-smoke ownership is recorded for camera, NFC, Bluetooth/beacons,
  printing, AR, RoomPlan, Tap to Pay, and other hardware-only flows.

## Wrapper Cleanup After Parity

After a private product proves parity, remove only that product's
wrapper-owned footprint:

- Replace registry entries with generic examples or private-manifest pointers.
- Remove product-specific bundle/application IDs from wrapper platform files.
- Replace product icons/loading assets with generic demo assets.
- Replace product startup URLs and recovery copy with sanitized examples.
- Replace product-specific variant-boundary assertions with generic wrapper
  contract tests.
- Remove now-migrated product patterns from
  `docs/private-product-footprint-allowlist.json`.

Keep bridge compatibility aliases only if they are documented as public wrapper
API, not native app identity.
