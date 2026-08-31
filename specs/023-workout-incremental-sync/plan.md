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
- The metadata-pinned delivery worktree must be preserved without reset/recreation or history rewrite; Planner changes planning artifacts only. Its forward-recovery composite at local HEAD `794624a…` is recorded below.

Forward-recovery readiness evidence:

- Owner recovery is authorized by comment `7c73c678-c3b6-48f3-8eb7-7f272823083a`; Team Lead composite direction is comment `6bb3aac9-4177-4fd7-b304-b9d76eddeb56`. No Fullstack continuation is active.
- Local HEAD is `794624a2516e60c461cb8a598d95c67e7df6b3b5`; its parent, tracking branch, pushed remote, and Draft PR #423 head are all `f5690f1461a6cb07504d7f6e945220cb5213b2fb`. The PR is OPEN Draft targeting `main` with auto-merge disabled.
- Local commit `794624a…` must remain in history. It changes `HealthDataCache.swift` `+117/−731` from blob `be0963652c349210fa39a898cfecf47f13bf710f` to `7956e0b06d9d38b73f2ab088ed87f4967b33a961`, and improperly changes excluded `HealthKitService.swift` `+4/−4` from base blob `4b1f809090c96185a8bf6befe1360bf30c6ec263` to `77fb965f34cf0da6dab0052ab66630f11ddddf1e`.
- Relative to local HEAD, the worktree has exactly three dirty paths: `HealthDataCache.swift` `+119/−24`, blob `206acca959568e56ca3aaf62ee764f04b0aa2392`; excluded `HealthKitService.swift` `+1/−1`, blob `b8244271b30a51da04a41e6eb28d9c5faf6e156e`; and `HealthWorkoutCacheTests.swift` `+36/−8`, blob `28f96c751553f7bf39d16c62ad5394ebfe74c96d` from base/HEAD blob `9bdc7a5fd2b528b8f9273395480d9efa02625616`.
- MY-1483 metadata pins local HEAD `794624a…`, dirty cache blob `206acca…`, and recovery owner task `113937f4-8a72-44cf-867b-ade6cee55a6e`. The prior `stage_0a_packet` describes the superseded `7f1f162…` composite and must be replaced only after this planning revision passes.
- The inherited implementation widens four prepared-fetch witnesses to public and one anchor reader to internal in excluded `HealthKitService.swift`. Cache-owned code also widens `WorkoutPreparedDataProviding`, imports HealthKit, adds public `WorkoutCheckpointTracking`, reconstructs an anchor, parses its description, and compares `lastSyncDate`. These are rejected ownership/currentness seams, not authority to expand scope.
- Exact-SHA reviews `00966211-f963-48f7-ac63-8623621e0298` and `9d352f6d-5742-40a7-a047-365e1aae2cea` remain the defect baseline. The current local/dirty work is preserved as forward-only input, not accepted delivery.

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
    └── HealthWorkoutQueryContractTests.swift   # delivered by T023-001
