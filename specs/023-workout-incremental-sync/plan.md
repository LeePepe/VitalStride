# Implementation Plan: HealthKit workout incremental sync successor

**Branch**: `agent/planner-lead/5fd462097a42`
**Date**: 2026-10-14
**Spec**: `specs/023-workout-incremental-sync/spec.md`
**Tracker parent**: MY-1481 / US1
**Successor task**: T023-003
**Immutable implementation base**: `main` at `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`

## Summary

Complete the workout-cache half of the delivered T023-001 provider contract as one deep `HealthDataCache` module. Keep the existing public cache and provider interface small while placing request registration, one remove-before-resume settlement funnel, lane-domain scheduling, semantic cache application, opaque checkpoint acceptance, and deterministic replay tests behind it. The successor is a new implementation path from current `main`; cancelled MY-1483, Draft PR #423, and its unpublished candidate are evidence only and contribute no code, branch, workspace, or dependency.

## Authority and Baseline

- Owner-delegated stop decision: Multica comment `01a138de-d88f-7206-a2de-82f3e45579ee`.
- Rejected implementation verdict: comment `01a13823-10b6-7ad5-baf8-aaef06c40e57`, exact SHA `a0d8a787cb1dff760595ba0dec029bbf5d493f20`.
- Prior accepted planning evidence: `67614a0c5d29450326a88c60d45e175416bba0aa`.
- Evidence-only states: Draft PR #423 head `7331f226ac496a67f80304e2453dfeebde060de8` and unpublished candidate `a0d8a787cb1dff760595ba0dec029bbf5d493f20`. They must not be adopted, copied, pushed, closed, reset, or used as the successor base.
- T023-001 is delivered on `main` at `9dfa1fb4317935573c0a2f7c9283d13a40f01104`; no later commit through the immutable successor base changes the relevant HealthKitService source/tests.

## Technical Context

**Language/Version**: Swift 6.0 with strict concurrency
**Primary Dependencies**: Foundation and OSLog; existing HealthKitService dependency on VitalModels remains unchanged
**Storage**: One process-memory workout cache plus the existing provider-owned device-local anchor; no new persistence
**Testing**: Swift Testing in `Packages/HealthKitService/Tests/HealthKitServiceTests`
**Target Platform**: iOS 18+, macOS 15+, watchOS 11+ package compatibility
**Owning layer**: HealthKitService / Service role
**Performance**: UUID reconciliation is linear in cached records plus changes; independent range lanes do not serialize behind the default anchor lane
**Constraints**: Whole-entry replacement, aggregate-only logging, opaque checkpoints, compiler-checked actor isolation, package-only verification, no xcodebuild
**Scale/Scope**: One implementation task, one layer, one production file, one test file

## Constitution Check — Before Design

| Gate | Result | Evidence |
|---|---|---|
| §I health privacy | PASS | Only cache orchestration and aggregate metadata are in scope; no health values enter logs or persistence. |
| §II strict concurrency | PASS | All mutable request/waiter/lane state remains actor-owned; unsafe Sendable annotations and lock-owned helpers are prohibited. |
| §III SPM-first | PASS | Both implementation paths are under `Packages/HealthKitService`; the exact gate is package-local Swift build/test. |
| Quality Bar A scope | PASS | The allowlist is exactly `HealthDataCache.swift` and `HealthWorkoutCacheTests.swift`. |
| Quality Bar C unsafe concurrency | PASS | The acceptance audit rejects unsafe annotations, mutex state, continuation-holder turns, and yield polling. |
| Quality Bar D errors | PASS | Failure/cancellation/reset settle callers and preserve the last accepted cache/anchor pair. |
| DoR contract | PASS | Scope, exclusions, public interface, AC-S1–AC-S5, verification, existing behavior, compatibility, and removed behavior are explicit. |

## Current-State Evidence at `e8cfc19…`

