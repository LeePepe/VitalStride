# Quickstart: MY-1477 implementation and verification

## Preconditions

- Work only in the daemon-provided worktree.
- Read `.specify/memory/constitution.md`, `AGENTS.md`, and `Packages/HealthKitService/CONTEXT.md`.
- Keep the diff within the files declared by `tasks.md`.
- Do not run `xcodebuild`; this is a package-only change.
- Preserve Draft PR #423 with auto-merge disabled, historical invalidated SHA `d85372895fd4561aba3185e31605076d9429d517`, base HEAD `f5690f1461a6cb07504d7f6e945220cb5213b2fb`, and the authorized dirty partial repair as evidence. Reuse that exact metadata-pinned workspace without reset or recreation.
- Planner changes no source file. Fullstack replaces the invalidated transaction/waiter design through the staged public-cache behavior below rather than patching isolated review lines.
- Immediately before dispatch, Team Lead confirms base HEAD/tracking/remote/PR `f5690f…` equality plus the sole authorized dirty `HealthDataCache.swift` fingerprint: cancelled owner `1051db56-e454-4640-ac24-6d013586cf49`, blob `7f1f162ef166aa6f841e3746fff3fa3ea40ba069`, numstat `+4/−207`, unchanged test blob `9bdc7a5fd2b528b8f9273395480d9efa02625616`, and exact reviewed planning revision.
- After dispatch but before editing, Fullstack records its current run/task as the expected owner, excludes only itself, confirms no competing active/orphan process, and matches the exact dirty packet. Each phase has the fail-closed handling below; neither may reset, clean, recreate, re-checkout, restore the committed source blob, or force the workspace to match.

## Stage 0 Baseline Packet

**Phase 0A — Team Lead immediately before dispatch** records a timestamped packet attributable to that Team Lead run:

- delivery worktree, branch, local HEAD, tracking OID, pushed remote OID, PR head/target/Draft/auto-merge state;
- cancelled source owner task `1051db56-e454-4640-ac24-6d013586cf49`, matching metadata attribution, and absence of any later source-authorized/current process;
- sole dirty path `Packages/HealthKitService/Sources/HealthKitService/HealthDataCache.swift`, worktree blob `7f1f162ef166aa6f841e3746fff3fa3ea40ba069`, committed blob `be0963652c349210fa39a898cfecf47f13bf710f`, and exact `+4/−207` numstat;
- base three-dot file list/stat against `9dfa1fb4317935573c0a2f7c9283d13a40f01104`;
- exact dirty-blob inventory of removed declarations and surviving continuation consumers, three `Task.yield` calls, request-order state, checkpoint decoding/ordering, prior-checkpoint carry-forward, and unconditional checkpoint acceptance;
- `HealthWorkoutCacheTests.swift` blob `9bdc7a5fd2b528b8f9273395480d9efa02625616`, identical at invalidated `d853728…` and `f5690f…`;
- repeated five-P1 verdict comments `00966211-f963-48f7-ac63-8623621e0298` and `9d352f6d-5742-40a7-a047-365e1aae2cea`.

If 0A diverges, Team Lead does not dispatch and reports the exact mismatch without changing the workspace.

**Phase 0B — dispatched Fullstack before its first edit** records a separate timestamped packet attributable to its current run/task identity, excludes only that expected run from the check, confirms no competing active/orphan owner, and independently rechecks every 0A value. Audit immutable committed `f5690f…` for the historical unsafe/Mutex structural RED, then audit dirty blob `7f1f162…` separately to prove partial removals remain and surviving rejected consumers match 0A. If 0B diverges, Fullstack stops before editing and reports the mismatch; it does not normalize the worktree, restore `be096365…`, or terminate an unverified process. Source work begins only after 0A and 0B agree.

The dirty blob is a preservation baseline, not an executable-result claim. All executable evidence runs in the metadata-pinned workspace. First run `swift build` and record the actual outcome. Compiler RED proves only incompleteness and cannot replace a behavior RED; compile GREEN proves only buildability. If RED, complete the minimum actor-owned compile bridge without restoring deleted helpers or implementing B settlement, C reset-drain, or D checkpoint outcomes; make `swift build` green, then run every behavior tracer in place.

