# Phase 4 Target Repository Selection

This document describes how to select a private target repository without
recording real repository names or local paths in the open-source wrapper.

## Selection Criteria

Pick exactly one owner per private product/platform before moving native
integration data. A good target repository:

- is already the authoritative product/web/backend repository;
- has a clean enough worktree to review native-wrapper changes;
- can own `native/variant.json`, assets, overrides, CI commands, and deploy
  documentation;
- can run or delegate device-smoke tests for hardware-only features;
- has `AGENTS.md` instructions that keep product identity out of the
  open-source wrapper.

## Decision Matrix Template

Use this template in the private planning context, not in this open-source
repository:

| Product | Platform | Target repository | Native root | Confidence | Required evidence |
| --- | --- | --- | --- | --- | --- |
| Product A | iOS | private | `native/` | TBD | build, tests, device smoke |
| Product A | Android | private | `native/` | TBD | build, tests, device smoke |

## Stop Rule

Do not edit any private repository until the target repo/path matrix is filled
in outside the open-source wrapper and reviewed with the product owner.

The open-source wrapper may continue improving validators, generators,
documentation, tests, and footprint audits while those private decisions are
pending.
