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
- A prepared baseline/change may have no pending checkpoint. Nil does not invalidate its records, coverage, or semantic.
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
- Only the instance still registered for its key may publish, invoke checkpoint acceptance, or clear the in-flight slot.

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

## Cache Acceptance State

This is not a second cache-entry shape. It references the one canonical `Workout Cache Entry` defined below. Request generation, fetch key, request identity, and any scheduling order belong only to `Workout Transaction`; none is stored in the cache entry.

| Field | Meaning |
|---|---|
| Immutable cache entry | The canonical records, coverage, provenance, and optional accepted-checkpoint value defined below |
| Acceptance invocation | Synchronous submission before caller success only when that entry has a candidate checkpoint |
| Durable anchor | Provider-owned state that may remain on the prior checkpoint because the `Void` acceptance reports no outcome |

### Invariants

- Checkpoint contents are never decoded, compared, or ordered by the cache.
- A current prepared baseline/delta entry records its cache-accepted candidate only when supplied; nil-checkpoint prepared results record no checkpoint.
- Legacy snapshot fallback and explicit-range entries record no checkpoint and invoke no checkpoint acceptance.
- Entry publication and synchronous provider acceptance occur in one actor turn before success settlement.
- Acceptance invocation is observable to the deterministic provider adapter, but it is not proof of durable persistence.
- Process failure or silent no-advance may leave durable state behind the cache and replay safely; the cache does not roll back or fail waiters based on an outcome the seam cannot report.

## Workout Cache Entry

| Field | Meaning |
|---|---|
| Records | Deduplicated, deterministic `[HealthWorkoutRecord]` projection |
| Coverage | The concrete range actually fetched |
| Provenance | Whether the entry is a default anchored baseline or an explicit range snapshot |
| Accepted checkpoint | Optional opaque candidate submitted to provider acceptance for this entry; present only when an accepted prepared baseline/change supplied one, and absent for nil-checkpoint prepared results, legacy snapshot fallback, and anchor-free explicit-range snapshots |

### Invariants

- Records contain at most one item per UUID.
- Records are sorted by start date descending, then UUID.
- Publication replaces the whole entry; no in-place externally visible mutation.
- A stale generation cannot commit.
- Generation, fetch key, request identity, and scheduling order are transaction-only currentness state and are not cache-entry fields.
- A default-window entry cannot claim to cover an older/wider range.
- A range snapshot cannot be used as the base for default anchored changes.
- The accepted checkpoint denotes cache acceptance and matching invocation, not confirmed durable persistence.
- The cache may be ahead of the persisted anchor after interruption or silent no-advance, which is safe replay; the persisted anchor must never be advanced by a rejected cache transition.

## State Transitions

| Current state | Request/result | Next state |
|---|---|---|
| No compatible entry | Baseline snapshot | Replace with default baseline entry; record and submit a candidate only when supplied |
| Default baseline | Current anchored changes | Construct reconciled entry; if a candidate exists, record it and synchronously invoke matching provider acceptance; otherwise keep checkpoint absent; retain coverage/provenance |
| Any compatible state | Legacy snapshot fallback | Publish authoritative snapshot with checkpoint absent; invoke no checkpoint acceptance |
| Any state | Explicit-range snapshot | Replace with scoped entry for that exact coverage |
| Scoped entry | Default request | Rebuild default baseline |
| Active/queued transaction | Non-owner waiter cancellation | Remove and cancel only that waiter; preserve request and peers |
| Active/queued transaction | Owner cancellation or supersession | Retire request, release lane, cancel task, settle all attached waiters, start eligible successor |
| Any state | Invalidate | Advance generation, clear entry, retire/drain active and queued transactions/lanes, then permit fresh work |
| Published candidate, durable anchor unchanged | Silent acceptance no-advance | Keep cache-accepted candidate state; next query reads prior durable anchor, replays idempotently, and resubmits acceptance |
| Any state | Failure, cancellation, stale generation/instance | Preserve last cache-accepted state and durable anchor; reject prepared state and invoke no acceptance |
| Terminal transaction | Late or duplicate event | No-op except rejecting a late prepared result |