## Execution Order

1. Complete T023-001 and keep the package gate green.
2. Complete T023-002 after T023-001.
3. **Stage A — result semantics and reconciliation**: run a strengthened public-cache case for A→empty and anchored-intent→baseline fallback, then continue test-first through UUID add/update/delete, unknown deletion, duplicate provider UUIDs, repeated-delta idempotency, deletion-wins, empty authoritative snapshot, and equal-time ordering. Use RED→GREEN for missing/incorrect behavior or a changing production path; record characterization-GREEN when the behavior is already correct and its path remains unchanged.
4. **Stage B — exactly-once caller settlement**: first require an explicit-gate RED that exposes multiple/independent completion; then replace independently synchronized waiter helpers with actor-owned registration/settlement state and cover same-key coalescing, non-owner cancellation, owner cancellation, and shared provider failure. Every case must finish without a hang, direct second resume, sleeps, or yield polling.
5. **Stage C — provider-lane cancellation and reset**: gate one active provider request and one queued successor; require RED for the continuation-holder lane stranding a caller or blocking a successor under cancellation/invalidation, then implement actor-owned request-ID lanes and cover refresh supersession, `invalidateWorkouts()`, `invalidateAll()`, and authorization revocation through full-reset draining while a stale non-cooperative provider remains held.
6. **Stage D — checkpoint publication/invocation and anchored replay**: require separate RED evidence for previous/candidate mismatch, checkpoint decoding/comparison defeating request-identity currentness, and anchored B/c2 rejection/replay. Then implement opaque currentness plus same-turn A+B/c2 publication and synchronous acceptance invocation before success settlement; make the provider silently leave durable state on c1 and prove the following query replays B from c1 and resubmits c2 safely.
7. **Stage E — remaining deterministic matrix**: one test-first case at a time for explicit-range→default rebuild, concrete coverage versus wider range, different semantic/range requests not coalescing, persisted-anchor restart baseline rebuild, provider failure preserving cache-accepted state, stale late completion, legacy snapshot-only fallback with checkpoint absent/no acceptance call, and prepared baseline/change with nil checkpoint. Use RED→GREEN only when missing/incorrect or changing; otherwise record strengthened characterization-GREEN.
8. Run focused workout tests after every tracer bullet, then the full repository-declared package gate.

For every stage, entry evidence is the prior stage's exit plus a named next tracer. Before production change, classify and record exactly one mode: (a) mandatory RED→GREEN with test name, command, nonzero exit, and observable defect when behavior is missing/incorrect or its path will change; or (b) characterization-GREEN with test name, command, zero exit, strengthened observable assertions, and proof that the path remains unchanged. Never introduce a regression or mix in another defect to manufacture RED. Exit evidence records the focused GREEN command/exit, replacement or unchanged-path proof, prior-stage regression set, and current allowlisted diff. Accumulate this ledger for the final Fullstack handoff; do not post a progress-only comment.

### Stage-specific entry and exit evidence

- **A entry**: both Stage 0 phases match the authorized dirty packet; compiler preflight is recorded; if RED, the minimal in-place actor-owned bridge makes `swift build` green without implementing B–D outcomes. **A exit**: every semantic/UUID/empty/order tracer has RED→GREEN or eligible characterization-GREEN evidence, B–D mandatory defect paths remain RED until their stages, and Stage A is green.
- **B entry**: A green plus failing owner/non-owner/failure cases. **B exit**: one terminal outcome per caller; old waiter/in-flight lock state, direct second resume, and production yield polling absent; A+B green.
- **C entry**: B green plus failing active/queued reset case. **C exit**: no provider-turn continuation holder; cancellation, invalidation, and authorization reset settle all affected callers once; successor starts before stale release; A–C green.
- **D entry**: C green plus scripted A/c1 and completed B/c2. **D exit**: no checkpoint decoding/order, request order, or prior-checkpoint carry-forward; rejection/replay/invocation/silent-lag transcript; A–D green.
- **E entry**: D green plus enumerated remaining cases. **E exit**: every remaining tracer has RED→GREEN or eligible characterization-GREEN evidence, the full matrix is green, no sleep/yield timing evidence remains, and the test blob differs from `9bdc7a…`.
- **F entry**: complete A–E ledger; final source blob differs from `be096365…` and dirty `7f1f162…`; final test blob differs from `9bdc7a5…`; both mandatory files differ from `f5690f…`. **F exit**: full package/diff/pattern gates, genuinely new pushed SHA/tree distinct from both preserved baselines, four-way equality, and Fullstack-authored exact-SHA review request.

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