```

**Structure Decision**: Keep the fix in the existing HealthKitService Types/Service roles. Do not add a package, AppUI adapter, or workout L2 model.

## Files in Scope

- `Packages/HealthKitService/Sources/HealthKitService/HealthDataCache.swift`
- `Packages/HealthKitService/Sources/HealthKitService/HealthKitService.swift`
- `Packages/HealthKitService/Sources/HealthKitService/HealthWorkoutRecord.swift`
- `Packages/HealthKitService/Tests/HealthKitServiceTests/HealthWorkoutCacheTests.swift`
- `Packages/HealthKitService/Tests/HealthKitServiceTests/HealthWorkoutQueryContractTests.swift` (delivered by T023-001)

T023-002 final implementation scope is exactly:

- `Packages/HealthKitService/Sources/HealthKitService/HealthDataCache.swift`
- `Packages/HealthKitService/Tests/HealthKitServiceTests/HealthWorkoutCacheTests.swift`

Excluded `HealthKitService.swift` has one recovery-only exception: Fullstack must manually edit its five inherited access-modifier deltas back to base blob `4b1f809090c96185a8bf6befe1360bf30c6ec263`. This is scope cleanup, not behavior ownership; the final cumulative diff for that file must be empty.

## Files NOT to Touch

- `VitalStride/**`, including `WorkoutListView.swift`
- `Packages/VitalModels/**` and all SwiftData/CloudKit schemas
- WorkoutSessionManager, WatchConnectivity, and live heart-rate files
- HealthKit workout write/delete flows except consuming anchored deleted IDs
- `project.yml` and `VitalStride.xcodeproj/**`
- `Packages/HealthKitService/Tests/HealthKitServiceTests/PrivacyLoggingTests.swift`; existing privacy coverage must pass unchanged

## Public Interface Contract

- Keep `HealthDataCache.workoutData(in:)` source-compatible.
- Keep `HealthDataCache.refreshWorkouts(in:)` source-compatible.
- Keep `HealthKitService.fetchWorkouts(dateRange:)` source-compatible.
- Make the direct service call anchor-free and side-effect-free with respect to the default workout anchor.
- Keep the precise cache-facing provider/result seam package-internal, with its conformance owned by `HealthDataCache.swift`; do not add public prepared-fetch requirements or public witness changes in `HealthKitService.swift`.
- Manually remove inherited public access from `prepareWorkoutSnapshot`, `prepareWorkoutChanges`, `acceptPreparedWorkoutFetch`, and `rejectPreparedWorkoutFetch`, and restore `persistedWorkoutAnchor` to `private`; do not use reset, checkout, stash, revert, amend, or rebase to accomplish it.
- Existing public provider conformers remain source-compatible and are treated as anchor-free snapshot-only adapters; compatibility behavior is locked by tests.

## Vertical Slice and Dependency Graph

| Slice | Outcome | Tasks | Upstream slices |
|---|---|---|---|
| US1 | Watch/HealthKit workout history survives empty deltas and reconciles additions, updates, deletions, range snapshots, and invalidation | T023-001 → T023-002 | None |

Task metadata and the acceptance mapping are in `tasks.md`.

## Verification Strategy

1. Preserve local commit `794624a…`, its three-path dirty worktree, and Draft PR #423 without rewriting history or discarding in-scope bytes. Treat `d853728…`, `f5690f…`, prior dirty `7f1f162…`, local commit blobs, and current dirty blobs as rejected/partial evidence, not a shipping claim.
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

### Forward-only dispatch and Stage 0 preconditions

**Phase 0A — Team Lead immediately before dispatch**:

- timestamp the packet and attribute it to the Team Lead run;
- confirm the metadata-pinned worktree and branch identity;
- confirm owner recovery authority from comment `7c73c678-c3b6-48f3-8eb7-7f272823083a`, recovery owner metadata `113937f4-8a72-44cf-867b-ade6cee55a6e`, and no active/orphan process owning the worktree;
- record local HEAD `794624a2516e60c461cb8a598d95c67e7df6b3b5`; record its parent, tracking OID, remote branch OID, and Draft PR #423 head all equal to `f5690f1461a6cb07504d7f6e945220cb5213b2fb`;
- record that the PR remains Draft with auto-merge disabled and target `main`;
- record the local commit's exact two paths: cache `+117/−731`, blob `7956e0b06d9d38b73f2ab088ed87f4967b33a961`; excluded service `+4/−4`, blob `77fb965f34cf0da6dab0052ab66630f11ddddf1e`; test blob still `9bdc7a5fd2b528b8f9273395480d9efa02625616`;
- record exactly three worktree-dirty paths relative to local HEAD: cache `+119/−24`, blob `206acca959568e56ca3aaf62ee764f04b0aa2392`; excluded service `+1/−1`, blob `b8244271b30a51da04a41e6eb28d9c5faf6e156e`; tests `+36/−8`, blob `28f96c751553f7bf39d16c62ad5394ebfe74c96d`;
- confirm no other tracked or untracked delivery changes and record the current obsolete-pattern/currentness inventory;
- confirm metadata keys `delivery_local_head`, `delivery_dirty_owner_task_id`, and `delivery_dirty_blob_sha` match `794624a…`, `113937f4…`, and `206acca…`;
- replace the superseded `stage_0a_packet` only after this exact planning revision passes, then confirm MY-1483 names that reviewed revision.

If Phase 0A differs, Team Lead does not dispatch Fullstack and reports the divergence. Team Lead does not reset, clean, stash, recreate, checkout, revert, amend, rebase, or silently normalize the preserved workspace/history.

**Phase 0B — dispatched Fullstack, before its first edit**:

- timestamp a separately attributable packet, record the current Fullstack run/task identity as the expected owner, and exclude only that current run from the ownership check;
- confirm no competing active or orphan process owns or writes the worktree;
- independently recheck every local-commit/worktree/metadata/PR field and current pattern inventory from Phase 0A;
- prove local commit `794624a…` remains a direct child of `f5690f…` and has not been amended, rebased, reset, or replaced.

If Phase 0B differs, Fullstack stops before editing, preserves the workspace unchanged, and reports the exact divergence to Team Lead. It does not reset, clean, stash, recreate, checkout, revert, amend, rebase, terminate an unverified competing process, or continue with a partial packet. No source byte may change until both phases agree.

**Phase 0C — forward-only excluded-file scope scrub**:

- before source edits, add or strengthen and run the three Stage D public-cache tracers for previous/candidate mismatch, cache-side anchor/timestamp ordering, and held B/c2 rejection/replay; record named mandatory RED evidence against the exact composite and record the resulting test blob (it may remain `28f96c…` only if existing assertions already prove every required observable);
- while manually editing only excluded service, preserve cache blob `206acca…` and that recorded post-RED test blob byte-for-byte;
- manually remove `public` from `prepareWorkoutSnapshot`, `prepareWorkoutChanges`, `acceptPreparedWorkoutFetch`, and `rejectPreparedWorkoutFetch`, and manually restore `private` on `persistedWorkoutAnchor` in excluded `HealthKitService.swift`;
- require `git hash-object Packages/HealthKitService/Sources/HealthKitService/HealthKitService.swift` to equal `4b1f809090c96185a8bf6befe1360bf30c6ec263` and `git diff --quiet f5690f1461a6cb07504d7f6e945220cb5213b2fb -- Packages/HealthKitService/Sources/HealthKitService/HealthKitService.swift` to exit 0;
- with service fixed at base and the post-RED tests unchanged, make the targeted owned-cache edit that returns `WorkoutPreparedDataProviding` to package-internal and removes `import HealthKit`, public `WorkoutCheckpointTracking`, its `currentWorkoutCheckpoint` conformance, `anchorOrderValue`, `isStalePreparedCheckpoint`, and all description/archive/`lastSyncDate` comparison; cache must evolve from `206acca…` without discarding other in-scope work;
- retain local commit `794624a…` as an ancestor and carry the inverse service edit into a later forward commit; do not create a cleanup commit that omits the owned recovery or expose an intermediate review candidate.

If exact service-base equality cannot be reached by those manual edits without changing other excluded behavior, Fullstack stops and reports infeasibility. Phase 0C is the sole permission to edit the excluded file and does not add it to final scope.

The three named public-cache RED tracers above are the sole executable-evidence exception: they run in the metadata-pinned workspace during Phase 0C before any source scrub. All remaining executable evidence runs in that workspace only after 0C exits. The first Stage A command records the actual `swift build` outcome. A nonzero result is recovery evidence, not a substitute for behavior RED; a zero proves only buildability. If RED, Fullstack fixes compilation only in `HealthDataCache.swift`; widening excluded witnesses is forbidden. The bridge must not restore legacy helpers or implement B settlement, C reset-drain, or remaining D publication outcomes before their mandatory evidence. `swift build` must be green before Stage A behavior tracers.

### Required removal and replacement map

| Rejected source/test state | Must be removed | Reviewed replacement | First exit gate that proves replacement |
|---|---|---|---|
| Committed/uncommitted access widening in excluded `HealthKitService.swift` | Four `public` modifiers plus lost `private` anchor-reader access | Manual exact base-blob scrub; package-internal prepared capability/conformance stays in `HealthDataCache.swift`; zero cumulative service diff | Phase 0C |
| `Synchronization`/Mutex-backed mutable waiter and in-flight reference helpers | Production import, lock-owned helper state, independent completion paths | Plain actor-owned transaction/waiter values plus one remove-before-resume settlement authority | Stage B |
| Continuation-holder provider-turn objects | Stored provider-turn continuation helpers and remove-without-resume cancellation | Actor-owned active/queued request identities with revocable lane ownership and successor pump | Stage C |
| `Task.yield`/timing coordination | Production polling and test yield/sleep interleaving evidence | Explicit provider-started, query-complete, cache-acceptance, acceptance-invocation, durable-advance, and release gates | Stages B–E |
| Request-order cache/currentness state | Entry field, global/per-key order maps, and order comparisons | Generation + semantic/range key + unique request identity in the transaction only | Stages B/D |
| Cache-side checkpoint decoding/ordering | `import HealthKit`, `WorkoutCheckpointTracking`, reconstructed anchors, description/archive parsing, anchor comparison, and `lastSyncDate` ordering | Opaque candidate; generation + semantic/range key + unique request identity alone decide currentness. Provider-owned private archive decoding in base `HealthKitService.swift` is unchanged | Stage D |
| Previous-checkpoint carry-forward and unconditional acceptance | Nil coalescing and acceptance call when no candidate exists | Store exactly the supplied optional candidate; legacy/nil/explicit results stay checkpoint-absent and call no acceptance | Stages D/E |
| Invalidated insensitive tests | Unchanged test blob and baseline/snapshot/cache-hit substitutes for anchored transaction evidence | Public-cache tracer bullets with explicit gates and recorded terminal outcomes | Stages A–E |

### Stage evidence ledger

Fullstack accumulates this ledger locally and publishes it in the single final implementation handoff; no progress comment substitutes for an exit gate. A tracer records exactly one evidence mode before its production change: mandatory RED with named test/command/nonzero exit/observable defect, or characterization-GREEN with named test/command/zero exit/strengthened observable assertions and proof that its production path is not changed by that tracer.

| Stage | Entry evidence | Test-first evidence before production change for that tracer | Exit evidence |
|---|---|---|---|
| A — semantic reconciliation | Stages 0A/0B match; 0C records D REDs, proves service base equality, preserves tests, and performs only the targeted cache seam cleanup; compiler preflight recorded; if RED, cache-only actor bridge makes `swift build` green without implementing B/C settlement or D publication outcomes | Mandatory RED for a missing/incorrect or changing production path; otherwise characterization-GREEN with strengthened semantic/UUID/empty/order assertions | Every case has eligible evidence; B/C defects and remaining D publication outcomes remain unimplemented; all Stage A cases green; worktree diff from local HEAD carries the inverse service scrub while cumulative diff from `f5690f…` contains only the two owned paths |
| B — caller settlement | Stage A exit plus named owner/non-owner/failure cases not yet satisfied | Explicit-gate cancellation/failure test fails or reaches its bounded no-hang guard; no direct private-state assertion | All registered callers record one terminal outcome; old waiter/in-flight locks, direct resume paths, and production yield polling absent; Stage A+B focused tests green |
| C — provider-lane reset | Stage B exit; active/queued request scenario scripted | Cancellation/supersession/invalidation/authorization-reset test proves the preserved design strands or blocks a waiter/successor | Old provider-turn continuation holder absent; affected callers cancel once; successor starts before stale release; late result rejects; A–C green |
| D — opaque checkpoint/replay | Stage C exit plus the three mandatory 0C RED transcripts; A/c1 and B/c2 script available | Reuse exact pre-change RED evidence; add a new RED only for any D behavior not covered by those transcripts | Tracking/anchor/timestamp seam remains absent; request order and carry-forward are removed; generation/key/request identity alone governs currentness; exact candidate publication, rejection/replay/invocation/silent-lag transcript recorded; A–D green |
| E — complete matrix | Stage D exit; remaining scenario list enumerated | Mandatory RED for any missing/incorrect or changing path; otherwise characterization-GREEN with strengthened legacy/nil/range/restart/failure/stale assertions | Every spec scenario/edge passes; test blob differs from base `9bdc7a5…` and current `28f96c…`; existing privacy suite passes unchanged; no sleep/yield timing evidence; A–E green |
| F — Fullstack delivery gate | Complete A–E ledger; final cache differs from lineage blobs; final tests differ from base/current blobs; service equals `4b1f809…`; obsolete-pattern audit clean | Not applicable—F verifies the assembled implementation candidate | Local package gate passes; cumulative `f5690f…` diff is exactly cache+tests; new forward SHA descends from `794624a…`; local/tracking/remote/PR equality and Draft state proven; Fullstack authors the exact-SHA Multica review request |

Mandatory defect RED evidence remains non-negotiable for the five repeated P1 families:

1. Stage 0's fail-on-match audit of immutable committed `f5690f…` is structurally RED for unsafe-Sendable/Mutex-owned mutable waiter state; the local/dirty audits prove the removal is retained rather than restored.
2. Stage B must expose the multiple/independent waiter-completion path through an explicit-gate public-cache test before centralizing remove-before-resume settlement.
3. Stage C must expose the continuation-holder lane's stranded caller or blocked successor under cancellation/invalidation before replacing it with revocable request-ID lanes.
4. Stage D must expose the cache-entry/candidate-checkpoint mismatch caused by previous-checkpoint carry-forward before publishing the exact candidate.
5. Stage D must expose cache-side checkpoint decoding/comparison defeating request-identity currentness and anchored replay before removing those heuristics.

The anchored B/c2 rejection/replay tracer in Stage D is also mandatory RED. Static pattern evidence alone cannot substitute for the behavior REDs in items 2–5. Characterization-GREEN is permitted only for other already-correct behavior whose production path is unchanged by its tracer.

### Genuinely new-SHA gate

A candidate is not reviewable or shippable unless all conditions hold:

The forward composite has no synthetic tree OID. Equality means: local HEAD `794624a…`; parent/tracking/remote/PR `f5690f…`; local commit cache/service blobs `7956e0b…`/`77fb965…` with `+117/−731` and `+4/−4`; dirty cache/service/test blobs `206acca…`/`b824427…`/`28f96c…` with `+119/−24`, `+1/−1`, and `+36/−8`; and matching owner metadata.

- final HEAD differs from `d853728…`, `f5690f…`, and `794624a…`, and `794624a…` remains its ancestor;
- final `HealthKitService.swift` blob equals `4b1f809090c96185a8bf6befe1360bf30c6ec263` and its cumulative diff from `f5690f…` is empty;
- cumulative diff from `f5690f…` contains exactly `HealthDataCache.swift` and `HealthWorkoutCacheTests.swift`; no conditional third file is authorized;
- final cache blob differs from `be0963652c349210fa39a898cfecf47f13bf710f`, `7f1f162ef166aa6f841e3746fff3fa3ea40ba069`, `7956e0b06d9d38b73f2ab088ed87f4967b33a961`, and `206acca959568e56ca3aaf62ee764f04b0aa2392`;
- final test blob differs from `9bdc7a5fd2b528b8f9273395480d9efa02625616` and `28f96c751553f7bf39d16c62ad5394ebfe74c96d`;
- the obsolete production/test patterns in the removal map are absent;
- `swift build && swift test` passes from `Packages/HealthKitService`;
- local HEAD, tracking branch, pushed remote OID, and PR #423 `headRefOid` are byte-identical at the new SHA;
- PR #423 remains Draft/auto-merge-disabled until Fullstack obtains an exact-SHA Multica AI Reviewer PASS or PASS WITH FOLLOW-UP at that same head; PR Manager is blocked before that verdict.

After same-head Multica PASS, Team Lead hands the unchanged head to PR Manager. PR Manager—not Fullstack—owns repository-required CI/build/test/lint/hook supervision, merge readiness, and shipping. Any head change invalidates the verdict/equality packet and returns the work to Fullstack plus exact-SHA review before PR Manager continues.

An empty commit, history rewrite, loss of `794624a…`, a tree equal to any invalidated/local/composite state, nonempty service diff, unchanged current cache/test blobs, extra path, same-SHA re-request, focused-test-only result, claimed audit without byte evidence, review request authored by anyone other than Fullstack, or PR Manager handoff before same-head Multica PASS fails readiness and returns to Team Lead.

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
| Logging leaks workout details | Keep only aggregate query type/count/duration and run existing privacy coverage unchanged; no third-file edit is authorized. |
| Scope grows into workout persistence/refresh policy | L2 workout persistence, observer sync, and TTL remain explicit non-goals. |
| Fullstack reports progress or package green without replacing rejected bytes | Stage exit requires named RED→GREEN or eligible characterization-GREEN evidence plus source/test removal proof; every repeated P1 retains mandatory RED, and Stage F requires both mandatory file blobs to differ from `f5690f…`. |
| Same invalidated tree is recommitted or re-reviewed | New-SHA gate rejects both invalidated SHAs, empty/same-tree commits, and any review request without four-way equality at a non-invalidated head. |
| Current local/dirty recovery is mistaken for completed remediation | Stage 0 pins commit/worktree/owner blobs; Stage F requires evolution beyond `206acca…`/`28f96c…`, zero service diff, clean patterns, and full package GREEN. |
| Local commit is discarded to simplify cleanup | Require `794624a…` to remain an ancestor; allow only forward commits and manual file edits, never reset/checkout/stash/revert/amend/rebase. |
| Excluded service access widening survives because it is already committed | Phase 0C manually returns all five modifiers to base and requires exact service blob `4b1f809…` plus zero cumulative service diff before A–F completion. |

## Constitution Check — After Design

All pre-design gates remain PASS. The design uses the existing `HealthDataCache` actor as the sole transaction module, preserves dependency direction/public call shapes/file ownership, keeps the prepared capability package-internal, removes the need for unsafe concurrency exceptions, and defines exact package-local verification. No constitution exception or ADR is required.

## Complexity Tracking

No constitution violations require justification.
