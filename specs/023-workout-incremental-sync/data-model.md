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

## Workout Transaction

Actor-owned logical state for one request instance.

| Field | Meaning |
|---|---|
| Fetch key and generation | Semantic/range identity and invalidation version |
| Request identity | Unique currentness and late-event rejection token |
| Owner waiter | Caller whose cancellation retires the request |
| Coalesced waiter identities | Other callers sharing the observable result |
| Provider phase | Queued, preparing, prepared, settling, or terminal |
| Provider task handle | Cancellable work handle; not the source of mutable waiter state |

### Invariants

- All mutable fields are isolated to `HealthDataCache`; helper values do not own locks or use unchecked Sendable conformance.
- A transaction reaches one terminal outcome through the actor settlement authority.
- Removing the transaction/waiter precedes continuation completion.
- A late provider/cancellation event after terminal removal cannot mutate cache, checkpoint, lane, or waiter state.

## Caller Waiter

| Field | Meaning |
|---|---|
| Waiter identity | Unique identity used for cancellation/settlement races |
| Request identity | Transaction whose result it awaits |
| Role | Owner or coalesced non-owner |
| Continuation | Pending success/failure result, stored only while registered |

### Invariants

- Pending transitions exactly once to success, failure, or cancellation.
- Non-owner cancellation affects only that waiter.
- Owner cancellation retires the request and settles all attached waiters once.
- Invalidation and supersession drain affected waiters before indexes are discarded.

## Provider Lane

| Field | Meaning |
|---|---|
| Lane identity | Default incremental anchor domain or anchor-free explicit range |
| Active request identity | Logical owner allowed to prepare for the lane |
| Queued request identities | FIFO successors; no continuation-holder object |

### Invariants

- Baseline and anchored changes serialize through the default anchor lane.
- Revoking an active logical turn does not wait for a non-cooperative provider; current successor work may start.
- Queued cancellation/reset removes the request identity and settles callers immediately.
- Late results must pass generation/key/request currentness before acceptance.

## Accepted Workout Pair

| Field | Meaning |
|---|---|
| Immutable cache entry | Records, concrete coverage, provenance, request order, matching checkpoint |
| Persisted checkpoint | The same opaque checkpoint accepted for that entry |

### Invariants

- Checkpoint contents are never decoded, compared, or ordered by the cache.
- A current baseline/delta entry records the candidate checkpoint, not the previous checkpoint.
- Entry publication and synchronous provider acceptance occur in one actor turn before success settlement.
- A process failure may leave persistence behind the cache and replay safely; persisted state never leads an observably successful cache transition.

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
| Default baseline | Current anchored changes | Construct reconciled entry with candidate checkpoint; publish and synchronously persist the matching checkpoint; retain coverage/provenance |
| Any state | Explicit-range snapshot | Replace with scoped entry for that exact coverage |
| Scoped entry | Default request | Rebuild default baseline |
| Active/queued transaction | Non-owner waiter cancellation | Remove and cancel only that waiter; preserve request and peers |
| Active/queued transaction | Owner cancellation or supersession | Retire request, release lane, cancel task, settle all attached waiters, start eligible successor |
| Any state | Invalidate | Advance generation, clear entry, retire/drain active and queued transactions/lanes, then permit fresh work |
| Any state | Failure, cancellation, stale generation/instance | Preserve last accepted cache/checkpoint pair; reject prepared state and persist no checkpoint |
| Terminal transaction | Late or duplicate event | No-op except rejecting a late prepared result |