- `WorkoutDataProviding.fetchWorkouts(dateRange:)` is the unchanged public compatibility interface.
- T023-001 supplies prepared baseline, anchored-change, explicit-range, accept, and reject operations inside the package; the direct public service fetch is an anchor-free snapshot.
- `HealthDataCache` has one `WorkoutCacheEntry` with records and optional coverage, one global `workoutInFlightFetch`, and no provenance or checkpoint field.
- `workoutData(in:)` treats nil cached coverage as satisfying every request. `refreshWorkouts(in:)` cancels the global task.
- `performWorkoutFetch` reads only `WorkoutFetchResult.workouts`, drops deleted UUIDs, and whole-replaces the cache. It does not consume prepared semantics or checkpoint acceptance.
- The baseline cache tests use an `@unchecked Sendable` class, `NSLock`, and `Task.sleep`; they do not expose query completion, cache acceptance, durable-anchor state, successor pumping, or stale release as distinct gates.

## Module and Interface Design

### External interface: unchanged and deepened

The interface remains `workoutData(in:)`, `refreshWorkouts(in:)`, workout invalidation, telemetry, and the existing public `WorkoutDataProviding` fallback. Callers learn no transaction, lane, waiter, or checkpoint concepts. Tests exercise the same public cache interface with deterministic adapters.

The package-internal prepared capability is a real internal seam because it has two adapters: `HealthKitService` in production and the deterministic prepared provider in tests. Declare only the conformance/capability needed in the cache-owned file; do not widen a public witness or edit the delivered T023-001 files.

### Actor-owned transaction registry

`HealthDataCache` owns plain Sendable values for requests, waiters, provider tasks, prepared outcomes, and lanes. Registration associates one owner waiter and any later identical-read waiters with one request identity. All terminal events route to one settlement operation that removes a waiter before resuming it. Owner cancellation retires the request and settles attached peers; non-owner cancellation settles only that caller.

No helper object owns mutable state behind a lock. No caller, provider task, reset path, or lane-drain path resumes a continuation directly outside the settlement operation.

### Lane-domain lifecycle

- One default-anchor lane serializes baseline and anchored-change requests because both share provider-owned durable anchor state.
- Each exact explicit range is an independent anchor-free lane. Distinct range lanes may run concurrently and do not advance a global request generation merely by starting.
- A lane contains one active request identity and FIFO queued request identities. It never contains a continuation-holder turn object.
- Refresh supersession and owner cancellation retire affected same-generation requests, settle callers, cancel task handles, release logical ownership, and pump the next eligible queued successor without awaiting stale provider cooperation.
- Workout/global invalidation and authorization revocation advance generation, settle and remove every old active/queued request, and carry no queued request into the new generation. A request registered after reset may start immediately even while an old non-cooperative provider remains held.
- Generation changes represent reset/invalidation epochs. Semantic/range key plus request identity distinguish coalescing, supersession, and late results inside an epoch.

### Snapshot/change application

- Baseline and explicit-range snapshots are UUID-normalized, deterministically sorted, and whole-published with request/result-derived provenance.
- Legacy fallback is always a snapshot. Default requests produce default provenance; explicit requests produce scoped provenance. Provider-reported coverage is retained. Missing explicit coverage becomes the exact request range; missing default coverage becomes the existing 30-day window ending at the transaction's captured request-start instant.
- Anchored changes apply only to a compatible default baseline. No entry or a scoped entry rejects the changes and schedules or retries a default baseline instead.
- Compatible changes copy the prior UUID map, apply upserts, apply deletions last, sort, and publish one entry retaining the baseline coverage and provenance.
- Published results follow the prepared result's actual semantic. An intended anchored request that legitimately returns a baseline is published as a baseline.

### Opaque candidate acceptance and replay

For a current prepared baseline/change with a candidate, construct one entry containing that exact opaque candidate, publish it, synchronously invoke matching provider acceptance in the same actor turn, release the lane, and only then settle success. Nil-candidate prepared results, legacy fallback, and explicit-range snapshots publish checkpoint-absent entries and invoke no acceptance.

The cache never decodes, compares, timestamps, orders, or carries forward checkpoints. The `Void` acceptance is not a durable receipt. If durable state silently remains at c1 after A+B/c2 was accepted in memory, the next anchored query may replay B from c1 and resubmit c2 safely through idempotent UUID reconciliation.

### Deterministic verification seam

