# Contract: Workout snapshot and anchored changes

## Purpose

Remove ambiguity between authoritative workout snapshots and HealthKit anchored changes while preserving existing public call sites.

## Request Semantics

### Baseline snapshot

- Used whenever the cache has no compatible default baseline, including after process restart or invalidation.
- Executes an anchor-free query for the existing default first-sync window.
- Returns concrete coverage and an authoritative record set.
- Returns an opaque pending anchor checkpoint; the provider does not persist it during the prepared fetch.

### Anchored changes

- Used only when a compatible default baseline exists.
- Executes with the persisted workout anchor.
- Returns UUID upserts and deleted UUIDs.
- Returns an opaque pending anchor checkpoint without persisting it.
- An empty response means no change, not an empty snapshot.

### Explicit-range snapshot

- Used for a caller-supplied date range when the cache cannot truthfully cover it, and for explicit range refresh.
- Executes with no anchor.
- Returns an authoritative record set for exactly that range.
- Does not read or advance the default incremental anchor.

## Cache Application

### Snapshot

- Replace the single workout cache entry with the authoritative records, concrete coverage, and matching provenance.
- Deduplicate and deterministically sort before publication.
- An empty snapshot is a valid empty cache entry.

### Changes

- Reject changes as a cache base when no compatible default baseline exists; request a baseline instead.
- Upsert records by UUID.
- Apply deleted UUIDs after upserts; deletion wins on conflict.
- Unknown deletions are no-ops.
- Preserve the baseline coverage/provenance.
- Publish one newly constructed whole entry.

## Coalescing and Commit Rules

- Only identical semantic-plus-range requests may share an in-flight task.
- Every newly started fetch owns a unique request instance in addition to its semantic-plus-range key and captured workout generation.
- Ordinary duplicate reads may coalesce onto the owning request instance; an explicit refresh supersedes prior work even when semantic and range are identical.
- Invalidation and incompatible snapshot transitions advance the workout generation.
- A result is current only when generation, fetch key, and request instance all still match; a stale request cannot clear a newer in-flight owner.
- Failure, cancellation, or a stale completion preserves the last accepted cache/anchor pair.
- All mutable request, waiter, and provider-lane state is owned by the cache actor as compiler-checked value/task state. No lock-owned mutable helper, unsafe Sendable annotation, or yield-polling handshake is part of the contract.

## Caller Waiter Lifecycle

- Every caller registers one actor-owned waiter identity before suspension.
- One actor settlement authority handles success, failure, cancellation, supersession, and invalidation. It removes each waiter before resuming it; no other path resumes a caller continuation directly.
- A non-owner cancellation settles only that waiter and does not cancel the request owner or remaining coalesced callers.
- An owner cancellation retires the request, cancels its provider task, releases its logical provider turn, and settles every attached waiter exactly once.
- Registration/cancellation/provider-result races are serialized by the actor. Once removed, late or duplicate terminal events are no-ops.

## Provider Lane Lifecycle

- The default baseline/anchored domain has one logical provider lane; anchor-free explicit ranges may use independent range lanes.
- A lane stores an active request identity plus queued request identities, never a separately synchronized provider-turn continuation holder.
- Cancellation, supersession, `invalidateWorkouts()`, and `invalidateAll()` remove affected queued identities, revoke affected active identities, cancel task handles, settle callers, and pump eligible current-generation successors.
- Logical revocation does not wait for a non-cooperative provider. A late result is rejected by generation/key/request identity and cannot publish, persist, or clear newer state.

## Anchor/Cache Transaction Authority

The cache actor is the sole acceptance authority for provider results used by `HealthDataCache`.

The precise prepared-fetch capability and its HealthKitService conformance are package-internal to the HealthKitService module and owned by the cache-facing T023-002 file. The package-internal preparation/acceptance methods delivered by T023-001 remain in `HealthKitService.swift` without public access changes. Existing public provider conformers are not required to adopt this capability and retain anchor-free snapshot-only compatibility behavior.

For an anchor-advancing baseline or changes result, acceptance order is:

1. The provider completes the query and returns records/deletions plus an opaque pending checkpoint without persisting it.
2. The cache actor validates generation, fetch key, and request instance after the provider await.
3. The cache actor constructs the new immutable cache entry containing the candidate checkpoint.
4. The cache publishes that entry and, without suspension, synchronously invokes provider acceptance with the same checkpoint.
5. Only after the matching invocation returns does actor settlement release the lane, remove the owning request, and complete registered success waiters.

Acceptance uses the prepared result's declared semantic, coverage, and provenance. The requested semantic identifies intent and coalescing, but it does not override the result: when anchored preparation has no persisted anchor and returns a baseline snapshot, the cache publishes that result as a baseline before accepting its matching checkpoint.

A rejected result performs neither step 3 nor step 4. The checkpoint is opaque: cache currentness uses only generation, semantic/range key, and request identity, never checkpoint timestamps, decoded anchor contents, or inferred ordering. Provider acceptance returns no outcome and may silently leave durable state unchanged; the cache therefore treats step 4 as an invocation guarantee, not a persistence receipt. The prior durable anchor then drives replay, which UUID reconciliation handles idempotently, and the same candidate may be submitted again. The unsafe inverse—advancing an anchor before accepting its cache transition—or publishing a new projection while retaining the old checkpoint in that entry is forbidden.

The source-compatible direct `HealthKitService.fetchWorkouts(dateRange:)` path is an anchor-free authoritative snapshot. It neither reads nor advances the default workout anchor. Only the deferred provider seam used by the app-owned `HealthDataCache` may prepare a default checkpoint and receive a cache-authorized synchronous acceptance invocation; there is no independent direct-call anchor writer.

### Required adversarial sequence

1. Accept baseline A and its checkpoint.
2. Complete a provider query for anchored delta B but hold it before cache acceptance.
3. Cancel or supersede it with a same-semantic refresh.
4. Verify the rejected request did not persist its checkpoint or clear the newer in-flight owner.
5. Run the next accepted request from the prior durable checkpoint, verify the cache publishes A and B with candidate c2, then verify provider acceptance receives c2 before caller success.
6. Configure that acceptance call to leave durable state on c1, run another request from c1, and verify replay is UUID-idempotent and c2 is submitted again without treating the first call as confirmed persistence.

The provider adapter must expose distinct deterministic gates for provider start, query completion, cache acceptance release, acceptance invocation, and optional durable-anchor advancement. A gate inside the provider before its method returns is not proof of the provider-complete/cache-not-yet-accepted interval. Snapshot-only requests and cache hits are not substitutes for anchored rejection/replay, and an acceptance invocation is not treated as confirmed durability.

## Compatibility

- Existing callers of `HealthDataCache.workoutData(in:)` require no source changes.
- Existing callers of `HealthDataCache.refreshWorkouts(in:)` require no source changes.
- Existing callers of `HealthKitService.fetchWorkouts(dateRange:)` require no source changes.
- Existing direct service callers receive an authoritative snapshot and no default-anchor side effect.
- Existing public provider conformers add no new witness and receive anchor-free snapshot-only compatibility behavior.
- The prepared-fetch capability adds no AppUI-facing or other public interface; HealthKitService and deterministic cache tests adopt it inside the package.
- Tests must cover both old call shapes and new precise behavior.

## Privacy

Allowed operational logging:

- request semantic;
- aggregate result count;
- elapsed duration;
- cache hit/miss/refresh category.

Forbidden logging:

- heart rate, energy, distance, duration, or other workout health values;
- record identifiers;
- record-specific timestamps or source details.
