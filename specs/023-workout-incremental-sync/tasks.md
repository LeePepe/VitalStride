# Tasks: HealthKit workout incremental sync successor

**Input**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/workout-fetch-contract.md`, `quickstart.md`
**Tracker parent**: MY-1481 / US1
**Implementation base**: `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`
**Layer context**: `Packages/HealthKitService/CONTEXT.md`
**Required gate**: Working directory `Packages/HealthKitService`; run `swift build && swift test`

## Format

The single executable successor row uses native Spec Kit syntax: `- [ ] Txxx [US#] Action with exact file paths`. There is no `[P]` row because production and tests form one transaction slice and are changed together.

## Historical Graph State

| Task | State | Relationship to successor |
|---|---|---|
| T023-001 | Delivered at `9dfa1fb4317935573c0a2f7c9283d13a40f01104` | Sole implementation dependency; precise provider contract is immutable input |
| T023-002 / MY-1483 | Cancelled after exhausted PR #423 delivery | Evidence only; not a dependency, base, workspace, candidate, or repair-budget predecessor |

## Phase 1: User Story 1 - Preserve and reconcile HealthKit workout history (P1)

**Goal**: Repeated reads and refreshes preserve the compatible workout baseline, apply UUID changes, and terminate every owner/coalesced/queued caller exactly once across cancellation, replay, and reset.

**Independent Test**: Through public `HealthDataCache` calls, accept A/c1, reject held B/c2, replay from durable c1, publish A+B/c2 before acceptance invocation and caller success, exercise owner/coalesced cancellation plus active/queued reset, and verify independent explicit-range lanes without HealthKit hardware or timing waits.

- [ ] T023-003 [US1] Implement the actor-owned workout request transaction, single remove-before-resume settlement funnel, default/range active-plus-queued provider lanes, compatible-baseline UUID reconciliation, deterministic legacy snapshot normalization/provenance, opaque candidate acceptance/replay, and the complete explicit-gate acceptance matrix in `Packages/HealthKitService/Sources/HealthKitService/HealthDataCache.swift` and `Packages/HealthKitService/Tests/HealthKitServiceTests/HealthWorkoutCacheTests.swift`

### T023-003 Metadata

| Field | Contract |
|---|---|
| Owning layer | HealthKitService / Service role |
| Context pointer | `Packages/HealthKitService/CONTEXT.md` L1 actor cache and whole-entry replacement red line |
| Slice | US1 |
| Blocking task | Delivered T023-001 only |
| Files in scope | Exactly `HealthDataCache.swift`; `HealthWorkoutCacheTests.swift` |
| Files/layers excluded | `HealthKitService.swift`; `HealthWorkoutRecord.swift`; `HealthWorkoutQueryContractTests.swift`; `PrivacyLoggingTests.swift`; AppUI; VitalModels; WatchConnectivity; workout-session/live-heart-rate/write/delete paths; all schemas/project files |
| Contract impact | Internal-only deepening of the existing public cache interface; consume the delivered prepared capability package-internally; no new public witness or call shape |
| Stable acceptance | AC-S1–AC-S5; AC-01–AC-13; FR-001–FR-020; SC-001–SC-009 |
| Exact verification | From `Packages/HealthKitService`: `swift build && swift test` plus two-file/prohibited-pattern audit |
| Evidence boundary | Start from exact current `main` base `e8cfc19…`; do not copy/adopt PR #423 or `a0d8…` content |

## Sequential Tracer Stages Within T023-003

Each changing behavior is observed RED against the exact base before its production path changes; an already-correct unchanged behavior may use strengthened characterization-GREEN. Never manufacture RED. Each stage retains all earlier tests.

### Stage A — Semantic cache foundation

- Cover A→empty changes, UUID add/update/delete, unknown deletion, duplicate IDs, deletion-wins, repeated changes, empty snapshot, and equal-time UUID order.
- Cover no/scoped baseline rejection, default-baseline coverage/provenance preservation, result-semantic baseline fallback, explicit-to-default rebuild, and wider-range coverage.
- Cover legacy default/scoped provenance, provider coverage preservation, missing explicit coverage as the exact request, missing default coverage as the 30-day window ending at captured request start, normalization, and deterministic sorting.
- Exit: AC-S3/AC-S4 and AC-01–AC-08 pass through public cache calls; whole-entry publication remains; no other file changed.

### Stage B — One settlement funnel

- Mandatory RED: owner plus coalesced callers expose independent/multiple completion under success, error, or cancellation.
- Implement actor-owned request/waiter registration and the sole remove-before-resume settlement operation.
- Cover success, provider failure fan-out, non-owner cancellation, owner cancellation with peers, and registration/cancellation races with bounded no-hang assertions.
- Exit: success/error/cancellation portions of AC-S1 plus AC-11 pass; AC-S1 remains partial until Stage C covers supersession and invalidation. There is one continuation-resume source site and no lock-owned waiter state, unsafe annotation, direct drain resume, or timing polling.

### Stage C — Real lane-domain lifecycle

- Mandatory RED: hold an active default request and an eligible same-generation queued successor, and prove the baseline cannot pump it before stale release. Separately hold old-generation active/queued work across reset and prove the baseline neither drains it correctly nor starts a newly registered post-reset request ahead of stale release.
- Implement default anchor lane plus independent exact-range lanes, active/queued request identities, same-generation logical retirement/pumping, and reset generation draining.
- Cover refresh supersession and owner cancellation pumping the eligible queued successor before stale release. Separately cover `invalidateWorkouts()`, `invalidateAll()`, and authorization revocation draining every old active/queued caller; only then register a fresh post-reset request and prove it starts before the old stale provider returns. Cover two independent range lanes.
- Exit: AC-S1 is complete after its Stage B→C coverage; AC-S2/AC-12 pass. Same-generation successor and fresh post-reset request each start before their stale release; late results cannot publish/accept/clear; no old queued work crosses reset and no continuation-holder provider turn exists.

### Stage D — Opaque acceptance and replay

- Mandatory RED: A/c1 plus query-complete B/c2 is rejected before cache acceptance and replay cannot prove the required order/boundaries.
- Use generation, semantic/range key, and request identity only. Publish the exact candidate entry, invoke matching acceptance synchronously, then settle success.
- Use distinct provider-started, query-complete, cache-acceptance, acceptance-invocation, durable-anchor, reset-successor, and stale-release gates.
- Cover c1 replay after rejection, A+B/c2 publication, invocation-before-owner/coalesced success, silent durable no-advance replay/resubmission, nil candidate, and legacy/explicit checkpoint absence. Reuse the reset gates to prove all old-generation terminal outcomes before a newly registered post-reset request starts ahead of stale release.
- Exit: AC-S5/AC-09/AC-10/AC-13 pass; no checkpoint decode/compare/timestamp/order, request-order currentness, or prior-checkpoint carry-forward.

### Stage E — Full matrix and layer gate

- Preserve current cache telemetry, filtering, no-provider empty result, error propagation, invalidation, authorization revocation, T023-001 provider contract, and existing privacy behavior.
- Run `swift build && swift test` from `Packages/HealthKitService`.
- Diff `e8cfc19…` to the candidate: exactly the two allowlisted paths.
- Audit both files for no `@unchecked Sendable`, `@preconcurrency`, `nonisolated(unsafe)`, `NSLock`, `Synchronization`, `Mutex`, `Task.sleep`, or `Task.yield`; audit production for one continuation resume site and no checkpoint decoding/ordering or continuation-holder lanes.
- No `xcodebuild`.

## Dependencies & Execution Order

```text
US1
├── T023-001  delivered provider request/result contract
└── T023-003  successor cache transaction + deterministic matrix
```

- The graph is acyclic and stays within one HealthKitService layer.
- T023-002 is not in the executable graph.
- T023-003 is one non-parallel task because every tracer changes the same production and test files.
- Team Lead schedules implementation only after exact-revision planning PASS; Planner does not assign an implementation role.

## Acceptance Mapping

| Requirement | Slice | Executable task/stage |
|---|---|---|
| AC-S3/AC-S4; AC-01–AC-08; FR-001–FR-012/020 | US1 | T023-003 Stage A |
| AC-S1/AC-11; FR-014/016/017 | US1 | T023-003 Stages B→C |
| AC-S2/AC-12; FR-008/009/014/018 | US1 | T023-003 Stage C |
| AC-S5/AC-09/AC-10/AC-13; FR-015/019 | US1 | T023-003 Stages C→D |
| FR-013; SC-001–SC-009; compatibility and removed-behavior audit | US1 | T023-003 Stage E |

## Required Verification

```bash
cd Packages/HealthKitService
swift build && swift test
```

`xcodebuild` is forbidden because the implementation diff is package-only.

## Implementation Handoff Notes

- Work only from the successor issue's fresh registered delivery workspace based on `e8cfc19…`; do not inspect/copy the evidence-only MY-1483 candidate during implementation.
- Test the deep module through its public cache interface. Internal transaction state is not a test interface.
- Keep prepared capability/conformance package-internal in `HealthDataCache.swift`; do not edit delivered T023-001 files.
- Treat checkpoint acceptance as ordered invocation, never as a durable-persistence receipt.
- If the two-file contract is infeasible from current main, stop with evidence for Team Lead/Planner rather than widening scope or reviving T023-002.
