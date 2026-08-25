# Contract: Workout snapshot and anchored changes

## Purpose

Remove ambiguity between authoritative workout snapshots and HealthKit anchored changes while preserving existing public call sites.

## Request Semantics

### Baseline snapshot

- Used whenever the cache has no compatible default baseline, including after process restart or invalidation.
- Executes an anchor-free query for the existing default first-sync window.
- Returns concrete coverage and an authoritative record set.
- Saves the returned anchor so later anchored changes begin from this snapshot.

### Anchored changes

- Used only when a compatible default baseline exists.
- Executes with the persisted workout anchor.
- Returns UUID upserts and deleted UUIDs.
- Advances the persisted anchor only after a successful provider result.
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
- A workout-specific generation is captured before awaiting the provider.
- Invalidation and a superseding incompatible snapshot advance the generation.
- A result commits only when its generation remains current.
- Failure, cancellation, or a stale completion preserves the last valid entry.

## Compatibility

- Existing callers of `HealthDataCache.workoutData(in:)` require no source changes.
- Existing callers of `HealthDataCache.refreshWorkouts(in:)` require no source changes.
- Existing callers of `HealthKitService.fetchWorkouts(dateRange:)` require no source changes.
- Existing provider conformers receive compatibility behavior for any newly explicit request semantic.
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
