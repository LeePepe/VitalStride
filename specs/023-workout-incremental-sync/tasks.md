# Tasks: HealthKit workout incremental sync

**Input**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/workout-fetch-contract.md`, `quickstart.md`
**Issue**: MY-1477
**Layer context**: `Packages/HealthKitService/CONTEXT.md`
**Required gate**: Working directory `Packages/HealthKitService`; run `swift build && swift test`

## Format

Each executable row uses native Spec Kit syntax: `- [ ] Txxx [US#] Action with exact file path`. There are no `[P]` rows because T023-002 consumes the provider contract from T023-001.

## Phase 1: User Story 1 - Preserve and reconcile HealthKit workout history (P1)

**Goal**: Repeated reads and refreshes retain the prior HealthKit workout baseline while applying additions, updates, deletions, explicit range snapshots, and invalidation safely.

**Independent Test**: Run a deterministic provider sequence through `HealthDataCache`; after baseline A, empty changes still return A, and the complete add/update/delete/idempotency/range/invalidation matrix passes without HealthKit hardware.

- [ ] T023-001 [US1] Define source-compatible baseline/changes/explicit-range request-result semantics in `Packages/HealthKitService/Sources/HealthKitService/HealthWorkoutRecord.swift` and `Packages/HealthKitService/Sources/HealthKitService/HealthKitService.swift`, with provider behavior tests in `Packages/HealthKitService/Tests/HealthKitServiceTests/HealthWorkoutQueryContractTests.swift`
- [ ] T023-002 [US1] Add the red regression matrix, then implement UUID reconciliation, concrete coverage/provenance, semantic-plus-range coalescing, deterministic ordering, and workout-generation commit guards in `Packages/HealthKitService/Sources/HealthKitService/HealthDataCache.swift` and `Packages/HealthKitService/Tests/HealthKitServiceTests/HealthWorkoutCacheTests.swift`; extend `Packages/HealthKitService/Tests/HealthKitServiceTests/PrivacyLoggingTests.swift` only if aggregate-only audit coverage is missing

### Task Metadata

| Field | T023-001 | T023-002 |
|---|---|---|
| Owning layer | HealthKitService | HealthKitService |
| Context pointer | `Packages/HealthKitService/CONTEXT.md` Types + Service roles | `Packages/HealthKitService/CONTEXT.md` Service role and L1 whole-entry red line |
| Slice | US1 | US1 |
| Blocking tasks | None | T023-001 |
| Files in scope | `HealthWorkoutRecord.swift`; `HealthKitService.swift`; new `HealthWorkoutQueryContractTests.swift` | `HealthDataCache.swift`; `HealthWorkoutCacheTests.swift`; `PrivacyLoggingTests.swift` only if needed |
| Files/layers excluded | `HealthDataCache.swift`; AppUI; VitalModels; WatchConnectivity; workout-session/write/delete flows | `HealthKitService.swift`; `HealthWorkoutRecord.swift`; AppUI; VitalModels; WatchConnectivity; workout-session/write/delete flows |
| Contract impact | Extend the provider/result seam to distinguish baseline snapshot, anchored changes, and explicit range while keeping existing public call shapes source-compatible | Consume the reviewed contract; no new public AppUI-facing API |
| Task-local acceptance | Provider tests prove anchor-free baseline, anchored changes, anchor-free explicit range, concrete snapshot coverage, anchor advancement only for baseline/changes, and compatibility of the existing direct call shape | Red-before-green evidence for A→empty; UUID add/update/delete; duplicate/idempotent changes; deletion wins; stable ordering; 30-day vs wider range; restart/invalidation rebuild; semantic/range coalescing isolation; late-result rejection; error preserves cache |
| Exact verification | From `Packages/HealthKitService`: `swift build && swift test` | From `Packages/HealthKitService`: `swift build && swift test` |

**Checkpoint**: US1 is complete only after T023-001 and T023-002 both pass the full package gate.

## Dependencies & Execution Order

```text
US1
└── T023-001  provider request/result contract
    └── T023-002  cache reconciliation + regression/concurrency matrix
```

- T023-001 has no implementation dependency.
- T023-002 is blocked on T023-001 because it consumes the precise response semantic and coverage.
- No task is parallelizable: the dependency is contractual even though the primary source files do not overlap.
- The graph is acyclic and stays entirely inside the HealthKitService layer.

## Acceptance Mapping

| Spec requirement / scenario | Vertical slice | Executable task(s) |
|---|---|---|
| AC 1-5; FR-003/004/005/012 | US1 | T023-002 |
| AC 6; FR-001/002/007/010/011 | US1 | T023-001 → T023-002 |
| AC 7-8; FR-002/006/008 | US1 | T023-001 → T023-002 |
| AC 9; FR-008/009/014 | US1 | T023-002 |
| FR-013 aggregate-only logging | US1 | T023-001, T023-002; existing privacy audit extended only if needed |
| SC-006 repository-declared SPM gate | US1 | T023-001, T023-002 |
| SC-007 scope boundary | US1 | T023-001, T023-002 diff audit |

## Required Verification

After each task and again after the assembled slice:

```bash
cd Packages/HealthKitService
swift build && swift test
```

`xcodebuild` is forbidden because all implementation files are under `Packages/HealthKitService`.

## Implementation Handoff Notes

- Tests in T023-002 must be written and observed failing against the old whole-replacement behavior before the production change is completed.
- Preserve whole-entry immutable assignment; do not mutate the published workout array in place.
- Do not add workout L2 persistence, TTL/observer refresh policy, UI changes, or broad sample-cache refactors.
- If an implementation fact makes the reviewed contract infeasible, stop and return evidence to Team Lead/Planner rather than widening scope.
