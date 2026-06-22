# Private Product Wrapper Migration Plan

This plan keeps the open-source wrapper generic while private products own
their native identity, URLs, assets, signing references, release metadata, and
deployment decisions.

## Implementation Status

Status: implemented for the current migration wave on 2026-06-22.

- Active wrapper modules contain only generic demo identity and reusable bridge
  behavior.
- Product-specific native ownership moved to private product repositories.
- This document keeps the reusable process only; real app names and private
  repository paths must not be recorded here.

## Goals

- Keep the wrapper useful as a reusable framework/tooling source.
- Keep product identity and business decisions in private product repositories.
- Keep generated product workspaces outside the open-source source tree,
  preferably under a private repo's ignored `native/build/wrapper` directory.
- Keep all moves reversible until private build/test/device evidence is
  recorded.

## Migration Sequence

1. Freeze the public bridge contract with `node tools/validate_contracts.js`.
2. Create or update the private product `native/variant.json`.
3. Generate the private handoff workspace with
   `tools/generate_variant_workspace.js`.
4. Review `native/generated/MIGRATION_STOP_GATE.json`.
5. Copy the generated decision-record template into the private product repository and
   fill in CI, parity, and hardware-smoke evidence.
6. Build and test the generated private wrapper.
7. Remove any remaining product-specific wrapper footprint.
8. Tighten `docs/private-product-footprint-allowlist.json`.
9. Re-run the footprint audit, contract validation, and relevant platform
   builds/tests.

## Completion Criteria

- No real private product names, repo paths, hosts, bundle IDs, application IDs,
  icons, or splash/loading assets remain in public wrapper docs or active source.
- Public docs describe wrapper features and contracts only.
- Private product repositories independently build and test their generated or
  native wrappers.
- Private product `AGENTS.md` files state that real product identity must stay
  in the private product repository.
