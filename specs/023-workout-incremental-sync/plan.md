# Implementation Plan: HealthKit workout incremental sync

**Branch**: `agent/planner-lead/19b63eb88135`
**Date**: 2026-08-31
**Spec**: `specs/023-workout-incremental-sync/spec.md`
**Issue**: MY-1477

## Summary

Repair the workout cache/provider seam inside the `HealthKitService` layer with one actor-isolated request/transaction module. A package-internal prepared-fetch capability distinguishes snapshots from anchored changes and returns an opaque unpersisted checkpoint. `HealthDataCache` owns request registration, provider-lane scheduling, exactly-once waiter settlement, currentness, immutable UUID reconciliation, and same-turn cache/checkpoint acceptance. Public cache, provider, and direct-service entry points remain source-compatible without unsafe Sendable bypasses or widening prepared checkpoint methods into public API.

## Technical Context

**Language/Version**: Swift 6.0 with strict concurrency
**Primary Dependencies**: Foundation, HealthKit, OSLog; local dependency on VitalModels remains unchanged
**Storage**: Process-memory workout cache plus existing device-local HealthKit anchor; no new persistence
**Testing**: Swift Testing in `Packages/HealthKitService/Tests/HealthKitServiceTests`
**Target Platform**: iOS 18+, macOS 15+, watchOS 11+ package compatibility
**Project Type**: Local Swift package in a multiplatform application
**Performance Goals**: UUID reconciliation is linear in cached records plus changes; no duplicate provider request for the same semantic key
**Constraints**: Health values never enter logs; whole cache entry replacement; Swift 6 actor isolation with no unsafe Sendable annotations; opaque checkpoints; no xcodebuild for package-only work
**Scale/Scope**: One package layer, three production files, two primary test files

## Constitution Check — Before Design

| Gate | Result | Evidence |
|---|---|---|
| §I health privacy | PASS | Plan changes cache semantics only; aggregate query type/count/duration logs are allowed. |
| §II strict concurrency | PASS | Actor isolation remains the synchronization boundary; workout generation plus request-instance identity handles actor reentrancy without unsafe annotations. |
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
- `HealthKitService.fetchWorkouts(dateRange:)` currently persists the returned workout anchor before `HealthDataCache` can accept or reject the corresponding cache transition.

Details and alternatives are recorded in `research.md`.

Post-review delivery evidence:

- Draft PR #423 previously preserved invalidated exact SHA `d85372895fd4561aba3185e31605076d9429d517`; that historical tree remains evidence but is not an implementation authority. The current preserved Draft head is recorded below.
- The invalidated two-file candidate added three unchecked Sendable waiter/turn helpers, lock-owned mutable state, yield polling, a double-resume cancellation path, provider-turn continuations that invalidation could strand, and cache-side ordering of opaque checkpoints.
- Its anchored acceptance published the new workout projection with the previous checkpoint while separately persisting the candidate checkpoint, so the accepted pair could disagree.
- Its green test set did not exercise a completed anchored B/c2 rejected between provider completion and cache acceptance, replay from c1, or the full deterministic fallback/failure/order/range matrix.
- The metadata-pinned delivery worktree must be preserved without reset/recreation; Planner changes planning artifacts only. Its current clean `f5690f…` fingerprint is recorded below.

Repeated-candidate readiness evidence:

- Draft PR #423 and the clean metadata-pinned delivery worktree now resolve to invalidated SHA `f5690f1461a6cb07504d7f6e945220cb5213b2fb`; local HEAD, tracking branch, and PR head match, and auto-merge remains disabled.
- Exact-SHA reviews `00966211-f963-48f7-ac63-8623621e0298` and `9d352f6d-5742-40a7-a047-365e1aae2cea` report the same five P1 findings. The second review proves that the prior Fullstack retry produced no byte change.
- Relative to delivered base `9dfa1fb4317935573c0a2f7c9283d13a40f01104`, the preserved candidate still changes only `HealthDataCache.swift` and `HealthWorkoutCacheTests.swift`, with 1,737 insertions and 76 deletions.
- Production still contains `Synchronization`/Mutex-backed reference helpers, continuation-holder provider turns, yield polling, request-order currentness, checkpoint decoding/ordering, and previous-checkpoint carry-forward for nil candidates.
- The workout-cache test file has blob `9bdc7a5fd2b528b8f9273395480d9efa02625616` at both invalidated `d85372895fd4561aba3185e31605076d9429d517` and `f5690f1461a6cb07504d7f6e945220cb5213b2fb`; the reviewed A–F matrix has not replaced it.

