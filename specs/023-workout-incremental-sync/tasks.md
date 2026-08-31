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
- [ ] T023-002 [US1] Replace the invalidated waiter/turn design with one actor-isolated request transaction and a staged public-cache test-first matrix with mandatory defect RED→GREEN plus eligible characterization-GREEN: package-internal prepared capability plus snapshot-only fallback, result-semantic UUID reconciliation, exactly-once owner/coalesced waiter settlement, request-ID provider lanes drained by cancellation/invalidation, opaque same-turn cache/checkpoint acceptance, deterministic ordering, and generation/key/request currentness in `Packages/HealthKitService/Sources/HealthKitService/HealthDataCache.swift` and `Packages/HealthKitService/Tests/HealthKitServiceTests/HealthWorkoutCacheTests.swift`; extend `Packages/HealthKitService/Tests/HealthKitServiceTests/PrivacyLoggingTests.swift` only if aggregate-only audit coverage is missing

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
| Task-local acceptance | Service tests prove anchor-free baseline preparation, anchored changes preparation, anchor-free explicit range, concrete snapshot coverage, prepared fetch does not persist, explicit acceptance persists when possible, discard does not, and direct call remains source-compatible without reading/advancing the anchor | Per-tracer RED→GREEN for missing/incorrect or changing behavior and characterization-GREEN only for already-correct unchanged paths; mandatory RED for all five repeated P1 families and anchored rejection/replay; no T023-002 access edit in `HealthKitService.swift`; zero unsafe concurrency annotations in final production/test files and no lock-owned production waiter state/yield polling; actual prepared semantic; legacy fallback and nil-checkpoint prepared results publish checkpoint-absent state with no acceptance invocation; exactly-once owner/non-owner/error settlement; active/queued provider lanes drain on cancellation/supersession/invalidation/authorization reset and let a fresh successor start; A/c1→rejected B/c2→replay from c1→cache-accepted A+B/c2 plus matching acceptance invocation before waiter success; silent no-advance leaves durable c1 and proves another idempotent replay/submission; UUID/range/restart/failure/equal-time order matrix |
| Exact verification | From `Packages/HealthKitService`: `swift build && swift test` | From `Packages/HealthKitService`: `swift build && swift test` |

**Checkpoint**: US1 is complete only after T023-001 and T023-002 both pass the full package gate.

### Sequential Test-First Stages Within T023-002

These are one non-parallelizable implementation task because every stage owns the same production/test files and must reuse Draft PR #423 plus the pinned delivery workspace. Complete one named test-first tracer before adding the next: RED→GREEN for missing/incorrect behavior or a changing production path, or strengthened characterization-GREEN for an already-correct unchanged path. Never manufacture RED.

**Stage 0A — Team Lead pre-dispatch**: immediately before dispatch, record a timestamped packet attributable to that Team Lead run for the clean preserved workspace at exact rejected SHA `f5690f1461a6cb07504d7f6e945220cb5213b2fb`: local/tracking/remote/PR equality, Draft/no-auto-merge state, no pre-existing active/orphan owner, two-file base diff, obsolete source-pattern inventory, unchanged test blob `9bdc7a5fd2b528b8f9273395480d9efa02625616`, and exact reviewed planning revision. If any value differs, do not dispatch; report it without reset/clean/recheckout.

**Stage 0B — Fullstack post-dispatch/pre-edit**: record a separate timestamped packet attributable to its own current run/task identity as the expected owner, exclude only that run, confirm no competing active/orphan process, and independently recheck every 0A value. Run the declared fail-on-match obsolete-pattern audit and record its exact command, expected nonzero exit, and unsafe-Sendable/Mutex matches as mandatory structural RED; expected matches are fingerprint evidence, while a mismatch from 0A is divergence. If any other value differs, stop before editing, preserve the workspace, and report it; do not terminate an unverified process or normalize the tree. Source work starts only after 0A and 0B agree.

Each stage starts only after the previous exit. For its next tracer, record either the named RED command/nonzero exit/observable defect before relevant production change, then GREEN; or a named characterization-GREEN command/zero exit/strengthened assertions plus unchanged-path proof. Record the replacement diff and prior-stage regression result. Mandatory RED remains for the five repeated P1 families: unsafe-Sendable/Mutex-owned waiter state (Stage 0 fail-on-match audit), multiple/independent completion (B), stranded continuation-holder lanes (C), previous/candidate entry mismatch (D), and checkpoint decoding/comparison defeating currentness/replay (D). Anchored B/c2 rejection/replay in D is also mandatory RED. Accumulate the ledger for the single final handoff; a progress comment, package-green claim, or audit claim without byte evidence is not an exit.

