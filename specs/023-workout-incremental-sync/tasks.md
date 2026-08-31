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
- [ ] T023-002 [US1] Continue forward from preserved local `794624a…` and its exact dirty composite: manually scrub every inherited `HealthKitService.swift` delta back to base without history rewrite, then complete one actor-isolated request transaction, package-internal prepared capability, result-semantic UUID reconciliation, exactly-once waiters, revocable request-ID lanes, opaque candidate acceptance, deterministic ordering, and generation/key/request currentness in exactly `Packages/HealthKitService/Sources/HealthKitService/HealthDataCache.swift` and `Packages/HealthKitService/Tests/HealthKitServiceTests/HealthWorkoutCacheTests.swift`

### Task Metadata

| Field | T023-001 | T023-002 |
|---|---|---|
| Owning layer | HealthKitService | HealthKitService |
| Context pointer | `Packages/HealthKitService/CONTEXT.md` Types + Service roles | `Packages/HealthKitService/CONTEXT.md` Service role and L1 whole-entry red line |
| Slice | US1 | US1 |
| Blocking tasks | None | T023-001 |
| Files in scope | `HealthWorkoutRecord.swift`; `HealthKitService.swift`; new `HealthWorkoutQueryContractTests.swift` | Exactly `HealthDataCache.swift`; `HealthWorkoutCacheTests.swift` |
| Files/layers excluded | `HealthDataCache.swift`; AppUI; VitalModels; WatchConnectivity; workout-session/write/delete flows | `HealthKitService.swift` final behavior/diff, with one manual base-blob scrub exception for inherited deltas; `PrivacyLoggingTests.swift`; `HealthWorkoutRecord.swift`; AppUI; VitalModels; WatchConnectivity; workout-session/write/delete flows |
| Contract impact | Define concrete prepared result/service behavior; direct service calls become anchor-free snapshots while keeping existing public call shapes source-compatible | Add the package-internal prepared capability/conformance in its cache-owned file and one actor-owned transaction/settlement/provider-lane module; retain public snapshot-only fallback and introduce no public provider/witness/AppUI API; treat checkpoints as opaque, record a candidate only when supplied, invoke provider acceptance only for a supplied candidate before caller success, and keep legacy/nil-checkpoint results checkpoint-absent |
| Task-local acceptance | Service tests prove anchor-free baseline preparation, anchored changes preparation, anchor-free explicit range, concrete snapshot coverage, prepared fetch does not persist, explicit acceptance persists when possible, discard does not, and direct call remains source-compatible without reading/advancing the anchor | Manual service scrub yields exact blob `4b1f809…` and zero cumulative service diff; package-internal cache capability with no public witness widening; per-tracer RED→GREEN/eligible characterization; mandatory repeated-P1 and anchored-replay REDs; zero unsafe annotations/locks/yield polling; generation/key/request-only currentness with no cache HealthKit/tracking/archive/timestamp comparison; actual result semantic; nil/legacy absence; exactly-once waiters; revocable lanes; A/c1→rejected B/c2→replay→A+B/c2 acceptance before success; silent-lag replay; full UUID/range/restart/failure/order matrix; existing privacy suite unchanged |
| Exact verification | From `Packages/HealthKitService`: `swift build && swift test` | From `Packages/HealthKitService`: `swift build && swift test` |

**Checkpoint**: US1 is complete only after T023-001 and T023-002 both pass the full package gate.

### Sequential Test-First Stages Within T023-002

These are one non-parallelizable implementation task because every stage owns the same production/test files and must reuse Draft PR #423 plus the pinned delivery workspace. Complete one named test-first tracer before adding the next: RED→GREEN for missing/incorrect behavior or a changing production path, or strengthened characterization-GREEN for an already-correct unchanged path. Never manufacture RED.

**Stage 0A — Team Lead pre-dispatch**: after exact planning PASS, replace the superseded metadata packet with a timestamped composite containing local HEAD `794624a2516e60c461cb8a598d95c67e7df6b3b5`; parent/tracking/remote/PR `f5690f1461a6cb07504d7f6e945220cb5213b2fb`; PR OPEN Draft/`main`/no-auto-merge; recovery owner `113937f4-8a72-44cf-867b-ade6cee55a6e`; no active/orphan owner; local-commit cache/service `+117/−731` and `+4/−4` blobs `7956e0b…`/`77fb965…`; and exactly three dirty paths—cache `+119/−24` blob `206acca…`, excluded service `+1/−1` blob `b824427…`, tests `+36/−8` blob `28f96c…`. If any field differs, do not dispatch; report without reset/clean/stash/checkout/revert/amend/rebase.

**Stage 0B — Fullstack post-dispatch/pre-edit**: record a separate timestamped packet for its current run, exclude only itself, prove no competing active/orphan owner, recheck every 0A field/pattern, and prove `794624a…` remains the direct child of `f5690f…`. Divergence stops before edit without normalization, history rewrite, or unverified-process termination.

