# Private Product Migration Inventory

This inventory describes which kinds of product-specific material must stay out
of the open-source wrapper. It intentionally uses neutral labels only. Real app
names, bundle identifiers, application IDs, URLs, icons, splash screens, signing
references, store metadata, and release decisions belong in private product
repositories.

## Categories

- **Generic wrapper source**: reusable bridge implementations, platform
  unavailable responses, demo HTML, sanitized examples, schemas, validators,
  generators, and tests.
- **Private product source**: native app identity, production URLs, branded
  assets, store metadata, signing references, product-selected optional modules,
  and product-specific build/deploy instructions.
- **Compatibility surface**: public bridge action names and legacy aliases that
  must remain stable for existing web apps. These are wrapper API, not private
  product identity.

## Wrapper-Owned Content

The open-source repository may contain:

- iOS and Android WebView shells with generic demo identity.
- The JavaScript/native bridge contract and response fixtures.
- Optional native modules that build without private credentials or product
  dependencies.
- Sanitized private-product manifest examples.
- Variant manifest schema, validators, generated handoff tooling, and stop-gate
  checks.
- Tests that prove generic bridge behavior, platform parity, unavailable
  responses, and generated workspace structure.

## Private-Product-Owned Content

Each private product repository should own:

- `native/variant.json`
- `native/wrapper-version.txt`
- `native/assets/`
- `native/ios/overrides/`
- `native/android/overrides/`
- `native/phase4-migration-decision.md`
- Build, test, deploy, and device-smoke commands for its generated wrapper.
- Product-specific `AGENTS.md` instructions that prohibit editing generated
  wrapper output by hand.

## Known Compatibility Decisions

- Legacy continuous scanner aliases remain part of the public bridge so older
  web apps can keep using their existing JavaScript action names.
- Legacy overlay payload normalization remains a generic compatibility adapter
  in the AR overlay bridge. New integrations should use the generic `items` and
  `lines` schema.
- Private product repositories choose optional modules such as Tap to Pay,
  printer integrations, NFC workflows, AR flows, and deployment defaults through
  their own manifests and overrides.

## Review Rule

If a document or source file starts to mention a real product name, real host,
real bundle/application ID, private repo path, signing reference, or release
channel, move that information to the private product repository instead. The
wrapper should describe capabilities and integration contracts, not individual
business apps.
