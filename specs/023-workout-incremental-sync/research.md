# Research: HealthKit workout incremental sync successor

## Question

What is the smallest repository-owned module change, starting from exact current `main`, that satisfies deterministic workout reconciliation, caller settlement, provider-lane reset, and checkpoint replay without widening T023-001 or reusing the exhausted MY-1483 delivery?

## Baseline Evidence

| Observation at `e8cfc19…` | Repository evidence | Consequence |
|---|---|---|
| T023-001 precise provider operations are delivered and unchanged after `9dfa1fb…` | `HealthKitService.swift` prepared snapshot/changes and accept/reject methods; provider contract tests | The successor consumes the delivered contract and does not edit its files. |
| The public compatibility witness returns `WorkoutFetchResult` | `HealthDataCache.swift` `WorkoutDataProviding` | Legacy providers remain source-compatible but expose snapshot-only fallback. |
| One cache entry stores records plus optional coverage only | `HealthDataCache.swift` `WorkoutCacheEntry` | Provenance and optional accepted candidate must be added inside the cache-owned entry. |
| One global workout task coalesces all work | `workoutInFlightFetch`, `fetchWorkoutCoalesced`, `performWorkoutFetch` | Default and unrelated ranges cannot express real active/queued lane lifecycles. |
| Nil coverage is treated as covering every request | `coversRange` | A bounded default or scoped snapshot may incorrectly satisfy a wider/default request. |
| Provider results replace the whole cache and ignore deletions | `performWorkoutFetch` reads only `.workouts` | Empty anchored changes erase history; UUID reconciliation is absent. |
| Refresh/reset cancel the task and clear references directly | `refreshWorkouts`, `invalidateWorkouts`, `invalidateAll` | Callers and successors have no centralized exactly-once settlement lifecycle. |
| Tests use unchecked Sendable, NSLock, and sleeps | `HealthWorkoutCacheTests.swift` baseline mock and invalidation test | Timing green cannot prove query-complete/cache-acceptance/replay or reset-successor order. |

## Decision 1: Preserve T023-001 and use a cache-owned internal capability

**Chosen**: Keep `WorkoutDataProviding` public and unchanged for legacy fallback. In `HealthDataCache.swift`, define only the package-internal capability/conformance needed to call the already-delivered prepared operations. Production `HealthKitService` and deterministic test providers are the two adapters at this internal seam.

**Why**: It preserves compatibility, keeps the prepared interface out of AppUI/public witness requirements, and confines the successor to the HealthKitService Service role.

**Rejected**: Editing `HealthKitService.swift`, `HealthWorkoutRecord.swift`, or provider-contract tests; making new prepared witnesses public; copying the PR #423 candidate.

## Decision 2: Keep one deep `HealthDataCache` module

**Chosen**: Put request, owner/coalesced waiter, provider task, lane, prepared outcome, cache application, and terminal state behind the existing public cache interface as actor-owned plain values.

**Why**: Cache state and the synchronous acceptance linearization point already belong to this actor. A separate coordinator actor would create another reentrancy seam and expose more interface without increasing leverage.

## Decision 3: Centralize remove-before-resume settlement

**Chosen**: One actor operation removes a waiter before continuation resume and is the only completion route for success, failure, cancellation, supersession, and invalidation. Non-owner cancellation settles only that waiter; owner cancellation retires the request and settles every attached waiter.

**Why**: Actor serialization gives registration/cancellation/provider-result races one terminal winner. A late event finds no registered waiter/request and cannot double-resume.

**Rejected**: Caller-local direct cancellation resume, provider-task direct success/failure resume, and separate drain-specific resume loops.

## Decision 4: Separate lane domain from fetch key

**Chosen**: The default baseline/anchored domain has one lane. Each exact explicit range has its own independent lane. A lane stores an active request identity and FIFO queued identities; fetch semantic/range key still controls coalescing and currentness.

**Why**: Baseline and changes share one durable anchor and must serialize. Anchor-free ranges do not share that state and must not be invalidated or blocked by unrelated ranges. Separating lane identity from fetch key avoids the rejected candidate's empty queue and per-request global-generation staling.

