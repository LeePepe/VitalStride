# Quickstart: MY-1477 implementation and verification

## Preconditions

- Work only in the daemon-provided worktree.
- Read `.specify/memory/constitution.md`, `AGENTS.md`, and `Packages/HealthKitService/CONTEXT.md`.
- Keep the diff within the files declared by `tasks.md`.
- Do not run `xcodebuild`; this is a package-only change.
- Preserve Draft PR #423, local commit `794624a2516e60c461cb8a598d95c67e7df6b3b5`, and the exact three-path worktree as forward-only evidence. Do not reset, clean, stash, checkout, revert, amend, rebase, or recreate it.
- Planner changes no source file. Fullstack replaces the invalidated transaction/waiter design through the staged public-cache behavior below rather than patching isolated review lines.
- Immediately before dispatch, Team Lead records local `794624a…`, parent/tracking/remote/PR `f5690f…`, the exact local-commit and three dirty-file blobs/numstats, recovery owner metadata `113937f4-8a72-44cf-867b-ade6cee55a6e`, no active/orphan owner, and the exact reviewed planning revision.
- After dispatch but before editing, Fullstack identifies/excludes only its own run and rechecks the entire packet. Phase 0C then manually removes every committed/uncommitted excluded service delta before A–F.

## Stage 0 Baseline Packet

**Phase 0A — Team Lead immediately before dispatch** records a timestamped packet attributable to that Team Lead run:

- local HEAD `794624a2516e60c461cb8a598d95c67e7df6b3b5`; parent/tracking/remote/PR `f5690f1461a6cb07504d7f6e945220cb5213b2fb`; PR OPEN Draft → `main`, no auto-merge;
- local commit paths: cache `+117/−731`, blob `7956e0b06d9d38b73f2ab088ed87f4967b33a961`; excluded service `+4/−4`, blob `77fb965f34cf0da6dab0052ab66630f11ddddf1e`; test blob `9bdc7a5fd2b528b8f9273395480d9efa02625616`;
- exactly three dirty paths relative to HEAD: cache `+119/−24`, blob `206acca959568e56ca3aaf62ee764f04b0aa2392`; excluded service `+1/−1`, blob `b8244271b30a51da04a41e6eb28d9c5faf6e156e`; tests `+36/−8`, blob `28f96c751553f7bf39d16c62ad5394ebfe74c96d`;
- metadata local head/dirty cache/owner `794624a…` / `206acca…` / `113937f4…`, owner authority comment `7c73c678-c3b6-48f3-8eb7-7f272823083a`, no active/orphan owner, and current pattern inventory;
- the exact reviewed planning revision; Team Lead replaces the superseded `stage_0a_packet` only after planning PASS.

If 0A diverges, Team Lead does not dispatch and reports the exact mismatch without changing the workspace or history.

**Phase 0B — dispatched Fullstack before its first edit** records a separate timestamped packet attributable to its current run/task identity, excludes only that run, proves no competing active/orphan owner, rechecks every 0A field, and proves `794624a…` remains the direct child of `f5690f…`. Any divergence stops before edit without normalization, history rewrite, or unverified-process termination.

**Phase 0C — forward-only excluded-file scope scrub** first adds/strengthens and runs mandatory REDs for previous/candidate mismatch, cache anchor/timestamp ordering, and held B/c2 rejection/replay, then records the post-RED test blob. While cache `206acca…` and that test blob remain exact, manually remove `public` from four prepared-fetch methods and restore `private` on `persistedWorkoutAnchor`; require service blob `4b1f809090c96185a8bf6befe1360bf30c6ec263` and zero cumulative service diff. With service fixed and post-RED tests unchanged, return cache `WorkoutPreparedDataProviding` to package-internal and delete `import HealthKit`, `WorkoutCheckpointTracking`, its service conformance, anchor reconstruction/description parsing, and `lastSyncDate` comparison. No reset/checkout/stash/revert/amend/rebase; `794624a…` remains an ancestor.

All executable evidence runs in the metadata-pinned workspace after 0C. First record actual `swift build`; compiler status proves no behavior. If RED, repair only `HealthDataCache.swift`, never excluded witness access, before behavior tracers.

## Execution Order