**Stage 0C — forward-only scope scrub**: before source edits, add/strengthen and run mandatory public-cache REDs for previous/candidate mismatch, cache anchor/timestamp ordering, and held B/c2 rejection/replay; record the post-RED test blob, which may remain `28f96c…` only if existing assertions prove every observable. While cache `206acca…` and that test blob remain exact, manually remove `public` from four prepared-fetch witnesses and restore `private` on `persistedWorkoutAnchor`; require `git hash-object Packages/HealthKitService/Sources/HealthKitService/HealthKitService.swift` = `4b1f809090c96185a8bf6befe1360bf30c6ec263` and `git diff --quiet f5690f1461a6cb07504d7f6e945220cb5213b2fb -- Packages/HealthKitService/Sources/HealthKitService/HealthKitService.swift` exit 0. Then keep service/post-RED tests fixed while cache returns `WorkoutPreparedDataProviding` to package-internal and removes `import HealthKit`, `WorkoutCheckpointTracking`, `currentWorkoutCheckpoint`, `anchorOrderValue`, `isStalePreparedCheckpoint`, and all description/archive/`lastSyncDate` comparison. Carry the inverse service edit into a forward commit above `794624a…`; no reset/checkout/stash/revert/amend/rebase. Inability to reach exact base equality is an infeasibility stop.

All executable evidence runs in the metadata-pinned delivery workspace after 0C. Record actual `swift build`; compiler status proves no behavior. If RED, repair only `HealthDataCache.swift` and never widen excluded service witnesses. Do not pre-implement B settlement, C reset-drain, or D checkpoint outcomes before their mandatory behavior REDs.

Each stage starts only after the previous exit. For its next tracer, record either the named RED command/nonzero exit/observable defect before relevant production change, then GREEN; or a named characterization-GREEN command/zero exit/strengthened assertions plus unchanged-path proof. Record the replacement diff and prior-stage regression result. Mandatory RED remains for the five repeated P1 families: unsafe-Sendable/Mutex-owned waiter state (Stage 0 fail-on-match audit), multiple/independent completion (B), stranded continuation-holder lanes (C), previous/candidate entry mismatch (D), and checkpoint decoding/comparison defeating currentness/replay (D). Anchored B/c2 rejection/replay in D is also mandatory RED. Accumulate the ledger for the single final handoff; a progress comment, package-green claim, or audit claim without byte evidence is not an exit.

1. **Stage A — semantic reconciliation foundation**
   - Test-first: A→empty delta, prepared anchored intent returning a baseline, then UUID add/update/delete, unknown deletion, duplicate provider UUIDs, deletion-wins, repeated-delta idempotency, empty authoritative snapshot, and equal-time UUID ordering one case at a time; use RED only if missing/incorrect or changing, otherwise characterization-GREEN.
   - GREEN: minimal prepared-result semantic transition and whole-entry normalized reconciler.
   - Entry: 0A/0B agree; 0C records D REDs, proves service base equality, preserves tests, and performs only targeted cache seam cleanup; compiler preflight recorded; if RED, cache-only repair makes `swift build` green without implementing B/C or remaining D outcomes.
   - Exit: every listed behavior has eligible evidence; B/C and remaining D outcomes stay unimplemented; focused Stage A passes; worktree diff from local HEAD includes the inverse service scrub while cumulative diff from `f5690f…` contains only the two owned files.
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
   - Mandatory REDs: consume the exact 0C transcripts for previous/candidate mismatch, cache anchor/timestamp ordering, and anchored B/c2 rejection/replay; add RED only for uncovered D behavior.
   - GREEN: keep the tracking/anchor/timestamp seam absent, remove request order/carry-forward, use generation + semantic/range key + request identity only, publish one whole entry with the exact candidate, synchronously invoke matching acceptance, then settle callers; silent no-advance replays c1 and resubmits c2.
   - Entry: Stage C exit plus the three 0C RED transcripts and scripted A/c1/query-complete B/c2.
   - Exit: cache contains no HealthKit/tracking/archive/timestamp/request-order/carry-forward currentness seam; private provider-owned base decoding unchanged; rejection/replay/invocation/silent-lag transcript recorded; A–D pass.
5. **Stage E — remaining deterministic acceptance matrix**
   - Test-first individually: explicit-range→default rebuild, default coverage versus wider range, different semantic/range requests not coalescing, persisted-anchor restart baseline rebuild, provider failure preservation, stale completion, legacy snapshot-only compatibility, nil-checkpoint prepared results, and aggregate-only logging through existing unchanged privacy coverage.
   - Entry: Stage D exit plus the next named matrix behavior and declared evidence mode.
   - Exit: all scenarios pass without timing synchronization; existing privacy tests pass unchanged; test blob differs from `9bdc7a5…` and current `28f96c…`; A–E pass.