**Rejected**: One global lane, one lane per full semantic key that lets baseline/changes race, or a continuation-holder provider turn.

## Decision 5: Distinguish same-generation retirement from reset

**Chosen**: Owner cancellation and refresh supersession retire affected same-generation requests, settle callers, release lane ownership, and pump the next eligible queued successor without waiting for stale provider return. Workout/global invalidation and authorization reset instead advance generation, settle and remove every old active/queued request, and carry no queue identity forward. A request newly registered after reset may start in the new generation before an old stale provider returns.

**Why**: HealthKit/provider cancellation is cooperative, so scheduling cannot depend on stale return. At the same time, reset is an authorization/cache-boundary event: pumping pre-reset queued intent would violate its generation. Late return is rejected by generation/key/request identity in both cases.

## Decision 6: Apply changes only to a compatible default baseline

**Chosen**: Prepared anchored changes require a cache entry with default provenance. They preserve that entry's concrete coverage/provenance. Missing or scoped state rejects the changes and rebuilds a default baseline. Cache application follows the prepared result's actual semantic, so an anchored intent that returns a baseline is published as a baseline.

**Why**: Deltas have meaning only relative to their anchor-compatible base. Requested intent cannot override a provider-reported baseline fallback.

## Decision 7: Normalize every snapshot, including legacy fallback

**Chosen**: Deduplicate by UUID with the final provider-result occurrence winning, then sort by start date descending and UUID before whole-entry publication. Legacy provenance comes from the request: nil is default; an explicit interval is scoped. Preserve provider-reported coverage. When coverage is absent, use the exact explicit request or, for a default request, the existing 30-day window ending at the transaction's captured request-start instant.

**Why**: Legacy public providers cannot report prepared semantics or checkpoints, but their snapshots still must obey cache invariants and cannot make scoped data default-compatible.

## Decision 8: Keep checkpoints opaque and optional

**Chosen**: A current prepared baseline/change may supply a candidate. Publish one immutable entry containing that exact candidate, synchronously invoke provider acceptance for it, then settle success. Nil candidates, legacy fallback, and explicit-range snapshots publish checkpoint-absent state and invoke no acceptance.

**Why**: Generation/key/request identity is the currentness authority. Checkpoint archive contents, timestamps, and prior values are provider concerns and cannot safely establish cache ordering.

## Decision 9: Treat acceptance as invocation, not durable receipt

**Chosen**: The delivered `Void` acceptance proves only ordered invocation. Deterministic tests model durable state separately: after A/c1 and B/c2 cache acceptance, durable state may silently remain c1; the next query replays B and safely resubmits c2.

**Why**: Claiming persistence success would exceed the interface. UUID reconciliation supplies at-least-once replay safety without reopening T023-001.

## Decision 10: Use distinct observable gates

**Chosen**: Deterministic test adapters expose provider-started, query-complete, cache-acceptance, acceptance-invocation, durable-anchor, reset-successor, and stale-release gates/events. State is actor-owned or equivalently compiler-checked Sendable.

**Why**: An in-provider release gate does not observe the post-query/pre-acceptance boundary. Sleep/yield timing cannot prove successor pumping or settlement completeness.

## Decision 11: One clean successor from current main

**Chosen**: T023-003 depends only on delivered T023-001 and starts from exact `main` SHA `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`. Cancelled T023-002, PR #423, and `a0d8…` remain cited evidence only.

**Why**: The Owner stopped the exhausted delivery and authorized a normal independent successor. Reusing its branch/workspace/content would turn the successor into another repair round and violate the stated base.

## Validation Decision

All implementation changes are package-only. Repository-declared verification is:

```bash
cd Packages/HealthKitService
swift build && swift test
```

`xcodebuild` is forbidden for this scope. A final source/diff audit is also required because full tests alone do not prove the unique-resume site, two-file allowlist, or absence of checkpoint/timing/concurrency anti-patterns.
