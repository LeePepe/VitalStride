# Implementation Plan: HealthKit workout incremental sync

**Branch**: `agent/planner-lead/afa3d12e2f19`
**Date**: 2026-08-25
**Spec**: `specs/023-workout-incremental-sync/spec.md`
**Issue**: MY-1477

## Summary

Repair the workout cache/provider seam inside the `HealthKitService` layer. The provider will distinguish an authoritative snapshot with concrete coverage from anchored changes. `HealthDataCache` will rebuild a baseline when no compatible snapshot exists, reconcile changes by UUID with deletion-wins semantics, key coalescing by query shape/range, and guard commits with a workout-specific generation. Public cache and direct-service entry points remain source-compatible.

## Technical Context

**Language/Version**: Swift 6.0 with strict concurrency
**Primary Dependencies**: Foundation, HealthKit, OSLog; local dependency on VitalModels remains unchanged
**Storage**: Process-memory workout cache plus existing device-local HealthKit anchor; no new persistence
**Testing**: Swift Testing in `Packages/HealthKitService/Tests/HealthKitServiceTests`
**Target Platform**: iOS 18+, macOS 15+, watchOS 11+ package compatibility
**Project Type**: Local Swift package in a multiplatform application
**Performance Goals**: UUID reconciliation is linear in cached records plus changes; no duplicate provider request for the same semantic key
**Constraints**: Health values never enter logs; whole cache entry replacement; Swift 6 actor safety; no xcodebuild for package-only work
**Scale/Scope**: One package layer, three production files, two primary test files

## Constitution Check — Before Design

| Gate | Result | Evidence |
|---|---|---|
| §I health privacy | PASS | Plan changes cache semantics only; aggregate query type/count/duration logs are allowed. |
| §II strict concurrency | PASS | Actor isolation remains the synchronization boundary; workout generation handles actor reentrancy without unsafe annotations. |
| §III SPM-first | PASS | All production work is under `Packages/HealthKitService`; verification is package-local Swift build/test only. |
| Quality Bar A scope | PASS | AppUI, models, WatchConnectivity, and generated project files are excluded. |
| Quality Bar C unsafe concurrency | PASS | No `@preconcurrency`, `nonisolated(unsafe)`, or new `@unchecked Sendable` is planned. |
| Quality Bar D errors | PASS | Failed/cancelled fetches preserve the last valid cache and retain existing thrown-error behavior. |
| DoR contract | PASS | Scope, exclusions, public signatures, measurable acceptance, task dependencies, and exact verification are specified. |

## Current-State Evidence

- `HealthKitService.fetchWorkouts(dateRange:)` uses a stored anchor only for the default (`nil`) request; an explicit date range sends `anchor: nil`.
- `WorkoutFetchResult` already contains workouts and deleted UUIDs but does not identify snapshot versus changes.
- `HealthDataCache.performWorkoutFetch` currently extracts only `.workouts`, discards deleted UUIDs, and replaces the whole cache with the returned additions.
- The default first-sync request fetches 30 days but stores `coveredRange: nil`; `coversRange(nil, requested:)` then claims every requested range is covered.
- The workout cache is process-memory-only while the anchor persists, so a new cache process can receive a delta without a baseline.
- One global workout in-flight task can currently coalesce unrelated ranges.

Details and alternatives are recorded in `research.md`.

## Design

### Provider contract

Add an explicit provider-level request semantic for:

1. default-window baseline snapshot;
2. anchored changes from the persisted workout anchor;
3. explicit-range snapshot.

The result identifies snapshot versus changes. Snapshots report concrete coverage. Changes retain UUID upserts and deleted UUIDs. Existing public direct-service and cache APIs stay source-compatible through compatibility defaults; no implementation-level signature is prescribed here.

### Cache state transition

- Default read with no compatible cache → request baseline snapshot and establish provenance/coverage.
- Default refresh with a compatible baseline → request anchored changes.
- Explicit range read/refresh not covered by the current entry → request an anchor-free snapshot for that range.
- Snapshot → replace the single workout cache entry with the authoritative records and coverage.
- Changes → copy current records into a UUID map, apply upserts, apply deletions last, deterministically sort, then assign one new immutable entry with unchanged coverage.
- Incompatible query shape → rebuild rather than treating scoped data as global or vice versa.

### Concurrency and invalidation