1. Confirm delivered T023-001 remains unchanged.
2. Capture matching Stage 0A/0B packets for the exact local-commit/worktree composite.
3. **Phase 0C — scope scrub**: capture three D behavior REDs; manually return excluded service to `4b1f809…` while cache/tests are preserved; then remove the cache public tracking/ordering seam while service/tests remain fixed.
4. **Stage A — result semantics and reconciliation**: record package buildability after 0C; repair compilation only in cache-owned code if needed; then run strengthened public-cache cases for A→empty, anchored-intent→baseline, UUID add/update/delete, unknown deletion, duplicate UUIDs, repeated-delta idempotency, deletion-wins, empty snapshot, and equal-time order.
5. **Stage B — exactly-once caller settlement**: require explicit-gate RED for multiple/independent completion; then implement actor-owned registration/settlement and cover same-key coalescing, non-owner cancellation, owner cancellation, and shared provider failure without hang, double resume, sleep, or yield polling.
6. **Stage C — provider-lane cancellation and reset**: require RED for a stranded caller/blocked successor; then implement actor-owned request-ID lanes and cover refresh supersession, workout/full invalidation, and authorization revocation while stale provider work remains held.
7. **Stage D — checkpoint publication/invocation and anchored replay**: consume the three mandatory 0C REDs, remove remaining request-order/carry-forward behavior, and implement exact opaque candidate publication plus matching acceptance before success; generation + semantic/range key + request identity alone decide currentness.
8. **Stage E — remaining deterministic matrix**: classify explicit→default rebuild, wider coverage, non-coalescing keys, restart, failure preservation, stale completion, legacy fallback, nil checkpoint, and aggregate-only logging through the existing unchanged privacy suite.
9. Run focused tests after every tracer, then the full package, exact-two-file, lineage-blob, new-tree, same-head, and Multica review gates.

For every stage, entry evidence is the prior stage's exit plus a named next tracer. Before production change, classify and record exactly one mode: (a) mandatory RED→GREEN with test name, command, nonzero exit, and observable defect when behavior is missing/incorrect or its path will change; or (b) characterization-GREEN with test name, command, zero exit, strengthened observable assertions, and proof that the path remains unchanged. Never introduce a regression or mix in another defect to manufacture RED. Exit evidence records the focused GREEN command/exit, replacement or unchanged-path proof, prior-stage regression set, and current allowlisted diff. Accumulate this ledger for the final Fullstack handoff; do not post a progress-only comment.

### Stage-specific entry and exit evidence

- **A entry**: 0A/0B match; 0C has D REDs, service blob/base-diff gate, preserved tests, and targeted cache seam cleanup; compiler preflight recorded. **A exit**: semantic/UUID/empty/order tracers have eligible evidence, B/C and remaining D publication outcomes stay unimplemented, Stage A green.
- **B entry**: A green plus failing owner/non-owner/failure cases. **B exit**: one terminal outcome per caller; old waiter/in-flight lock state, direct second resume, and production yield polling absent; A+B green.
- **C entry**: B green plus failing active/queued reset case. **C exit**: no provider-turn continuation holder; cancellation, invalidation, and authorization reset settle all affected callers once; successor starts before stale release; A–C green.
- **D entry**: C green plus the three 0C RED transcripts and scripted A/c1→B/c2. **D exit**: tracking/anchor/timestamp seam stays absent; request order/carry-forward removed; generation/key/request identity alone decides currentness; exact candidate rejection/replay/invocation/silent-lag transcript recorded; A–D green.
- **E entry**: D green plus enumerated remaining cases. **E exit**: full matrix green, existing privacy tests pass unchanged, no timing/yield evidence remains, and test blob differs from `9bdc7a…` and current `28f96c…`.
- **F entry**: complete A–E ledger; cache differs from `be096365…`, `7f1f162…`, `7956e0b…`, and `206acca…`; tests differ from `9bdc7a5…` and `28f96c…`; service equals `4b1f809…`. **F exit**: cumulative diff exactly cache+tests, full package/pattern gates, new forward SHA descends from `794624a…`, four-way equality, Draft state, Fullstack-authored exact-SHA review, and same-head Multica PASS before PR Manager.

## Required Regression Matrix

- Baseline A → empty changes → A remains.
- Baseline A → add B + delete A → only B.
- Existing UUID → changed record → one updated record.
- Unknown deletion → cache-accepted state unchanged; duplicate UUIDs in one provider response → one deterministic record.
- Repeat the same changes → identical result.
- Empty authoritative snapshot → accepted empty entry; empty anchored changes → prior records retained.
- Same timestamps → UUID tie-breaker is stable.
- Empty process cache with persisted-anchor behavior → baseline requested.
- Default 30-day coverage → wider range fetches a snapshot.
- Explicit range → later default request rebuilds a compatible baseline.
- Different ranges/semantics → no incorrect task coalescing.
- Provider-complete delta held before acceptance → same-semantic supersession → rejected checkpoint is not persisted and the next read still obtains the delta.
- Replacement provider read observes c1 → replay B → cache publishes A+B with candidate c2 → provider acceptance for c2 is invoked → success waiters complete.
- Forward opaque checkpoint c1→c2 is accepted solely by current request identity; no cache-side anchor/timestamp ordering.
- Non-owner coalesced cancellation completes once and leaves owner/peers running; owner cancellation retires the request and completes every attached waiter once.
- Active/queued provider-lane cancellation, refresh supersession, `invalidateWorkouts()`, and `invalidateAll()` release all affected callers and let current successor work start before stale provider return.
- Authorization revocation follows the same full-reset drain and cannot leave a provider lane or caller suspended.
- Late cancelled or invalidated work → reject only; no stale cache/checkpoint commit or newer ownership cleanup.
- Provider error → every attached waiter fails once and the prior cache-accepted state remains.
- Silent no-advance after acceptance invocation → prior durable checkpoint replay is UUID-idempotent and later acceptance invocation may retry c2; no durable-success assertion is made.
- Legacy snapshot fallback and nil-checkpoint prepared baseline/change → valid records/coverage/provenance, accepted checkpoint absent, and no checkpoint acceptance invocation.

