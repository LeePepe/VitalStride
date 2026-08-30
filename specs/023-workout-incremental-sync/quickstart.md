# Quickstart: MY-1477 implementation and verification

## Preconditions

- Work only in the daemon-provided worktree.
- Read `.specify/memory/constitution.md`, `AGENTS.md`, and `Packages/HealthKitService/CONTEXT.md`.
- Keep the diff within the files declared by `tasks.md`.
- Do not run `xcodebuild`; this is a package-only change.
- Preserve Draft PR #423, auto-merge disabled, and invalidated SHA `d85372895fd4561aba3185e31605076d9429d517` as evidence. Reuse the metadata-pinned delivery workspace without resetting its current dirty repair.
- Planner changes no source file. Fullstack replaces the invalidated transaction/waiter design through the staged public-cache behavior below rather than patching isolated review lines.

## Execution Order

1. Complete T023-001 and keep the package gate green.
2. Complete T023-002 after T023-001.
3. **Stage A — result semantics and reconciliation**: add one failing public-cache case for A→empty and anchored-intent→baseline fallback, then implement the minimal whole-entry semantic transition; continue one RED→GREEN case at a time through UUID add/update/delete, unknown deletion, duplicate provider UUIDs, repeated-delta idempotency, deletion-wins, empty authoritative snapshot, and equal-time ordering.
4. **Stage B — exactly-once caller settlement**: add deterministic failing cases for same-key coalescing, non-owner cancellation, owner cancellation, and shared provider failure; then replace independently synchronized waiter helpers with actor-owned registration/settlement state. Every case must finish without a hang, direct second resume, sleeps, or yield polling.
5. **Stage C — provider-lane cancellation and reset**: gate one active provider request and one queued successor; observe RED for cancellation, refresh supersession, `invalidateWorkouts()`, and `invalidateAll()`, then implement actor-owned request-ID lanes and reset draining so a fresh successor starts while a stale non-cooperative provider remains held.
6. **Stage D — atomic checkpoint pair and anchored replay**: accept A/c1; hold completed anchored B/c2 before cache acceptance; cancel/supersede it; prove c2 rejection and replay from c1; then implement opaque currentness plus same-turn A+B/c2 publication/persistence before success settlement. Add the interrupted-persistence replay case as its next tracer bullet.
7. **Stage E — remaining deterministic matrix**: one RED→GREEN case at a time for explicit-range→default rebuild, concrete coverage versus wider range, different semantic/range requests not coalescing, persisted-anchor restart baseline rebuild, provider failure preserving the accepted pair, stale late completion, and legacy snapshot-only fallback.
8. Run focused workout tests after every tracer bullet, then the full repository-declared package gate.

## Required Regression Matrix

- Baseline A → empty changes → A remains.
- Baseline A → add B + delete A → only B.
- Existing UUID → changed record → one updated record.
- Unknown deletion → accepted pair unchanged; duplicate UUIDs in one provider response → one deterministic record.
- Repeat the same changes → identical result.
- Empty authoritative snapshot → accepted empty entry; empty anchored changes → prior records retained.
- Same timestamps → UUID tie-breaker is stable.
- Empty process cache with persisted-anchor behavior → baseline requested.
- Default 30-day coverage → wider range fetches a snapshot.
- Explicit range → later default request rebuilds a compatible baseline.
- Different ranges/semantics → no incorrect task coalescing.
- Provider-complete delta held before acceptance → same-semantic supersession → rejected checkpoint is not persisted and the next read still obtains the delta.
- Replacement provider read observes c1 → replay B → cache publishes A+B with c2 → provider persists c2 → success waiters complete.
- Forward opaque checkpoint c1→c2 is accepted solely by current request identity; no cache-side anchor/timestamp ordering.
- Non-owner coalesced cancellation completes once and leaves owner/peers running; owner cancellation retires the request and completes every attached waiter once.
- Active/queued provider-lane cancellation, refresh supersession, `invalidateWorkouts()`, and `invalidateAll()` release all affected callers and let current successor work start before stale provider return.
- Authorization revocation follows the same full-reset drain and cannot leave a provider lane or caller suspended.
- Late cancelled or invalidated work → reject only; no stale cache/checkpoint commit or newer ownership cleanup.
- Provider error → every attached waiter fails once and the prior accepted pair remains.
- Interrupted checkpoint persistence → prior checkpoint replay is UUID-idempotent and later acceptance advances the pair.

## Focused Verification

From the repository root, use Swift Testing filters appropriate to the final suite names, including the existing workout-cache suite and provider-contract suite. For every tracer bullet, record the named RED failure against the current design and its subsequent GREEN result before starting the next case. Explicit gates, not wall-clock sleeps or `Task.yield`, establish interleavings.

## Required Layer Gate

Working directory: `Packages/HealthKitService`

```bash
swift build && swift test
```

Acceptance requires exit code 0 for both commands. Do not substitute an AppUI build or simulator test.

## Diff Audit

Before handoff, confirm:

- only the HealthKitService source/tests named in `tasks.md` changed;
- `workoutData(in:)`, `refreshWorkouts(in:)`, and direct `fetchWorkouts(dateRange:)` call shapes remain source-compatible;
- direct service fetches are anchor-free snapshots and do not independently read/advance the default workout anchor;
- the precise prepared-fetch capability/conformance is package-internal in `HealthDataCache.swift`, and `HealthKitService.swift` has no T023-002 public-witness access change;
- existing public provider adapters remain snapshot-only, and prepared acceptance uses the result's declared semantic when preparation falls back to a baseline;
- prepared cache-facing fetches do not persist checkpoints before acceptance;
- only the current request instance publishes cache state and then synchronously persists its checkpoint;
- the accepted immutable entry records the same opaque candidate checkpoint that the provider synchronously persists before success settlement;
- all request, waiter, and provider-lane mutable state is actor-owned and every continuation completion uses one remove-before-resume authority;
- cancellation/invalidation drains active and queued callers and a late non-cooperative result is rejected without blocking a successor;
- production `HealthDataCache.swift` does not decode/order checkpoints or use `Synchronization`, locks, unsafe Sendable annotations, or yield polling for transaction state;
- changed test support uses compiler-checked Sendable state and explicit gates; the final production and test files contain no `@unchecked Sendable`, `@preconcurrency`, or `nonisolated(unsafe)` bypass;
- no health values/details were added to logs;
- no unsafe concurrency annotation was introduced;
- no AppUI, schema, WatchConnectivity, generated Xcode project, or project configuration file changed.
