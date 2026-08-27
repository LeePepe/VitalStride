# ADR-0019: Formal RepoInfra Change-Owner Layer

**Status**: Accepted
**Date**: 2026-08-23
**Decider**: tianpli

## Context

ADR-0018 formalized AppUI and Prototype but left tracked CI workflows, hooks, tooling scripts,
release automation, and repository policy/config files outside the layer model. Treating all
non-product files as one implicit bucket would also incorrectly make governance, specifications,
design evidence, generated output, caches, logs, and local secrets schedulable infrastructure.

The existing frontmatter check validated declared layers but did not fail when a new tracked path
was unmapped or owned by two layers.

## Decision

- Add `RepoInfra` as a dependency-free change-owner layer for `.github/**`, `scripts/**` (including
  tooling tests), `fastlane/**`, repository lint/security/git config, and executable/configurable
  spec-kit paths under `.specify`.
- Keep `project.yml` in AppUI because it is the XcodeGen target source of truth. Classify the derived
  `VitalStride.xcodeproj/**` as a generated exclusion rather than layer content.
- Route progressively from top-level `CONTEXT.md`: `Packages/**` descends through
  `Packages/CONTEXT.md`, while AppUI, Prototype, and RepoInfra descend directly to leaf contexts.
  Each context owns only its local routes or leaf facts; no central registry duplicates the tree.
- Declare governance/agent documentation, specs, design evidence, and general documentation as
  support exclusions. Declare build/cache/log/local-secret/signing paths as generated/local
  exclusions. Exclusions carve files out before owner matching.
- Make tracked schedulable coverage exhaustive and non-overlapping. The checker fails closed for
  unmapped files and multiple owners, with regression tests for both negative cases.
- Keep gate speed independent from ownership. RepoInfra has a fast syntax/contract/test command;
  heavy AppUI verification remains in required CI.
- Preserve the pipeline boundary: AI Reviewer reviews content only; PR Manager owns CI, build,
  test, lint, hook, merge-readiness, and shipping state.

## Consequences

- Repository automation changes have a formal owner, red-lines, and focused validation command.
- New tracked tooling cannot silently land outside the formal layer universe.
- Support and generated artifacts remain intentionally unschedulable and visibly classified.
- Adding a package normally changes only `Packages/CONTEXT.md` and the new leaf context. Root routes
  change only when a new outer scope is introduced; fail-closed checks make either maintenance
  immediate.

## Implementation references

- `RepoInfra/CONTEXT.md`
- `scripts/check-frontmatter.sh`
- `scripts/lib/layer_coverage.py`
- `scripts/test-repoinfra.sh`
- `scripts/tests/test_layer_path_coverage.py`