## Focused Verification

From the repository root, use Swift Testing filters appropriate to the final suite names, including the existing workout-cache suite and provider-contract suite. All compiler and test evidence runs in the metadata-pinned workspace; compiler status is not behavior evidence. For every tracer bullet, record its eligible evidence mode before starting the next case. The five repeated P1 families require mandatory RED evidence: unsafe-Sendable/Mutex-owned waiter state (committed-base static audit plus retained deletion), multiple/independent completion (B), stranded continuation-holder lanes (C), previous/candidate entry mismatch (D), and checkpoint decoding/comparison defeating currentness/replay (D). Anchored B/c2 rejection/replay in D is also mandatory RED. Explicit gates, not wall-clock sleeps or `Task.yield`, establish interleavings.

## Required Layer Gate

Working directory: `Packages/HealthKitService`

```bash
swift build && swift test
```

Acceptance requires exit code 0 for both commands. Do not substitute an AppUI build or simulator test.

## Removal and New-SHA Gates

Before commit, the cache/test audit must show no rejected transaction pattern: no `Synchronization`/Mutex-owned waiter state, continuation-holder turn, timing-yield coordination, request-order currentness, HealthKit checkpoint tracking/reconstruction, anchor description/archive/timestamp ordering, previous-checkpoint carry-forward, or unconditional acceptance for nil candidates.

The forward composite has no synthetic tree OID. It is the exact local HEAD/parent/tracking/remote/PR relationship plus the local-commit and three dirty-file blobs/numstats recorded in Stage 0A.

After commit/push:

- HEAD differs from `d853728…`, `f5690f…`, and `794624a…`, with `794624a…` retained as an ancestor;
- final service blob equals base `4b1f809090c96185a8bf6befe1360bf30c6ec263`, and cumulative service diff from `f5690f…` is empty;
- cumulative diff from `f5690f…` contains exactly cache source and cache tests;
- final cache differs from `be096365…`, `7f1f162…`, `7956e0b…`, and `206acca…`; final tests differ from `9bdc7a5…` and `28f96c…`;
- local HEAD, tracking OID, pushed remote OID, and PR #423 head are identical;
- repository-required PR checks/reviews are green at that same head;
- PR remains Draft with auto-merge disabled until same-head Multica PASS;
- Fullstack—not Planner or PR Manager—authors the exact-SHA review request with planning authority, package, scope, lineage-blob, and same-head evidence;
- PR Manager is not invoked before the Multica PASS comment names the exact PR head.

History rewrite, lost `794624a…` ancestry, nonempty service diff, any extra path, composite-equivalent/unchanged current cache or test, same-SHA request, empty commit, focused-only evidence, or PR Manager routing before same-head Multica PASS fails the gate.

## Diff Audit

Before handoff, confirm:

- cumulative diff from `f5690f…` contains exactly `HealthDataCache.swift` and `HealthWorkoutCacheTests.swift`; `PrivacyLoggingTests.swift` remains unchanged;
- `workoutData(in:)`, `refreshWorkouts(in:)`, and direct `fetchWorkouts(dateRange:)` call shapes remain source-compatible;
- direct service fetches are anchor-free snapshots and do not independently read/advance the default workout anchor;
- the precise prepared-fetch capability/conformance is package-internal in `HealthDataCache.swift`; `HealthKitService.swift` hashes to `4b1f809…` and has no cumulative T023-002 diff;
- existing public provider adapters remain snapshot-only, and prepared acceptance uses the result's declared semantic when preparation falls back to a baseline;
- prepared cache-facing fetches do not persist checkpoints before acceptance;
- only the current request instance publishes cache state and then synchronously invokes provider acceptance for its checkpoint;
- the accepted immutable entry records the same opaque candidate checkpoint submitted to provider acceptance before success settlement; this is not treated as a persistence receipt;
- a provider adapter that records the acceptance call but deliberately leaves durable state unchanged causes a later query from the prior checkpoint and safe UUID-idempotent replay;
- legacy fallback and nil-checkpoint prepared results publish checkpoint-absent entries and do not invoke checkpoint acceptance;
- all request, waiter, and provider-lane mutable state is actor-owned and every continuation completion uses one remove-before-resume authority;
- cancellation/invalidation drains active and queued callers and a late non-cooperative result is rejected without blocking a successor;
- production `HealthDataCache.swift` has no `import HealthKit`, `WorkoutCheckpointTracking`, reconstructed anchor, description/archive/timestamp ordering, request order, `Synchronization`, locks, unsafe Sendable annotation, or yield polling for transaction state;
- changed test support uses compiler-checked Sendable state and explicit gates; the final production and test files contain no `@unchecked Sendable`, `@preconcurrency`, or `nonisolated(unsafe)` bypass;
- no health values/details were added to logs;
- no unsafe concurrency annotation was introduced;
- no AppUI, schema, WatchConnectivity, generated Xcode project, or project configuration file changed.