- Key in-flight fetches by request semantic and date range.
- Capture a workout-specific generation before awaiting the provider.
- `invalidateWorkouts()` and `invalidateAll()` bump the workout generation and cancel/clear workout tasks.
- A fetch commits only if its generation and semantic target remain current; cancellation is not treated as sufficient protection.
- Errors and stale completions leave the last valid entry unchanged.

### Ordering

All published and returned workout arrays are ordered by `startDate` descending; equal timestamps use UUID as a deterministic tie-breaker. Deletions are applied after upserts, so deletion wins if one response carries both for the same UUID.

## Project Structure

### Planning artifacts

```text
specs/023-workout-incremental-sync/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── checklists/
│   └── requirements.md
├── contracts/
│   └── workout-fetch-contract.md
└── tasks.md
```

### Implementation scope

```text
Packages/HealthKitService/
├── Sources/HealthKitService/
│   ├── HealthDataCache.swift
│   ├── HealthKitService.swift
│   └── HealthWorkoutRecord.swift
└── Tests/HealthKitServiceTests/
    ├── HealthWorkoutCacheTests.swift
    ├── HealthWorkoutQueryContractTests.swift   # new if needed
    └── PrivacyLoggingTests.swift                # only if audit coverage changes
```

**Structure Decision**: Keep the fix in the existing HealthKitService Types/Service roles. Do not add a package, AppUI adapter, or workout L2 model.

## Files in Scope

- `Packages/HealthKitService/Sources/HealthKitService/HealthDataCache.swift`
- `Packages/HealthKitService/Sources/HealthKitService/HealthKitService.swift`
- `Packages/HealthKitService/Sources/HealthKitService/HealthWorkoutRecord.swift`
- `Packages/HealthKitService/Tests/HealthKitServiceTests/HealthWorkoutCacheTests.swift`
- `Packages/HealthKitService/Tests/HealthKitServiceTests/HealthWorkoutQueryContractTests.swift` (new if needed)
- `Packages/HealthKitService/Tests/HealthKitServiceTests/PrivacyLoggingTests.swift` only for aggregate-only audit coverage

## Files NOT to Touch

- `VitalStride/**`, including `WorkoutListView.swift`
- `Packages/VitalModels/**` and all SwiftData/CloudKit schemas
- WorkoutSessionManager, WatchConnectivity, and live heart-rate files
- HealthKit workout write/delete flows except consuming anchored deleted IDs
- `project.yml` and `VitalStride.xcodeproj/**`

## Public Interface Contract

- Keep `HealthDataCache.workoutData(in:)` source-compatible.
- Keep `HealthDataCache.refreshWorkouts(in:)` source-compatible.
- Keep `HealthKitService.fetchWorkouts(dateRange:)` source-compatible.
- Extend only the provider/result seam needed to express baseline, changes, explicit range, and coverage; compatibility behavior is locked by tests.

## Vertical Slice and Dependency Graph

| Slice | Outcome | Tasks | Upstream slices |
|---|---|---|---|
| US1 | Watch/HealthKit workout history survives empty deltas and reconciles additions, updates, deletions, range snapshots, and invalidation | T023-001 → T023-002 | None |

Task metadata and the acceptance mapping are in `tasks.md`.

## Verification Strategy

1. Provider contract tests prove baseline versus anchored versus explicit-range query behavior and anchor advancement.
2. Cache tests perform the required red-green regression sequence and the full merge/range/concurrency/invalidation matrix.
3. Existing HealthKitService tests protect public compatibility and privacy logging.
4. Required layer gate, from `Packages/HealthKitService`:

```bash
swift build && swift test
```

No `xcodebuild` is permitted because implementation scope is package-only.

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Persisted anchor outlives in-memory baseline | Empty/incompatible cache forces baseline and re-establishes the anchor. |
| Range snapshot is treated as a global baseline | Result carries semantic/coverage; cache provenance controls compatibility. |
| Late actor-reentrant task overwrites newer state | Workout-specific generation guards every post-await commit. |
| Different ranges share an in-flight result | Coalescing key includes semantic and range. |
| Duplicate or unstable projection | UUID map plus explicit sort/tie-breaker. |
| Logging leaks workout details | Keep only aggregate query type/count/duration and extend existing privacy audit only if needed. |
| Scope grows into workout persistence/refresh policy | L2 workout persistence, observer sync, and TTL remain explicit non-goals. |

## Constitution Check — After Design

All pre-design gates remain PASS. The design uses one existing layer, preserves dependency direction and public call shapes, adds no unsafe concurrency exception, and defines the exact package-local verification. No constitution exception or ADR is required.

## Complexity Tracking

No constitution violations require justification.
