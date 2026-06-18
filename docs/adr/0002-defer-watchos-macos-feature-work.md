# ADR-0002: Defer Dedicated watchOS / macOS Feature Work

**Status**: Accepted (deferred)
**Date**: 2026-06-18
**Deciders**: tianpli (project owner)
**Revisit**: 2026-09-01 OR when watchOS user feedback warrants

## Context

VitalStride ships three platforms (iOS / watchOS / macOS) sharing five SPM packages (`VitalModels`, `HealthKitService`, `AIService`, `VitalUI`, `TelemetryKit`).

The 2026-06-17 dev retro (covering the 16-day burst from 2026-06-02 → 06-17) showed extreme imbalance in platform-specific work:

| Platform | Commits in window | LOC touched | Days since last touch |
|---|---|---|---|
| iOS (`VitalStride/`) | 143 | 42,149 | 0.5 |
| macOS (`VitalStrideMac/`) | 18 | 318 | 7.3 |
| watchOS (`VitalStrideWatch Watch App/`) | <10 | ~50 | 10+ |

All watch/mac commits were W1 scaffolding work; no business features were added or refined on those platforms during W2 or W3.

The shared SPM packages did receive heavy churn (300 → 39.5K LOC across the window), so the watch/mac targets are not *abandoned* — they consume the same packages and inherit fixes — but they are **functionally frozen** at the level of platform-specific UX.

## Decision

For the current product phase:

1. **No new dedicated watch/mac feature work is planned.** Effort concentrates on the iOS app.
2. **CI / pre-push hook adds a smoke build** for both watch and mac schemes (build only, no test) so silent breakage from shared-package changes is caught immediately.
3. **Shared-package changes** continue to land normally; they implicitly cover watch/mac.
4. **No watchOS or macOS user-facing feature** appears in the active issue backlog. New issues touching watch/mac UX get triaged as "out of scope this iteration" unless explicitly promoted.

This is a temporary stance, not a permanent retirement. The platforms remain compilable and deployable.

## Consequences

### Positive
- Focused iOS iteration speed.
- Smaller cognitive load on issue-pipeline agents (one platform-of-record).
- Shared packages still earn their keep — they cover watch/mac for free.

### Negative
- Watch users see no product-level progress for the duration.
- macOS layout regressions in shared SwiftUI components may go unnoticed unless the smoke build catches them.
- Risk of bit-rot in watch-specific concurrency, lifecycle, or HealthKit code paths.

### Mitigations
- Smoke build catches API-level breakage.
- Every 14 days, evaluate whether watch/mac should be revived, retired (delete targets + ADR-update), or held.
- If a user reports a watch issue, escalate to active iteration regardless of this ADR.

## Revisit triggers

- 2026-09-01 calendar revisit.
- watch user feedback (any).
- iOS roadmap stabilizes and capacity frees up.
- Apple platform announcements affecting watchOS (new APIs, deprecations).