## Design

### Provider contract

Add an explicit provider-level request semantic for:

1. default-window baseline snapshot;
2. anchored changes from the persisted workout anchor;
3. explicit-range snapshot.

The prepared result identifies snapshot versus changes. Snapshots report concrete coverage. Changes retain UUID upserts and deleted UUIDs. A baseline/change result may carry an opaque pending checkpoint but does not persist it. When no candidate exists, the cache publishes checkpoint-absent state and invokes no checkpoint acceptance. The prepared capability and its production conformance stay package-internal in the cache-owned file, so T023-001's package-internal preparation/acceptance methods satisfy it without a public access change in `HealthKitService.swift`. Existing public provider conformers use anchor-free snapshot-only fallback behavior with no checkpoint. The existing direct service call remains source-compatible but becomes an anchor-free authoritative snapshot, leaving `HealthDataCache` as the sole default-anchor acceptance authority. No implementation-level signature is prescribed here.

### Cache state transition

- Default read with no compatible cache → request baseline snapshot and establish provenance/coverage.
- Default refresh with a compatible baseline → request anchored changes.
- Explicit range read/refresh not covered by the current entry → request an anchor-free snapshot for that range.
- Acceptance follows the prepared result's declared semantic, not only the requested semantic; if preparation falls back from anchored changes to a baseline because no persisted anchor exists, publish it as a baseline with its concrete coverage/provenance.
- Snapshot → replace the single workout cache entry with the authoritative records and coverage.
- Changes → copy current records into a UUID map, apply upserts, apply deletions last, deterministically sort, then assign one new immutable entry with unchanged coverage.
- Incompatible query shape → rebuild rather than treating scoped data as global or vice versa.
- Accepted baseline/changes → construct the next entry with the candidate checkpoint, publish it, synchronously invoke provider acceptance for that same checkpoint without suspension, and only then settle success waiters. Because acceptance returns no outcome, a silent durable no-advance is handled by replay rather than reported as confirmed persistence; rejected results publish no candidate and invoke no acceptance.

### Actor-isolated request transaction module

Keep all mutable workout orchestration inside the existing `HealthDataCache` actor. Each request transaction is plain actor-owned state: semantic/range key, generation, unique request identity, owner waiter, coalesced waiter identities, provider task/turn phase, and terminal outcome. No independently synchronized waiter or in-flight helper object may own mutable state.

The private conceptual interface has three transitions, without prescribing Swift signatures:

1. **Register** creates a request or joins an eligible same-key request and records the caller waiter.
2. **Settle** handles prepared/snapshot success, provider failure, caller cancellation, or a stale late event through one terminal funnel.
3. **Reset** handles refresh supersession, workout invalidation, full invalidation, and authorization revocation by advancing generation, retiring affected transactions, releasing lanes, cancelling tasks, and settling waiters.

### Waiter lifecycle

- Every caller, including the request owner, has an actor-owned waiter identity and one pending continuation.
- The settlement authority removes the waiter before resuming it; every other success/error/cancel path submits an event to that authority and never resumes directly.
- A cancelled non-owner waiter completes independently and does not cancel the owner or peers.
- Cancelling the owner retires the request, cancels its provider task, rejects any later prepared result, and completes all attached waiters once so callers may retry against a new request instance.
- Late cancellation, provider completion, or duplicate settlement after removal is a no-op.

### Provider-turn scheduling

