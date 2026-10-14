# Quickstart: T023-003 successor implementation and verification

## Preconditions

- Use the successor issue's registered delivery workspace from exact base `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`.
- Read `.specify/memory/constitution.md`, `AGENTS.md`, `Packages/CONTEXT.md`, `Packages/HealthKitService/CONTEXT.md`, and this feature artifact set.
- T023-001 is the only dependency and is already delivered. Do not edit its owned files.
- Keep the implementation diff to `HealthDataCache.swift` and `HealthWorkoutCacheTests.swift`.
- Treat MY-1483, PR #423, and candidate `a0d8…` as read-only historical evidence; do not adopt or copy them.
- Do not run `xcodebuild`; this is package-only work.

## Execution Order

1. Record exact-base identity and current two-file contents.
2. For each changing tracer in tasks.md Stages A–D, capture RED before the relevant production change, then minimal GREEN and all prior regressions. Use characterization-GREEN only for already-correct unchanged paths.
3. Build semantic cache application and deterministic legacy normalization.
4. Replace caller completion with one actor-owned remove-before-resume settlement funnel.
5. Add default/range active-plus-queued lanes: pump eligible same-generation successors on retirement, but drain all old work on reset before admitting a newly registered post-reset request.
6. Add opaque candidate publication/acceptance plus rejection and durable-lag replay.
7. Run the complete public-cache matrix, package gate, two-file diff audit, and prohibited-pattern audit.

## Required Entry Acceptance Tests

- **AC-S1**: one settlement funnel for success, failure, cancellation, supersession, and invalidation; owner/non-owner semantics and exactly-once outcomes.
- **AC-S2**: a real default active/queued lane and independent explicit-range lanes; same-generation retirement pumps eligible queued work, while reset drains all old work and admits only a newly registered post-reset request, both without waiting for stale release.
- **AC-S3**: anchored changes require a compatible default baseline and preserve its coverage/provenance.
- **AC-S4**: legacy snapshots are UUID-normalized and sorted with request-derived default/scoped provenance; provider coverage is preserved, otherwise coverage is the exact explicit range or the 30-day default ending at captured request start.
- **AC-S5**: distinct query-complete, cache-acceptance, durable-anchor, reset-successor, and release gates prove replay, every old-generation owner/coalesced/queued terminal outcome, and fresh post-reset start before old stale release.

## Required Regression Matrix

- Baseline A → empty changes → A remains.
- Baseline A → add B + delete A → only B.
- Existing UUID → changed record → one updated record.
- Duplicate UUID snapshots/deltas normalize deterministically; deletion wins.
- Repeated changes are idempotent; equal timestamps use UUID order.
- Empty/no/scoped cache plus anchored changes rebuilds a default baseline.
- Default coverage does not satisfy a wider range; scoped range does not satisfy a later default request.
- Legacy default/scoped snapshots preserve provider coverage; when missing, they use the exact scoped request or the existing 30-day default window ending at that transaction's captured request-start instant. They carry no candidate.
- Different explicit ranges progress independently; baseline and anchored changes serialize through the default lane.
- Non-owner cancellation preserves peers; owner cancellation, provider error, supersession, and reset settle every attached waiter once.
- Supersession/owner retirement starts an eligible same-generation queued successor before stale release.
- Reset settles and removes every old active/queued request; after that, a newly registered post-reset request starts before old stale release. Stale return cannot publish, accept, or clear.
- A/c1 → held B/c2 rejection → c1 replay → A+B/c2 publication → matching acceptance before caller success.
- Silent acceptance no-advance retains durable c1 and causes another safe B/c2 replay/resubmission.
- Nil-candidate prepared baseline/change publishes valid checkpoint-absent state with no acceptance.
- Existing telemetry, filtering, no-provider, error, invalidation, authorization-revocation, provider-contract, and privacy behavior remains green.

## Deterministic Gate Rules

The test provider must expose distinct provider-started, query-complete, cache-acceptance, acceptance-invocation, durable-anchor, reset-successor, and stale-release gates/events. Holding inside the provider until release does not prove query-complete/cache-acceptance separation. Gate state must be actor-owned or equivalently compiler-checked Sendable; do not use locks, sleeps, or yield polling.

## Required Layer Gate

Working directory: `Packages/HealthKitService`

```bash
swift build && swift test
```

Acceptance requires exit code 0 for both commands. Do not substitute an AppUI build or simulator test.

## Final Audit

- Cumulative diff from `e8cfc19…` is exactly the two allowlisted files.
- Public `workoutData(in:)`, `refreshWorkouts(in:)`, `fetchWorkouts(dateRange:)`, and `WorkoutDataProviding` call shapes remain source-compatible.
- T023-001 source and provider-contract tests are unchanged.
- Production has one continuation-resume site behind remove-before-resume settlement.
- Default and range lanes contain request identities, not continuation-holder turns.
- Anchored changes cannot apply to missing/scoped state and cannot replace baseline coverage/provenance.
- Legacy snapshots normalize/sort and derive default/scoped provenance from the request.
- Candidate checkpoints remain opaque; nil/legacy/explicit results invoke no acceptance.
- No health values/details enter logs.
- Neither file contains unsafe concurrency annotations, lock/mutex state, sleep/yield coordination, or request/checkpoint ordering shortcuts.