1. **Stage A — semantic reconciliation foundation**
   - Test-first: A→empty delta, prepared anchored intent returning a baseline, then UUID add/update/delete, unknown deletion, duplicate provider UUIDs, deletion-wins, repeated-delta idempotency, empty authoritative snapshot, and equal-time UUID ordering one case at a time; use RED only if missing/incorrect or changing, otherwise characterization-GREEN.
   - GREEN: minimal prepared-result semantic transition and whole-entry normalized reconciler.
   - Entry: Stage 0A/0B packets agree and the next public-cache tracer has a declared evidence mode.
   - Exit: every listed behavior has sequential RED→GREEN or eligible characterization-GREEN evidence; focused Stage A suite passes; diff remains allowlisted.
2. **Stage B — exactly-once caller settlement**
   - Mandatory RED: an explicit-gate owner/non-owner/error case that exposes multiple/independent completion before replacement; then cover coalescing, non-owner cancellation, owner cancellation with peers, and provider failure fan-out with bounded no-hang assertions.
   - GREEN: actor-owned request/waiter registry and single remove-before-resume settlement authority; remove unchecked/lock-owned/yield-polling waiter helpers.
   - Entry: Stage A exit plus failing owner/non-owner/failure tracer.
   - Exit: every registered caller records one terminal outcome; old lock-owned waiter/in-flight state, direct second resume, and production yield polling are absent; Stage A+B tests pass.
3. **Stage C — provider-lane reset**
   - Mandatory RED: an active request plus queued successor that exposes continuation-holder stranding or successor blockage under cancellation/invalidation; then cover same-key refresh supersession, `invalidateWorkouts()`, `invalidateAll()`, and authorization revocation while the stale provider remains held.
   - GREEN: actor-owned active/queued request identities, logical turn revocation, reset draining, and successor pump.
   - Entry: Stage B exit plus failing active/queued lane-reset tracer.
   - Exit: old provider-turn continuation holder is absent; affected callers cancel once, fresh work starts before stale provider release, late results reject without clearing/publishing, and A–C tests pass.
4. **Stage D — opaque candidate publication, acceptance invocation, and anchored rejection/replay**
   - Mandatory REDs: separately expose previous/candidate entry mismatch, checkpoint decoding/comparison defeating request-identity currentness, and anchored rejection/replay by accepting A/c1, completing B/c2 before cache acceptance, cancelling/superseding, and proving the preserved design fails. Replacement reads durable c1, publishes A+B with candidate c2, invokes provider acceptance for c2, then completes callers; silent no-advance leaves c1 and another request replays B and resubmits c2.
   - GREEN: generation/key/request-only currentness and one same-turn whole-entry/candidate-checkpoint publication plus synchronous provider acceptance invocation; remove checkpoint decoding/comparison and do not infer a persistence outcome from `Void`.
   - Entry: Stage C exit plus scripted A/c1 and query-complete B/c2 failing before cache acceptance.
   - Exit: checkpoint decode/order, request-order state, and previous-checkpoint carry-forward are absent; entry/invocation/rejection/replay/silent-lag transcript is recorded; A–D tests pass.
5. **Stage E — remaining deterministic acceptance matrix**
   - Test-first individually: explicit-range→default rebuild, default coverage versus wider range, different semantic/range requests not coalescing, persisted-anchor restart baseline rebuild, provider failure preservation, stale completion, legacy snapshot-only compatibility with no checkpoint/acceptance call, prepared baseline/change with nil checkpoint, aggregate-only logging if coverage is missing; use RED only if missing/incorrect or changing, otherwise characterization-GREEN.
   - Entry: Stage D exit plus the next named matrix behavior and declared evidence mode.
   - Exit: all thirteen scenarios and edge cases pass without timing-based synchronization; test blob differs from `9bdc7a5…`; A–E tests pass.