- Represent a provider lane as an actor-owned active request identity plus FIFO queued request identities, not as continuation-holding waiter objects.
- Baseline and anchored-change work share the default incremental anchor lane; unrelated anchor-free explicit ranges may use independent range lanes.
- Cancellation, supersession, or invalidation atomically retires active/queued old-generation identities and pumps eligible successor work immediately. It does not wait for a non-cooperative stale provider to return.
- A late provider result re-enters the actor with its captured generation/key/request identity, fails currentness, is rejected, and cannot clear or publish newer state.

### Cache acceptance and durable lag

- Treat every checkpoint as opaque; `HealthDataCache` does not import checkpoint-owner details, compare timestamps, decode anchors, or infer ordering.
- Generation, semantic/range key, and request identity are the only currentness authority.
- For a current prepared baseline or delta, compute one whole immutable entry containing the prepared candidate checkpoint. Assign that entry and synchronously invoke provider acceptance with the same candidate in one actor turn, with no `await`, lane release, or waiter completion between them.
- If a prepared baseline/delta supplies no checkpoint, or the result came through legacy snapshot-only fallback, publish the semantic records/coverage/provenance with checkpoint absent and skip checkpoint acceptance. Nil is valid absence, not rejection or an inferred durable outcome.
- The package-internal acceptance returns `Void` and its anchor archive path may silently no-op, so T023-002 cannot claim or verify durable persistence. Settlement proves only that the matching acceptance invocation occurred before caller success.
- If durable state remains on the prior checkpoint, the next provider query reads that prior checkpoint and replays the delta. UUID reconciliation is idempotent; the cache may submit the same candidate again. No rollback or waiter failure is inferred from an unreportable no-advance.

### Concurrency and invalidation

- Key in-flight fetches by request semantic and date range.
- Give every started fetch a unique request instance and capture a workout-specific generation before awaiting the provider.
- Ordinary duplicate reads may coalesce onto the owning instance; an explicit refresh supersedes prior work even for the same semantic/range.
- `invalidateWorkouts()`, `invalidateAll()`, and authorization revocation route through the reset transition: bump generation, clear cache, retire active/queued lane state, cancel tasks, and settle every affected caller before discarding indexes.
- A fetch commits only if generation, semantic/range key, and request instance remain current; only the actor settlement authority may retire that instance or clear its lane.
- Errors, rejected currentness, cancellation, and stale completions leave the last accepted cache/checkpoint pair unchanged.
- All mutable request/waiter/turn state remains actor-isolated value state; no lock, unchecked Sendable helper, or yield-polling handshake is used.

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
- Make the direct service call anchor-free and side-effect-free with respect to the default workout anchor.
- Keep the precise cache-facing provider/result seam package-internal, with its conformance owned by `HealthDataCache.swift`; do not add public prepared-fetch requirements or public witness changes in `HealthKitService.swift`.
- Existing public provider conformers remain source-compatible and are treated as anchor-free snapshot-only adapters; compatibility behavior is locked by tests.

## Vertical Slice and Dependency Graph

| Slice | Outcome | Tasks | Upstream slices |
|---|---|---|---|
| US1 | Watch/HealthKit workout history survives empty deltas and reconciles additions, updates, deletions, range snapshots, and invalidation | T023-001 → T023-002 | None |

Task metadata and the acceptance mapping are in `tasks.md`.

## Verification Strategy

1. Preserve Draft PR #423 and the pinned delivery workspace; treat invalidated SHAs `d85372895fd4561aba3185e31605076d9429d517` and current `f5690f1461a6cb07504d7f6e945220cb5213b2fb` as rejected-baseline evidence, not proof that every individual behavior is RED.
2. Run sequential test-first tracer bullets through the public cache seam. First run a strengthened named behavior against the preserved baseline. Use mandatory RED→GREEN when the behavior is missing/incorrect or its production path will change in that tracer; when the behavior is already correct and that path remains unchanged, record characterization-GREEN with strengthened observable assertions and keep it in every later regression set. Never regress code or conflate defects to manufacture RED. Each of the five reviewed P1 defect families still requires its explicit mandatory RED evidence below.
3. Stage order is: result-semantic/reconciliation foundation; exactly-once coalesced waiter settlement; provider-lane cancellation/reset; checkpoint publication plus synchronous acceptance invocation and anchored rejection/replay; remaining fallback/range/restart/failure/order compatibility matrix.
4. Use explicit provider-started, query-complete, cache-acceptance, acceptance-invocation, durable-advance, cancellation, and release gates. Sleeps and `Task.yield` are not synchronization evidence.
5. Existing HealthKitService tests protect public compatibility and privacy logging.
6. Required layer gate, from `Packages/HealthKitService`:

```bash
swift build && swift test
```

No `xcodebuild` is permitted because implementation scope is package-only.

## Preserved-Workspace Replacement Protocol

### Two-phase dispatch and Stage 0 preconditions

**Phase 0A — Team Lead immediately before dispatch**:

- timestamp the packet and attribute it to the Team Lead run;
- confirm the metadata-pinned worktree and branch identity;
- confirm no pre-existing active or orphan process owns the worktree;
- record clean local HEAD, tracking OID, remote branch OID, and Draft PR #423 head all equal to `f5690f1461a6cb07504d7f6e945220cb5213b2fb`;
- record that the PR remains Draft with auto-merge disabled and target `main`;
- record the two-file base diff, exact obsolete-pattern inventory, and test blob `9bdc7a5fd2b528b8f9273395480d9efa02625616`;
- confirm MY-1483 names the exact reviewed planning revision.

If Phase 0A differs, Team Lead does not dispatch Fullstack and reports the divergence. Team Lead does not reset, clean, recreate, re-checkout, or silently normalize the preserved workspace.

**Phase 0B — dispatched Fullstack, before its first edit**:

- timestamp a separately attributable packet, record the current Fullstack run/task identity as the expected owner, and exclude only that current run from the ownership check;
- confirm no competing active or orphan process owns or writes the worktree;
- independently recheck the clean four-way `f5690f…` equality, Draft/no-auto-merge/target state, two-file diff, obsolete-pattern inventory, test blob, and reviewed planning revision from Phase 0A.
- run the declared fail-on-match obsolete-pattern audit and record its exact command, expected nonzero exit, and matched unsafe-Sendable/Mutex state as the first mandatory structural RED. Those expected matches are fingerprint evidence; only a mismatch from Phase 0A is divergence.

If Phase 0B differs, Fullstack stops before editing, preserves the workspace unchanged, and reports the exact divergence to Team Lead. It does not reset, clean, recreate, re-checkout, terminate an unverified competing process, or continue with a partial packet. No source byte may change until both phases agree.

### Required removal and replacement map

| Rejected source/test state | Must be removed | Reviewed replacement | First exit gate that proves replacement |
|---|---|---|---|
| `Synchronization`/Mutex-backed mutable waiter and in-flight reference helpers | Production import, lock-owned helper state, independent completion paths | Plain actor-owned transaction/waiter values plus one remove-before-resume settlement authority | Stage B |
| Continuation-holder provider-turn objects | Stored provider-turn continuation helpers and remove-without-resume cancellation | Actor-owned active/queued request identities with revocable lane ownership and successor pump | Stage C |
| `Task.yield`/timing coordination | Production polling and test yield/sleep interleaving evidence | Explicit provider-started, query-complete, cache-acceptance, acceptance-invocation, durable-advance, and release gates | Stages B–E |
| Request-order cache/currentness state | Entry field, global/per-key order maps, and order comparisons | Generation + semantic/range key + unique request identity in the transaction only | Stages B/D |
| Checkpoint decoding/ordering | Anchor string/data/timestamp parsing and stale-order heuristics | Opaque candidate; generation/key/request identity alone decides currentness | Stage D |
| Previous-checkpoint carry-forward and unconditional acceptance | Nil coalescing and acceptance call when no candidate exists | Store exactly the supplied optional candidate; legacy/nil/explicit results stay checkpoint-absent and call no acceptance | Stages D/E |
| Invalidated insensitive tests | Unchanged test blob and baseline/snapshot/cache-hit substitutes for anchored transaction evidence | Public-cache tracer bullets with explicit gates and recorded terminal outcomes | Stages A–E |