6. **Stage F — package and diff gate**
   - From `Packages/HealthKitService`, run `swift build && swift test`.
   - Cumulative `f5690f…` diff is exactly cache+tests; no conditional third file; no `xcodebuild`.
   - Entry: complete A–E ledger; service equals `4b1f809…`; final cache differs from `be096365…`, `7f1f162…`, `7956e0b…`, `206acca…`; final tests differ from `9bdc7a5…`, `28f96c…`; obsolete-pattern audit empty.
   - Audit cache/tests for zero unsafe annotations, HealthKit/tracking/archive/timestamp ordering, locks/`Synchronization`, continuation-holder turns, request order, prior-checkpoint carry-forward, or timing yield/sleep coordination.
   - Exit: commit/push a new SHA above `794624a…`; prove ancestry, local/tracking/remote/PR equality, Draft/no-auto-merge, exact-two-file diff, and same-head required checks green; Fullstack requests exact-SHA Multica review and PR Manager waits for same-head PASS.

### Mandatory Removal/Replacement Preconditions

| Rejected state that must not survive or be restored | Must replace with | Required exit |
|---|---|---|
| Four committed public witness modifiers plus uncommitted loss of `private` in excluded service | Manual exact base-blob scrub; package-internal capability/conformance in cache; zero cumulative service diff | 0C |
| Historical `Synchronization`/Mutex mutable waiter definitions already deleted by the dirty partial, plus surviving waiter/in-flight consumers | Retain the deletion and replace every consumer with actor-owned transaction/waiter values and one remove-before-resume settlement funnel | B |
| Historical provider-turn holder definitions already deleted by the dirty partial, plus surviving continuation-holder calls/dictionaries | Retain the deletion and replace every consumer with actor-owned active/queued request identities and revocable lane pump | C |
| Production/test `Task.yield` or sleep coordination | Explicit provider/query/acceptance/durable/release gates | B–E |
| Request-order cache/currentness state | Generation + key + request identity in transaction state only | B/D |
| Cache `import HealthKit`, tracking protocol/conformance, reconstructed anchor, description/archive parsing, anchor/`lastSyncDate` comparison | Opaque candidate governed only by generation + key + request identity; provider-private base archive decoding unchanged | D |
| Previous-checkpoint carry-forward/unconditional acceptance | Exact optional candidate; nil/fallback/explicit entries checkpoint-absent with no acceptance call | D/E |
| Unchanged invalidated test blob | Reviewed public-cache A–F tracer matrix | A–E |

### Genuinely New-SHA Gate

The forward composite is `{local 794624a…, parent/tracking/remote/PR f5690f…, commit cache/service 7956e0b…/77fb965…, dirty cache/service/tests 206acca…/b824427…/28f96c… with recorded numstats and owner metadata}`; no synthetic tree OID is required.

- Reject HEAD equal to `d853728…`, `f5690f…`, or `794624a…`, or a final head that does not retain `794624a…` as ancestor.
- Reject service blob not equal to `4b1f809…`, nonempty cumulative service diff, or any cumulative path beyond cache+tests.
- Reject cache blob equal to `be096365…`, `7f1f162…`, `7956e0b…`, or `206acca…`; reject test blob equal to `9bdc7a5…` or `28f96c…`.
- Reject empty/composite-equivalent commits, focused-only evidence, nonempty pattern audit, non-Fullstack review routing, same-head mismatch, or PR Manager routing before same-head Multica PASS.
- Only a new equal SHA with full package pass, exact-two-file diff, clean pattern audit, preserved ancestry, same-head required checks green, Draft/no-auto-merge PR, Fullstack-authored review, and same-head Multica PASS may leave Stage F.

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

- Preserve local commit `794624a…` and its three dirty paths exactly through 0A/0B; continue only forward in the metadata-pinned workspace. Never reset, clean, stash, checkout, revert, amend, or rebase. Manually scrub excluded service to base in 0C while preserving cache/test bytes, then carry that inverse into the final forward commit.
- Follow the sequential stages above. Missing/incorrect or changing behavior must be observed RED before minimal GREEN; already-correct unchanged behavior gets strengthened characterization-GREEN and ongoing regression coverage. Never manufacture RED or bulk-write the matrix horizontally.
- Test through public cache calls and the prepared-provider system seam. Deterministic adapters use compiler-checked Sendable state and distinct provider-started/query-complete/cache-acceptance/acceptance-invocation/durable-advance/release gates; no sleep or yield synchronization.
- The adversarial test must hold an anchored result after the provider method completes but before cache acceptance, reject c2, prove the replacement reads from durable c1, then observe A+B/c2 publication and matching acceptance invocation before caller success. A separate silent-no-advance case must keep durable c1 and prove another idempotent replay/submission.
- Preserve whole-entry immutable assignment; do not mutate the published workout array in place.
- Keep the prepared capability/conformance package-internal in `HealthDataCache.swift`; the only excluded-service edits are the five manual inverse access changes required to reach base blob `4b1f809…` and zero cumulative diff.
- Treat legacy public providers as anchor-free snapshot-only adapters, and drive acceptance from the prepared result's actual semantic when an anchored preparation falls back to baseline.
- Keep all production request/waiter/provider-lane mutation inside `HealthDataCache`; one settlement authority removes before resume, reset drains before discard, and checkpoints remain opaque.
- Do not add workout L2 persistence, TTL/observer refresh policy, UI changes, or broad sample-cache refactors.
- If an implementation fact makes the reviewed contract infeasible, stop and return evidence to Team Lead/Planner rather than widening scope.
