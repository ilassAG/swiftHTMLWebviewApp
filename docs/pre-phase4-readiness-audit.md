# Pre-Phase-4 Readiness Audit

This audit records generic wrapper readiness before private product data moves
into private repositories. It intentionally does not list real products or
private paths.

## Current Readiness

| Area | Status | Evidence |
| --- | --- | --- |
| Bridge contract | Ready | `node tools/validate_contracts.js` validates actions, fixtures, docs, and platform catalogs |
| Private variant manifest | Ready | `docs/variant-manifest.schema.json` and `tools/variant_manifest_check.js` validate identity, startup, branding, features, bridge profiles, and verification commands |
| Generated handoff workspace | Ready | `tools/generate_variant_workspace.js` emits `VARIANT_WORKSPACE.json`, scaffold plan, commands, stop gate, decision template, private product AGENTS.md section, and review script |
| Product-footprint guardrail | Ready | `tools/private_product_footprint_audit.js` scans for non-generic product footprint |
| Android generic build | Ready | `android/app` builds and tests as the generic demo wrapper |

## Required Before Product Cleanup

For each private product:

1. `native/variant.json` exists and validates in the private repository.
2. Source icon and splash/loading assets exist under `native/assets/`.
3. `native/generated/` has been regenerated from the manifest.
4. The generated stop gate is reviewed.
5. The decision record is copied to a product-owned path and filled with CI,
   parity, and hardware-smoke evidence.
6. Private product build/test parity is green.
7. Device-smoke ownership is recorded for hardware-only flows.

Only after those items are complete should product-specific wrapper footprint be
removed or replaced by sanitized demo fixtures.