### Stage evidence ledger

Fullstack accumulates this ledger locally and publishes it in the single final implementation handoff; no progress comment substitutes for an exit gate. A tracer records exactly one evidence mode before its production change: mandatory RED with named test/command/nonzero exit/observable defect, or characterization-GREEN with named test/command/zero exit/strengthened observable assertions and proof that its production path is not changed by that tracer.

| Stage | Entry evidence | Test-first evidence before production change for that tracer | Exit evidence |
|---|---|---|---|
| A — semantic reconciliation | Both Stage 0 phases agree; source still at preserved candidate | Mandatory RED for a missing/incorrect or changing production path; otherwise characterization-GREEN with strengthened semantic/UUID/empty/order assertions | Every case has RED→GREEN or characterization-GREEN evidence before the next; all Stage A cases green; only allowlisted files changed |
| B — caller settlement | Stage A exit plus named owner/non-owner/failure cases not yet satisfied | Explicit-gate cancellation/failure test fails or reaches its bounded no-hang guard; no direct private-state assertion | All registered callers record one terminal outcome; old waiter/in-flight locks, direct resume paths, and production yield polling absent; Stage A+B focused tests green |
| C — provider-lane reset | Stage B exit; active/queued request scenario scripted | Cancellation/supersession/invalidation/authorization-reset test proves the preserved design strands or blocks a waiter/successor | Old provider-turn continuation holder absent; affected callers cancel once; successor starts before stale release; late result rejects; A–C green |
| D — opaque checkpoint/replay | Stage C exit; A/c1 accepted and B/c2 script available | Query-complete B/c2 is held before cache acceptance and the old design fails rejection/replay or candidate semantics | Checkpoint decode/order, request order, and previous-checkpoint carry-forward absent; c2 rejection, replay from c1, matching invocation, and silent durable-lag resubmission transcript recorded; A–D green |
| E — complete matrix | Stage D exit; remaining scenario list enumerated | Mandatory RED for any missing/incorrect or changing path; otherwise characterization-GREEN with strengthened legacy/nil/range/restart/failure/stale assertions | Every spec scenario/edge passes; test blob differs from preserved `9bdc7a…`; no sleep/yield timing evidence; A–E green |
| F — delivery gate | Complete A–E ledger; both mandatory files differ from `f5690f…`; obsolete-pattern audit clean | Not applicable—F verifies the assembled candidate | Full package gate passes; diff is allowlisted; commit/push produces a non-invalidated SHA; local/remote/PR equality proven; Fullstack requests exact-SHA review itself |

Mandatory defect RED evidence remains non-negotiable for the five repeated P1 families:

1. Stage 0's fail-on-match audit for unsafe-Sendable/Mutex-owned mutable waiter state is structurally RED before Stage B removes that state.
2. Stage B must expose the multiple/independent waiter-completion path through an explicit-gate public-cache test before centralizing remove-before-resume settlement.
3. Stage C must expose the continuation-holder lane's stranded caller or blocked successor under cancellation/invalidation before replacing it with revocable request-ID lanes.
4. Stage D must expose the cache-entry/candidate-checkpoint mismatch caused by previous-checkpoint carry-forward before publishing the exact candidate.
5. Stage D must expose cache-side checkpoint decoding/comparison defeating request-identity currentness and anchored replay before removing those heuristics.

The anchored B/c2 rejection/replay tracer in Stage D is also mandatory RED. Static pattern evidence alone cannot substitute for the behavior REDs in items 2–5. Characterization-GREEN is permitted only for other already-correct behavior whose production path is unchanged by its tracer.

### Genuinely new-SHA gate

A candidate is not reviewable or shippable unless all conditions hold:

- local HEAD is neither `f5690f1461a6cb07504d7f6e945220cb5213b2fb` nor `d85372895fd4561aba3185e31605076d9429d517`;
- both `HealthDataCache.swift` and `HealthWorkoutCacheTests.swift` have non-empty byte deltas from `f5690f…` (the conditional privacy test may be a third file);
- the obsolete production/test patterns in the removal map are absent;
- `swift build && swift test` passes from `Packages/HealthKitService`;
- local HEAD, tracking branch, pushed remote OID, and PR #423 `headRefOid` are byte-identical at the new SHA;
- PR #423 remains Draft/auto-merge-disabled until Fullstack obtains an exact-SHA AI Reviewer PASS or PASS WITH FOLLOW-UP.

An empty commit, same-tree commit, same-SHA re-request, focused-test-only result, claimed audit without byte evidence, or request authored by anyone other than Fullstack fails readiness and returns to Team Lead without another implementation review.

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Persisted anchor outlives in-memory baseline | Empty/incompatible cache forces baseline and re-establishes the anchor. |
| Range snapshot is treated as a global baseline | Result carries semantic/coverage; cache provenance controls compatibility. |
| Late actor-reentrant task overwrites newer state | Workout generation plus fetch-key/request-instance ownership guards every post-await commit. |
| Different ranges share an in-flight result | Coalescing key includes semantic and range. |
| Same-semantic superseded result advances anchor or clears newer ownership | Unique request-instance currentness; only accepted owner publishes a candidate then invokes provider acceptance. |
| Mutable waiter helpers require unsafe Sendable escapes or double-complete | Store plain waiter/transaction state in the actor and route every terminal outcome through remove-before-resume settlement. |
| Cancellation/invalidation strands provider-turn waits | Queue actor-owned request identities rather than continuations; reset drains identities/waiters and immediately pumps eligible successor work. |
| Non-cooperative stale provider blocks successor | Logical lane ownership is revocable; late results fail generation/key/request identity and are rejected. |
| Cache candidate and durable anchor differ after silent acceptance no-op | Publish the supplied candidate and synchronously invoke matching acceptance before success; explicitly permit durable lag and prove replay from the prior anchor is idempotent. Nil candidates publish checkpoint-absent state and skip invocation. |
| Opaque checkpoint is misordered by cache heuristics | Never decode or compare it; currentness alone decides acceptance. |
| Direct service caller advances the anchor outside cache acceptance | Direct entry point is anchor-free snapshot-only; cache-facing prepare/accept is the sole anchor writer. |
| A package-internal cache seam accidentally widens public service API or crosses task ownership | Keep the capability and conformance in `HealthDataCache.swift`; existing package-internal service witnesses remain owned by T023-001 and require no access change. |
| Requested anchored changes prepare a baseline because no anchor exists | Drive publication, coverage, and provenance from the prepared result's declared semantic. |
| Process interruption or silent no-advance after cache publication | Previous durable anchor remains; next fetch safely replays idempotent UUID changes. |
| Duplicate or unstable projection | UUID map plus explicit sort/tie-breaker. |
| Logging leaks workout details | Keep only aggregate query type/count/duration and extend existing privacy audit only if needed. |
| Scope grows into workout persistence/refresh policy | L2 workout persistence, observer sync, and TTL remain explicit non-goals. |
| Fullstack reports progress or package green without replacing rejected bytes | Stage exit requires named RED→GREEN or eligible characterization-GREEN evidence plus source/test removal proof; every repeated P1 retains mandatory RED, and Stage F requires both mandatory file blobs to differ from `f5690f…`. |
| Same invalidated tree is recommitted or re-reviewed | New-SHA gate rejects both invalidated SHAs, empty/same-tree commits, and any review request without four-way equality at a non-invalidated head. |

## Constitution Check — After Design

All pre-design gates remain PASS. The design uses the existing `HealthDataCache` actor as the sole transaction module, preserves dependency direction/public call shapes/file ownership, keeps the prepared capability package-internal, removes the need for unsafe concurrency exceptions, and defines exact package-local verification. No constitution exception or ADR is required.

## Complexity Tracking

No constitution violations require justification.