6. **Stage F — package and diff gate**
   - From `Packages/HealthKitService`, run `swift build && swift test`.
   - Diff remains the declared two files unless the conditional privacy audit is required; no `xcodebuild`.
   - Entry: complete A–E ledger; non-empty deltas in both `HealthDataCache.swift` and `HealthWorkoutCacheTests.swift` versus `f5690f…`; obsolete-pattern audit empty.
   - Audit changed code for zero `@unchecked Sendable`, `@preconcurrency`, `nonisolated(unsafe)`, checkpoint ordering/decoding, production locks/`Synchronization`, continuation-holder turns, request order, prior-checkpoint carry-forward, or timing yield/sleep coordination.
   - Exit: commit/push a SHA different from `f5690f…` and `d853728…`; prove local/tracking/remote/PR equality with PR still Draft/no-auto-merge; Fullstack requests exact-SHA implementation review itself.

### Mandatory Removal/Replacement Preconditions

| Must remove from preserved source/tests | Must replace with | Required exit |
|---|---|---|
| `Synchronization`/Mutex mutable waiter and in-flight reference helpers | Actor-owned transaction/waiter values and one remove-before-resume settlement funnel | B |
| Continuation-holder provider-turn objects | Actor-owned active/queued request identities and revocable lane pump | C |
| Production/test `Task.yield` or sleep coordination | Explicit provider/query/acceptance/durable/release gates | B–E |
| Request-order cache/currentness state | Generation + key + request identity in transaction state only | B/D |
| Checkpoint parsing/comparison | Opaque candidate governed only by currentness | D |
| Previous-checkpoint carry-forward/unconditional acceptance | Exact optional candidate; nil/fallback/explicit entries checkpoint-absent with no acceptance call | D/E |
| Unchanged invalidated test blob | Reviewed public-cache A–F tracer matrix | A–E |

### Genuinely New-SHA Gate

- Reject HEAD equal to `f5690f1461a6cb07504d7f6e945220cb5213b2fb` or `d85372895fd4561aba3185e31605076d9429d517`.
- Reject an empty/same-tree commit or any candidate where either mandatory file has no delta from `f5690f…`.
- Reject focused-test-only evidence, non-empty obsolete-pattern audit, non-Fullstack review routing, or mismatched local/tracking/remote/PR OIDs.
- Only a new equal SHA with full package pass, allowlisted diff, clean pattern audit, Draft/no-auto-merge PR, and Fullstack-authored exact-SHA review request may leave Stage F.

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

- Preserve Draft PR #423 and invalidated SHAs `d85372895fd4561aba3185e31605076d9429d517` and `f5690f1461a6cb07504d7f6e945220cb5213b2fb` as evidence; reuse the metadata-pinned worktree without reset. Do not treat either invalidated candidate as a base for isolated line-by-line repair or same-SHA re-review.
- Follow the sequential stages above. Missing/incorrect or changing behavior must be observed RED before minimal GREEN; already-correct unchanged behavior gets strengthened characterization-GREEN and ongoing regression coverage. Never manufacture RED or bulk-write the matrix horizontally.
- Test through public cache calls and the prepared-provider system seam. Deterministic adapters use compiler-checked Sendable state and distinct provider-started/query-complete/cache-acceptance/acceptance-invocation/durable-advance/release gates; no sleep or yield synchronization.
- The adversarial test must hold an anchored result after the provider method completes but before cache acceptance, reject c2, prove the replacement reads from durable c1, then observe A+B/c2 publication and matching acceptance invocation before caller success. A separate silent-no-advance case must keep durable c1 and prove another idempotent replay/submission.
- Preserve whole-entry immutable assignment; do not mutate the published workout array in place.
- Keep the prepared capability/conformance package-internal in `HealthDataCache.swift`; do not widen T023-001's prepared methods or edit their access in excluded `HealthKitService.swift`.
- Treat legacy public providers as anchor-free snapshot-only adapters, and drive acceptance from the prepared result's actual semantic when an anchored preparation falls back to baseline.
- Keep all production request/waiter/provider-lane mutation inside `HealthDataCache`; one settlement authority removes before resume, reset drains before discard, and checkpoints remain opaque.
- Do not add workout L2 persistence, TTL/observer refresh policy, UI changes, or broad sample-cache refactors.
- If an implementation fact makes the reviewed contract infeasible, stop and return evidence to Team Lead/Planner rather than widening scope.
