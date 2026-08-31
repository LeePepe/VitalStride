# Tasks: HealthKit workout incremental sync

**Input**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/workout-fetch-contract.md`, `quickstart.md`
**Issue**: MY-1477
**Layer context**: `Packages/HealthKitService/CONTEXT.md`
**Required gate**: Working directory `Packages/HealthKitService`; run `swift build && swift test`

## Format

Each executable row uses native Spec Kit syntax: `- [ ] Txxx [US#] Action with exact file path`. There are no `[P]` rows because T023-002 consumes the provider contract from T023-001.

## Phase 1: User Story 1 - Preserve and reconcile HealthKit workout history (P1)

**Goal**: Repeated reads and refreshes retain the prior HealthKit workout baseline while applying additions, updates, deletions, explicit range snapshots, and invalidation safely.

**Independent Test**: Run a deterministic provider sequence through `HealthDataCache`; after baseline A, empty changes still return A, and the complete add/update/delete/idempotency/range/invalidation/anchor-acceptance matrix passes without HealthKit hardware.

- [ ] T023-001 [US1] Define source-compatible baseline/changes/explicit-range prepared result types with opaque pending checkpoints plus anchor-free direct snapshot behavior in `Packages/HealthKitService/Sources/HealthKitService/HealthWorkoutRecord.swift` and `Packages/HealthKitService/Sources/HealthKitService/HealthKitService.swift`, with provider behavior tests in `Packages/HealthKitService/Tests/HealthKitServiceTests/HealthWorkoutQueryContractTests.swift`
- [ ] T023-002 [US1] Replace the invalidated waiter/turn design with one actor-isolated request transaction and a staged public-cache RED→GREEN matrix: package-internal prepared capability plus snapshot-only fallback, result-semantic UUID reconciliation, exactly-once owner/coalesced waiter settlement, request-ID provider lanes drained by cancellation/invalidation, opaque same-turn cache/checkpoint acceptance, deterministic ordering, and generation/key/request currentness in `Packages/HealthKitService/Sources/HealthKitService/HealthDataCache.swift` and `Packages/HealthKitService/Tests/HealthKitServiceTests/HealthWorkoutCacheTests.swift`; extend `Packages/HealthKitService/Tests/HealthKitServiceTests/PrivacyLoggingTests.swift` only if aggregate-only audit coverage is missing

### Task Metadata

| Field | T023-001 | T023-002 |
|---|---|---|
| Owning layer | HealthKitService | HealthKitService |
| Context pointer | `Packages/HealthKitService/CONTEXT.md` Types + Service roles | `Packages/HealthKitService/CONTEXT.md` Service role and L1 whole-entry red line |
| Slice | US1 | US1 |
| Blocking tasks | None | T023-001 |
| Files in scope | `HealthWorkoutRecord.swift`; `HealthKitService.swift`; new `HealthWorkoutQueryContractTests.swift` | `HealthDataCache.swift`; `HealthWorkoutCacheTests.swift`; `PrivacyLoggingTests.swift` only if needed |
| Files/layers excluded | `HealthDataCache.swift`; AppUI; VitalModels; WatchConnectivity; workout-session/write/delete flows | `HealthKitService.swift`, including public-access changes to prepared witnesses; `HealthWorkoutRecord.swift`; AppUI; VitalModels; WatchConnectivity; workout-session/write/delete flows |
| Contract impact | Define concrete prepared result/service behavior; direct service calls become anchor-free snapshots while keeping existing public call shapes source-compatible | Add the package-internal prepared capability/conformance in its cache-owned file and one actor-owned transaction/settlement/provider-lane module; retain public snapshot-only fallback and introduce no public provider/witness/AppUI API; treat checkpoints as opaque, record a candidate only when supplied, invoke provider acceptance only for a supplied candidate before caller success, and keep legacy/nil-checkpoint results checkpoint-absent |
| Task-local acceptance | Service tests prove anchor-free baseline preparation, anchored changes preparation, anchor-free explicit range, concrete snapshot coverage, prepared fetch does not persist, explicit acceptance persists when possible, discard does not, and direct call remains source-compatible without reading/advancing the anchor | Per-stage named RED→GREEN evidence; no T023-002 access edit in `HealthKitService.swift`; zero unsafe concurrency annotations in final production/test files and no lock-owned production waiter state/yield polling; actual prepared semantic; legacy fallback and nil-checkpoint prepared results publish checkpoint-absent state with no acceptance invocation; exactly-once owner/non-owner/error settlement; active/queued provider lanes drain on cancellation/supersession/invalidation and let a fresh successor start; A/c1→rejected B/c2→replay from c1→cache-accepted A+B/c2 plus matching acceptance invocation before waiter success; silent no-advance leaves durable c1 and proves another idempotent replay/submission; UUID/range/restart/failure/equal-time order matrix |
| Exact verification | From `Packages/HealthKitService`: `swift build && swift test` | From `Packages/HealthKitService`: `swift build && swift test` |

**Checkpoint**: US1 is complete only after T023-001 and T023-002 both pass the full package gate.

### Sequential TDD Stages Within T023-002

These are one non-parallelizable implementation task because every stage owns the same production/test files and must reuse Draft PR #423 plus the pinned delivery workspace. Within each stage, complete one named RED→GREEN tracer bullet before adding the next.

1. **Stage A — semantic reconciliation foundation**
   - RED: A→empty delta, prepared anchored intent returning a baseline, then UUID add/update/delete, unknown deletion, duplicate provider UUIDs, deletion-wins, repeated-delta idempotency, empty authoritative snapshot, and equal-time UUID ordering one case at a time.
   - GREEN: minimal prepared-result semantic transition and whole-entry normalized reconciler.
   - Gate: focused public-cache behavior passes; no private-state assertion.
2. **Stage B — exactly-once caller settlement**
   - RED: coalesced non-owner cancellation, owner cancellation with peers, and provider failure fan-out, each with explicit gates and a bounded no-hang assertion.
   - GREEN: actor-owned request/waiter registry and single remove-before-resume settlement authority; remove unchecked/lock-owned/yield-polling waiter helpers.
   - Gate: every registered caller records one terminal outcome and peers follow the specified owner/non-owner behavior.
3. **Stage C — provider-lane reset**
   - RED: active request plus queued successor under cancellation, same-key refresh supersession, `invalidateWorkouts()`, `invalidateAll()`, and authorization revocation while the stale provider remains held.
   - GREEN: actor-owned active/queued request identities, logical turn revocation, reset draining, and successor pump.
   - Gate: affected callers cancel once, fresh work starts before stale provider release, and late results reject without clearing/publishing.
4. **Stage D — opaque candidate publication, acceptance invocation, and anchored rejection/replay**
   - RED: accept A/c1; complete anchored B/c2 and hold before cache acceptance; cancel/supersede; assert c2 rejected; replacement reads durable c1, publishes A+B with candidate c2, invokes provider acceptance for c2, then completes callers. Next, make that invocation silently leave durable state on c1 and prove another request replays B and resubmits c2.
   - GREEN: generation/key/request-only currentness and one same-turn whole-entry/candidate-checkpoint publication plus synchronous provider acceptance invocation; remove checkpoint decoding/comparison and do not infer a persistence outcome from `Void`.
   - Gate: the cache entry contains the candidate submitted before caller success; rejected work submits nothing; silent durable lag drives c1 replay and idempotent c2 resubmission without a false persisted-success assertion.
5. **Stage E — remaining deterministic acceptance matrix**
   - RED→GREEN individually: explicit-range→default rebuild, default coverage versus wider range, different semantic/range requests not coalescing, persisted-anchor restart baseline rebuild, provider failure preservation, stale completion, legacy snapshot-only compatibility with no checkpoint/acceptance call, prepared baseline/change with nil checkpoint, aggregate-only logging if coverage is missing.
   - Gate: all thirteen spec scenarios and edge cases pass without timing-based synchronization.
6. **Stage F — package and diff gate**
   - From `Packages/HealthKitService`, run `swift build && swift test`.
   - Diff remains the declared two files unless the conditional privacy audit is required; no `xcodebuild`.
   - Audit changed code for zero `@unchecked Sendable`, `@preconcurrency`, `nonisolated(unsafe)`, checkpoint ordering/decoding, production locks/`Synchronization`, or `Task.yield` transaction polling.

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
| AC 9-10; FR-008/009/014/015 | US1 | T023-001 → T023-002 |
| AC 11-13; FR-016/017/018/019 | US1 | T023-002 |
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

- Preserve Draft PR #423 and invalidated SHA `d85372895fd4561aba3185e31605076d9429d517` as evidence; reuse the metadata-pinned dirty worktree without reset. Do not treat the invalidated candidate as a base for isolated line-by-line repair.
- Follow the sequential stages above. Each behavior must be observed RED before its minimal GREEN implementation; do not bulk-write the matrix horizontally.
- Test through public cache calls and the prepared-provider system seam. Deterministic adapters use compiler-checked Sendable state and distinct provider-started/query-complete/cache-acceptance/release gates; no sleep or yield synchronization.
- The adversarial test must hold an anchored result after the provider method completes but before cache acceptance, reject c2, prove the replacement reads from durable c1, then observe A+B/c2 publication and matching acceptance invocation before caller success. A separate silent-no-advance case must keep durable c1 and prove another idempotent replay/submission.
- Preserve whole-entry immutable assignment; do not mutate the published workout array in place.
- Keep the prepared capability/conformance package-internal in `HealthDataCache.swift`; do not widen T023-001's prepared methods or edit their access in excluded `HealthKitService.swift`.
- Treat legacy public providers as anchor-free snapshot-only adapters, and drive acceptance from the prepared result's actual semantic when an anchored preparation falls back to baseline.
- Keep all production request/waiter/provider-lane mutation inside `HealthDataCache`; one settlement authority removes before resume, reset drains before discard, and checkpoints remain opaque.
- Do not add workout L2 persistence, TTL/observer refresh policy, UI changes, or broad sample-cache refactors.
- If an implementation fact makes the reviewed contract infeasible, stop and return evidence to Team Lead/Planner rather than widening scope.
