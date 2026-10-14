# Data Model: HealthKit workout incremental sync successor

This feature changes in-memory synchronization contracts only. It adds no SwiftData model, migration, CloudKit field, workout L2 persistence, or public interface.

## Workout Fetch Intent

| Semantic | Anchor behavior | Coverage/provenance |
|---|---|---|
| Baseline snapshot | Ignore stored anchor; may return an unpersisted candidate | Concrete default first-sync coverage; default provenance |
| Anchored changes | Use provider-owned durable anchor; may return an unpersisted candidate | Requires and preserves compatible default coverage/provenance |
| Explicit-range snapshot | Ignore stored anchor; never accepts a default candidate | Exact scoped request coverage; scoped provenance |
| Legacy fallback snapshot | Public compatibility call, no candidate | Default/scoped provenance derived from request; provider coverage preserved, otherwise exact explicit range or captured-start 30-day default |

The semantic/range fetch key identifies coalescible work. It is not the lane-domain identity.

## Workout Request Instance

| Field | Meaning |
|---|---|
| Request identity | Unique identity for one owning transaction |
| Fetch key | Requested semantic plus optional exact range |
| Lane identity | Default anchor domain or one exact explicit range |
| Reset generation | Invalidation/reset epoch captured before provider work |
| Request-start instant | Captured once at transaction registration; ends the fallback 30-day default coverage when a legacy default result omits coverage |
| Owner waiter | Caller whose cancellation retires the request |
| Coalesced waiters | Other identical-read callers attached to the owner |
| Provider task | Cancellable handle; cancellation does not define logical retirement |
| Prepared outcome | Result held until actor currentness/cache acceptance |

### Invariants

- All mutable request fields are isolated to `HealthDataCache`.
- Starting unrelated range work does not advance the reset generation.
- Only the current generation/key/request identity may publish or accept.
- Terminal removal makes later provider/cancellation events no-ops except prepared-result rejection.

## Caller Waiter

| Field | Meaning |
|---|---|
| Waiter identity | Unique identity for cancellation/settlement races |
| Request identity | Transaction awaited by this caller |
| Role | Owner or coalesced non-owner |
| Continuation | Pending terminal result while registered |

### Invariants

- One actor settlement authority removes before resuming.
- A waiter transitions exactly once to success, failure, or cancellation.
- Non-owner cancellation affects only that waiter.
- Owner cancellation retires the request and settles all attached waiters once.
- Supersession drains the retired request's waiters before pumping an eligible same-generation successor.
- Reset drains every old-generation active/queued waiter before discarding request/lane indexes; no old queued request becomes the reset successor.

## Provider Lane

| Field | Meaning |
|---|---|
| Lane identity | Default incremental anchor domain or one exact anchor-free explicit range |
| Active request identity | Logical provider owner currently running for the lane |
| Queued request identities | FIFO successors; no continuation-holder object |

### Invariants

- Baseline and anchored changes serialize through the default lane.
- Different explicit ranges use independent lanes and may progress independently.
- Logical revocation does not wait for a non-cooperative provider.
- Same-generation owner retirement or supersession pumps the next eligible queued request.
- Reset advances generation, removes every old active/queued identity, and settles callers immediately; only a newly registered post-reset request may start in the new generation.

## Workout Cache Entry

| Field | Meaning |
|---|---|
| Records | One record per UUID (final provider-result occurrence wins), sorted start date descending then UUID |
| Coverage | Concrete range actually represented: provider coverage when present; otherwise exact explicit range or the 30-day default ending at captured request start |
| Provenance | Default baseline or one explicit scoped range |
| Accepted candidate | Optional opaque checkpoint supplied by the accepted prepared baseline/change |

### Invariants

- Publication replaces the whole entry; no externally visible in-place mutation.
- Anchored changes apply only to default provenance and preserve its coverage/provenance.
- Scoped provenance cannot satisfy a default read.
- Missing explicit-range coverage falls back only to the exact requested range.
- Missing legacy default coverage falls back to the existing 30-day window ending at that transaction's captured request-start instant.
- Legacy, nil-candidate, and explicit-range snapshots record no candidate and invoke no acceptance.
- Candidate contents are never decoded, compared, timestamp-ordered, or carried forward.

## Cache Acceptance State

This is the transaction state around the one cache entry, not a second cache shape.

| Field/event | Meaning |
|---|---|
| Cache-acceptance point | Currentness passed and immutable next entry is ready to publish |
| Acceptance invocation | Synchronous provider call for the exact published candidate |
| Durable anchor | Provider-owned state that may remain behind because acceptance returns no outcome |

### Invariants

- Entry publication and matching acceptance invocation occur in one actor turn before success settlement.
- Candidate absence skips acceptance without invalidating the snapshot/change transition.
- Acceptance invocation does not prove durable advancement.
- Durable lag causes replay from the older checkpoint and idempotent resubmission; it does not roll back the cache or fail callers.

## Deterministic Test Gates

| Gate/event | Observable contract |
|---|---|
| Provider started | Lane pump launched the request |
| Query complete | Provider produced a result but cache has not yet accepted it |
| Cache acceptance | Actor reached the current-result publication point |
| Acceptance invocation | Exact candidate was submitted after publication and before success settlement |
| Durable anchor | Test provider controls whether invocation advances durable state |
| Reset successor | Newly registered post-reset request started in the new generation after every old active/queued identity is drained |
| Stale release | Non-cooperative stale provider is finally allowed to return |

Each gate is independently controlled and uses actor-owned or equivalent compiler-checked Sendable state. No lock, unsafe Sendable annotation, sleep, or yield loop is part of the model.

## State Transitions

| Current state | Event/result | Next state |
|---|---|---|
| No compatible entry | Baseline snapshot | Publish normalized default entry; record/accept candidate only when supplied |
| Default baseline | Current anchored changes | Publish UUID-reconciled entry preserving coverage/provenance; optionally accept candidate |
| No entry or scoped entry | Anchored changes | Reject prepared result; schedule/retry default baseline |
| Any state | Explicit-range snapshot | Publish normalized scoped entry with no candidate acceptance |
| Any compatible state | Legacy fallback snapshot | Publish normalized request-derived default/scoped entry with no candidate |
| Active request | Non-owner waiter cancellation | Settle only that waiter; preserve request and peers |
| Active/queued request | Owner cancellation or supersession | Retire request, settle attached waiters, release lane, pump eligible same-generation successor |
| Any state | Invalidate/reset | Advance reset generation, clear entry, drain all old active/queued work, permit a newly registered post-reset request |
| Published candidate, durable state unchanged | Later query | Replay from durable prior checkpoint and resubmit candidate safely |
| Any state | Failure, stale completion, duplicate terminal event | Preserve accepted cache/durable state; settle once or no-op if already terminal |