Test adapters expose separate gates/events for provider started, provider query complete, cache acceptance reached, acceptance invoked, durable anchor advanced, reset successor started, and stale provider released. Gate state is actor-owned or an equivalent compiler-checked Sendable value. Tests do not use sleeps, yield loops, locks, unsafe annotations, or internal cache state.

## Project Structure and Scope

### Planning artifacts

```text
specs/023-workout-incremental-sync/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── checklists/requirements.md
├── contracts/workout-fetch-contract.md
└── tasks.md
```

### Implementation allowlist

```text
Packages/HealthKitService/
├── Sources/HealthKitService/HealthDataCache.swift
└── Tests/HealthKitServiceTests/HealthWorkoutCacheTests.swift
```

### Explicit exclusions

- `HealthKitService.swift`, `HealthWorkoutRecord.swift`, `HealthWorkoutQueryContractTests.swift`, and `PrivacyLoggingTests.swift`
- AppUI, VitalModels/SwiftData/CloudKit schemas, WatchConnectivity, workout sessions, live heart rate, workout write/delete behavior, L2 workout persistence, observer/background sync, and refresh TTL policy
- PR #423, its branch/workspace/history, and unpublished candidate content

## Vertical Slice and Dependency Graph

| Slice | Outcome | Executable task | Dependency |
|---|---|---|---|
| US1 | Workout history reconciles and every concurrent caller terminates correctly across replay and reset | T023-003 | Delivered T023-001 only |

```text
US1
├── T023-001  delivered provider request/result contract
└── T023-003  successor cache transaction + deterministic matrix
```

Cancelled T023-002 / MY-1483 is historical evidence, not a blocking edge or repair-budget predecessor. T023-003 is the only new executable row and the only Multica successor.

## Verification Strategy

1. Capture current-main RED evidence for each changing behavior in AC-S1–AC-S5 before its production path changes; retain characterization-GREEN only for already-correct unchanged behavior. Never manufacture RED.
2. Test UUID reconciliation, default/scoped coverage and provenance, legacy fallback, nil candidate, prepared-result actual semantic, restart, error preservation, cancellation, supersession, invalidation, and authorization reset through public cache calls.
3. Use the distinct transaction gates to prove acceptance invocation before success and durable-lag replay. Prove same-generation retirement pumps an eligible queued successor before stale release; separately prove reset drains all old work and a newly registered post-reset request starts before old stale release. Every owner, coalesced waiter, and queued request receives one terminal outcome.
4. Run the full existing provider-contract and privacy suites unchanged as part of the package gate.
5. From `Packages/HealthKitService`, run:

```bash
swift build && swift test
```

6. Audit the cumulative implementation diff against `e8cfc19…`: exactly the two allowlisted files; no prohibited concurrency/checkpoint/timing patterns; no xcodebuild.

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Owner cancellation and provider completion race | Actor serialization plus remove-before-resume settlement; late terminal events find no waiter/request and become no-ops. |
| Default and explicit work block each other | Lane-domain identity separates the default anchor lane from independent exact-range lanes. |
| Stale non-cooperative provider blocks refresh/reset | Same-generation retirement pumps an eligible queued successor; reset drains old work and permits a newly registered post-reset request, both before stale return. |
| Anchored changes corrupt scoped/no baseline | Compatibility check rejects the delta and rebuilds a default baseline. |
| Legacy snapshots reintroduce duplicates or wrong provenance | One normalization/sort path plus request-derived default/scoped provenance. |
| Checkpoint is accepted ahead of cache or success is released early | Single actor turn publishes the candidate entry, invokes acceptance, then settles success; AC-S5 gates observe the order. |
| `Void` acceptance silently leaves durable anchor behind | Explicit durable-lag replay test proves c1 replay and idempotent c2 resubmission. |
| Planning drifts back to exhausted delivery state | Exact base is current `main`; PR #423 and `a0d8…` are explicit read-only exclusions. |

## Constitution Check — After Design

All pre-design gates remain PASS. The design keeps one existing layer and one deep public-cache module, preserves dependency direction and public call shapes, introduces no unsafe concurrency or privacy exception, and defines exact package-local evidence. No ADR or constitution change is required.

## Complexity Tracking

No constitution violation or cross-layer exception requires justification.
