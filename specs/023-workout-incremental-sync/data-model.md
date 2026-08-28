# Data Model: HealthKit workout incremental sync

This feature changes in-memory synchronization contracts only. It adds no SwiftData model, migration, CloudKit field, or workout L2 persistence.

## Workout Fetch Request

Represents one of three semantic requests:

| Semantic | Anchor behavior | Coverage |
|---|---|---|
| Baseline snapshot | Ignore any stored anchor; return an unpersisted checkpoint for cache acceptance | Concrete default first-sync window |
| Anchored changes | Use the stored workout anchor; return an unpersisted checkpoint for cache acceptance | Relative to the compatible baseline coverage |
| Explicit-range snapshot | Ignore the stored anchor; do not advance the default incremental anchor | Exact requested date range |

The request semantic and range together form the in-flight coalescing identity.

## Workout Fetch Result

| Field | Meaning |
|---|---|
| Records | Authoritative snapshot records or UUID-keyed upserts |
| Deleted UUIDs | Deletions for anchored changes; empty for a normal snapshot |
| Result semantic | Snapshot or changes |
| Coverage | Concrete authoritative range for a snapshot; inherited from the base for changes |
| Pending checkpoint | Opaque anchor state tied to this query; absent for explicit-range snapshots and unpersisted until acceptance |

### Invariants

- A snapshot is independently usable and may be empty.
- Changes require a compatible baseline.
- Changes never widen or shrink coverage.
- Explicit-range snapshots never advance the default workout anchor.
- Prepared baseline/change results do not persist their pending checkpoint.
- The direct public service fetch is snapshot-only and has no default-anchor side effect.
- The precise prepared-fetch capability is package-internal and adds no public witness requirement.
- Existing public provider conformers remain source-compatible through anchor-free snapshot-only fallback behavior.
- Cache application follows the prepared result's semantic; an anchored request that prepares a baseline because no persisted anchor exists establishes baseline coverage/provenance.

## Workout Request Instance

| Field | Meaning |
|---|---|
| Fetch key | Request semantic plus optional range |
| Instance identity | Unique identity for the specific owner of in-flight work |
| Workout generation | State version captured before awaiting the provider |

### Invariants

- Duplicate ordinary reads may share one owning instance.
- An explicit refresh creates a new instance even when its fetch key matches the prior refresh.
- Only the instance still registered for its key may publish, persist a checkpoint, or clear the in-flight slot.

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
- The cache may be ahead of the persisted anchor (safe replay), but the persisted anchor must never be ahead of the accepted cache transition.

## State Transitions

| Current state | Request/result | Next state |
|---|---|---|
| No compatible entry | Baseline snapshot | Replace with default baseline entry |
| Default baseline | Current anchored changes | Publish reconciled UUIDs, then persist pending checkpoint; retain coverage/provenance |
| Any state | Explicit-range snapshot | Replace with scoped entry for that exact coverage |
| Scoped entry | Default request | Rebuild default baseline |
| Any state | Invalidate | Clear entry/tasks and advance workout generation |
| Any state | Failure, cancellation, stale generation/instance | Preserve last accepted cache/anchor pair; persist no checkpoint |
