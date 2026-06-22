# private product Native Integration Template

Use this template inside each private product repository before generated
native wrapper files are created or updated. It keeps product-owned data in the
private product repository and keeps this open-source wrapper generic.

## Expected Repository Shape

```text
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
    .gitkeep
```

`native/generated/` is replaceable generated output. Do not edit files there by
hand. Change `native/variant.json`, an override file, or the upstream wrapper
tooling instead.

## Required Files

- `native/wrapper-version.txt`: pinned wrapper tag, branch, or commit.
- `native/variant.json`: private app identity, startup, branding, feature, and
  verification manifest.
- `native/assets/icon.png`: source icon owned by the private product.
- `native/assets/splash.png`: loading/splash image owned by the private product.
- `native/generated/`: generated handoff or platform workspace output.

## Manifest Validation

From the private product repository:

```sh
WRAPPER_ROOT=/path/to/swiftHTMLWebviewApp
node "$WRAPPER_ROOT/tools/variant_manifest_check.js" \
  --file native/variant.json
```

To generate the current safe handoff workspace:

```sh
WRAPPER_ROOT=/path/to/swiftHTMLWebviewApp
node "$WRAPPER_ROOT/tools/generate_variant_workspace.js" \
  --variant native/variant.json \
  --output native/generated
node "$WRAPPER_ROOT/tools/phase4_stop_gate_check.js" \
  --generated native/generated
```

This command currently stops before moving existing private product logic or directly
editing real iOS/Android project files. Review the generated handoff before any
platform files are created or replaced. Use
`native/generated/MIGRATION_STOP_GATE.json` as the generated checklist before
Phase 4 starts. Copy
`native/generated/PHASE4_DECISION_RECORD_TEMPLATE.md` to a private-product-owned path
such as `native/phase4-migration-decision.md` before recording the target
repository, CI, parity-test, and hardware-smoke evidence.
After copying the decision record, validate that it is outside generated output:

```sh
WRAPPER_ROOT=/path/to/swiftHTMLWebviewApp
node "$WRAPPER_ROOT/tools/phase4_stop_gate_check.js" \
  --generated native/generated \
  --decision-record native/phase4-migration-decision.md
```

Before product data moves or wrapper cleanup starts, require the filled record:

```sh
WRAPPER_ROOT=/path/to/swiftHTMLWebviewApp
node "$WRAPPER_ROOT/tools/phase4_stop_gate_check.js" \
  --generated native/generated \
  --decision-record native/phase4-migration-decision.md \
  --require-filled-decision-record
```

## AGENTS.md Native Section

Add a section like this to the private product `AGENTS.md`:

````md
## Native Wrapper Integration

This repository owns the app-specific native variant data for this private product:

- `native/variant.json`
- `native/wrapper-version.txt`
- `native/assets/`
- `native/ios/overrides/`
- `native/android/overrides/`

Do not edit files under `native/generated/` by hand. They are generated from
`native/variant.json`, override files, and the pinned wrapper version.

Product-specific native identity, startup URLs, icons, splash/loading assets,
signing references, store metadata, and release-channel decisions belong in
this repository, not in the open-source wrapper repository.

Do not commit secrets, signing keys, provisioning profiles, Stripe keys, or
private API tokens. Store only references to CI variables, Keychain entries, or
secure vault paths.

After changing native variant data, run:

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

Then run the generated build/test commands from
`native/generated/commands.json`.

Before moving existing private product logic or assets, review
`native/generated/MIGRATION_STOP_GATE.json`, copy
`native/generated/PHASE4_DECISION_RECORD_TEMPLATE.md` to a private-product-owned path,
and capture the required repository, CI, parity-test, and hardware-smoke
evidence there.
````

## Migration Review Checklist

- `native/variant.json` validates.
- `native/generated/MIGRATION_STOP_GATE.json` has been reviewed.
- `phase4_stop_gate_check.js --generated native/generated` passes for the
  generated handoff.
- `native/generated/PHASE4_DECISION_RECORD_TEMPLATE.md` has been copied to a
  private-product-owned path before evidence is filled in.
- `phase4_stop_gate_check.js --generated native/generated --decision-record
  native/phase4-migration-decision.md --require-filled-decision-record` passes
  before product data moves or wrapper cleanup starts.
- Product name and display labels match the private product.
- Bundle identifier and Android application ID match the target stores.
- Startup URL/provisioning policy has no embedded secret.
- Icon and loading/splash assets exist under `native/assets/`.
- Required and optional native capabilities match the product scope.
- Generated unavailable bridge actions match the platform contract.
- Generated build/test commands are wired into private product CI.
- Hardware-dependent flows have a manual or device-smoke test owner.
