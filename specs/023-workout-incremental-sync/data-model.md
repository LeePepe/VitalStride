# Data Model: HealthKit workout incremental sync

This feature changes in-memory synchronization contracts only. It adds no SwiftData model, migration, CloudKit field, or workout L2 persistence.

## Workout Fetch Request

Represents one of three semantic requests:

| Semantic | Anchor behavior | Coverage |
|---|---|---|
| Baseline snapshot | Ignore any stored anchor; save the returned anchor for later changes | Concrete default first-sync window |
| Anchored changes | Use the stored workout anchor; save the returned anchor | Relative to the compatible baseline coverage |
| Explicit-range snapshot | Ignore the stored anchor; do not advance the default incremental anchor | Exact requested date range |

The request semantic and range together form the in-flight coalescing identity.

## Workout Fetch Result

| Field | Meaning |
|---|---|
| Records | Authoritative snapshot records or UUID-keyed upserts |
| Deleted UUIDs | Deletions for anchored changes; empty for a normal snapshot |
| Result semantic | Snapshot or changes |
| Coverage | Concrete authoritative range for a snapshot; inherited from the base for changes |

### Invariants

- A snapshot is independently usable and may be empty.
- Changes require a compatible baseline.
- Changes never widen or shrink coverage.
- Explicit-range snapshots never advance the default workout anchor.
- Existing result construction remains source-compatible through defaults.

## Workout Cache Entry

| Field | Meaning |
|---|---|
| Records | Deduplicated, deterministic `[HealthWorkoutRecord]` projection |
| Coverage | The concrete range actually fetched |
| Provenance | Whether the entry is a default anchored baseline or an explicit range snapshot |
| Generation | Actor-owned workout state version captured by in-flight work |

### Invariants

- Records contain at most one item per UUID.
- Records are sorted by start date descending, then UUID.
- Publication replaces the whole entry; no in-place externally visible mutation.
- A stale generation cannot commit.
- A default-window entry cannot claim to cover an older/wider range.
- A range snapshot cannot be used as the base for default anchored changes.

## State Transitions

| Current state | Request/result | Next state |
|---|---|---|
| No compatible entry | Baseline snapshot | Replace with default baseline entry |
| Default baseline | Anchored changes | Reconcile UUIDs; retain coverage/provenance |
| Any state | Explicit-range snapshot | Replace with scoped entry for that exact coverage |
| Scoped entry | Default request | Rebuild default baseline |
| Any state | Invalidate | Clear entry/tasks and advance workout generation |
| Any state | Failure, cancellation, stale generation | Preserve last valid entry |
