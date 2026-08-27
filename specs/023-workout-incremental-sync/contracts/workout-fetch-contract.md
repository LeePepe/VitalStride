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

## Anchor/Cache Transaction Authority

The cache actor is the sole acceptance authority for provider results used by `HealthDataCache`.

For an anchor-advancing baseline or changes result, acceptance order is:

1. The provider completes the query and returns records/deletions plus an opaque pending checkpoint without persisting it.
2. The cache actor validates generation, fetch key, and request instance after the provider await.
3. The cache actor constructs and publishes the new immutable cache entry.
4. Without another suspension point, the accepted checkpoint is synchronously persisted.
5. Only the owning request instance clears its in-flight slot and returns the accepted projection.

A rejected result performs neither step 3 nor step 4. This gives at-least-once change delivery: if checkpoint persistence cannot complete after cache publication, the previous anchor remains and the next fetch may replay changes, which UUID reconciliation handles idempotently. The unsafe inverse—persisting an anchor before accepting its cache transition—is forbidden.

The source-compatible direct `HealthKitService.fetchWorkouts(dateRange:)` path is an anchor-free authoritative snapshot. It neither reads nor advances the default workout anchor. Only the deferred provider seam used by the app-owned `HealthDataCache` may prepare and persist a default anchor checkpoint; there is no independent direct-call anchor writer.

### Required adversarial sequence

1. Accept baseline A and its checkpoint.
2. Complete a provider query for anchored delta B but hold it before cache acceptance.
3. Cancel or supersede it with a same-semantic refresh.
4. Verify the rejected request did not persist its checkpoint or clear the newer in-flight owner.
5. Run the next accepted request from the prior checkpoint, verify the cache publishes A and B first, then verify the matching new checkpoint is persisted.

## Compatibility

- Existing callers of `HealthDataCache.workoutData(in:)` require no source changes.
- Existing callers of `HealthDataCache.refreshWorkouts(in:)` require no source changes.
- Existing callers of `HealthKitService.fetchWorkouts(dateRange:)` require no source changes.
- Existing direct service callers receive an authoritative snapshot and no default-anchor side effect.
- Existing provider conformers receive compatibility behavior for any newly explicit request/acceptance semantic.
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