Before commit, the production/test audit must show no rejected transaction pattern: no `Synchronization`/Mutex-owned waiter state, continuation-holder provider turn, production or test timing-yield coordination, request-order currentness, checkpoint decoding/ordering, previous-checkpoint carry-forward, or unconditional acceptance for nil candidates.

The authorized dirty snapshot is the measurable composite `{base HEAD f5690f…, sole HealthDataCache.swift dirty path, +4/−207, source blob 7f1f162…, test blob 9bdc7a5…}`; it has no synthetic tree OID.

After commit/push:

- HEAD differs from both invalidated `f5690f1461a6cb07504d7f6e945220cb5213b2fb` and `d85372895fd4561aba3185e31605076d9429d517`;
- both mandatory file blobs differ from `f5690f…`;
- final source blob differs from committed `be0963652c349210fa39a898cfecf47f13bf710f` and authorized dirty `7f1f162ef166aa6f841e3746fff3fa3ea40ba069`; final test blob differs from `9bdc7a5fd2b528b8f9273395480d9efa02625616`;
- local HEAD, tracking OID, pushed remote OID, and PR #423 head are identical;
- PR remains Draft with auto-merge disabled until exact-SHA content PASS;
- Fullstack—not PR Manager—authors the review request with planning authority, package gate, and scope/pattern evidence.

Same-SHA requests, trees equal to committed `f5690f…` or the authorized dirty snapshot, unchanged dirty-source/test blobs, empty commits, focused-only test evidence, or claims without recorded byte deltas fail the gate.

## Diff Audit

Before handoff, confirm:

- only the HealthKitService source/tests named in `tasks.md` changed;
- `workoutData(in:)`, `refreshWorkouts(in:)`, and direct `fetchWorkouts(dateRange:)` call shapes remain source-compatible;
- direct service fetches are anchor-free snapshots and do not independently read/advance the default workout anchor;
- the precise prepared-fetch capability/conformance is package-internal in `HealthDataCache.swift`, and `HealthKitService.swift` has no T023-002 public-witness access change;
- existing public provider adapters remain snapshot-only, and prepared acceptance uses the result's declared semantic when preparation falls back to a baseline;
- prepared cache-facing fetches do not persist checkpoints before acceptance;
- only the current request instance publishes cache state and then synchronously invokes provider acceptance for its checkpoint;
- the accepted immutable entry records the same opaque candidate checkpoint submitted to provider acceptance before success settlement; this is not treated as a persistence receipt;
- a provider adapter that records the acceptance call but deliberately leaves durable state unchanged causes a later query from the prior checkpoint and safe UUID-idempotent replay;
- legacy fallback and nil-checkpoint prepared results publish checkpoint-absent entries and do not invoke checkpoint acceptance;
- all request, waiter, and provider-lane mutable state is actor-owned and every continuation completion uses one remove-before-resume authority;
- cancellation/invalidation drains active and queued callers and a late non-cooperative result is rejected without blocking a successor;
- production `HealthDataCache.swift` does not decode/order checkpoints or use `Synchronization`, locks, unsafe Sendable annotations, or yield polling for transaction state;
- changed test support uses compiler-checked Sendable state and explicit gates; the final production and test files contain no `@unchecked Sendable`, `@preconcurrency`, or `nonisolated(unsafe)` bypass;
- no health values/details were added to logs;
- no unsafe concurrency annotation was introduced;
- no AppUI, schema, WatchConnectivity, generated Xcode project, or project configuration file changed.
