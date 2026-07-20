# Architecture Decision Records

This directory documents significant architecture and process decisions for VitalStride.

## Why ADRs

Decisions accumulate. Code shows *what* we built; ADRs explain *why*. When a future contributor (or our future self) wonders "why isn't this a single SwiftData store?" or "why don't we ship a watchOS standalone app?", the answer should be one file away.

Each ADR is a **one-time decision artifact** — once accepted, it captures the context at that moment. Decisions can be superseded by later ADRs, but the original is not edited (except for status, "Superseded by ADR-N").

## Format

We use a lightweight [MADR](https://adr.github.io/madr/)/[Nygard](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions) hybrid:

- **Status**: Proposed / Accepted / Deprecated / Superseded by ADR-N
- **Date**: when accepted (or revised)
- **Deciders**: who signed off
- **Context**: situation that prompted the decision
- **Decision**: what we chose, concretely
- **Consequences**: positive, negative, accepted trade-offs
- **Implementation references**: paths / files for grounding
- **Revisit triggers**: when this should be re-opened

Each ADR is its own file, numbered sequentially: `NNNN-kebab-case-title.md`.

## Index

| # | Title | Status | Date |
|---|-------|--------|------|
| [0001](0001-no-pr-workflow.md) | No-PR Git Workflow | Superseded by [0009](0009-pr-required-workflow.md) | 2026-06-16 |
| [0002](0002-defer-watchos-macos-feature-work.md) | Defer Dedicated watchOS / macOS Feature Work | Accepted (deferred) | 2026-06-18 |
| [0003](0003-healthkit-swiftdata-dual-data-source.md) | HealthKit + SwiftData Dual Data Source | Accepted | 2026-06-18 |
| [0004](0004-five-local-spm-packages.md) | Five Local SPM Packages | Accepted | 2026-06-18 |
| [0005](0005-ai-provider-chain.md) | AI ProviderChain (Apple Intelligence Primary, Zhipu Fallback) | Accepted | 2026-06-18 |
| [0006](0006-live-activity-for-rest-timer.md) | Live Activity for Rest Timer | Accepted | 2026-06-18 |
| [0007](0007-telemetrykit-standalone-spm-package.md) | TelemetryKit as Standalone SPM Package | Accepted | 2026-06-18 |
| [0008](0008-designkit-seed-based-design-system.md) | DesignKit — One Seed-Based Design System Package | Accepted | 2026-07-02 |
| [0009](0009-pr-required-workflow.md) | PR-Required Git Workflow (supersedes 0001) | Accepted | 2026-07-03 |
| [0010](0010-promote-watchos-live-heart-rate.md) | Promote watchOS Live Heart Rate (narrow ADR-0002 exception) | Accepted | 2026-07-19 |
| [0011](0011-telemetrydeck-first-production-provider.md) | TelemetryDeck as First Production Telemetry Provider | Accepted | 2026-07-20 |

## Writing a new ADR

1. Pick the next number.
2. Copy an existing ADR as a template — 0001 is the most complete example, 0002–0007 are more compact.
3. Keep it to ~80–150 lines. Long ADRs go unread.
4. Be concrete on consequences — both the upside and the cost you accepted.
5. Reference real file paths so the ADR stays anchored to code.
6. Add a row to this README.

## Backfilled ADRs

0002–0007 were written on 2026-06-18 to capture decisions that had already been made earlier in the project lifecycle but never written down. The 2026-06-17 retro (`~/Development/personal/vitalstride-retro/2026-06-17/`) surfaced this gap as an audit finding; this set of ADRs closes it.

When backfilling, the rule of thumb is: only document decisions that are still *load-bearing*. If something has been quietly reversed, write the reversal as a new ADR instead of backfilling the original.
