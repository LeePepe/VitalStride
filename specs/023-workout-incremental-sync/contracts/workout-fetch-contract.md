# Contract: Workout snapshot, changes, settlement, and lanes

## Purpose

Complete the cache-side transaction contract delivered by T023-001 while preserving existing public call sites and confining the successor to `HealthDataCache` plus its public-interface tests.

## Request and Result Semantics

### Baseline snapshot

- Used whenever the cache has no compatible default baseline, including after process restart, scoped-cache replacement, or invalidation.
- Executes anchor-free for the existing default first-sync window.
- Returns concrete coverage, authoritative records, and an optional opaque candidate.

### Anchored changes

- Used only when a compatible default baseline exists.
- Executes from provider-owned durable anchor state.
- Returns UUID upserts, deleted UUIDs, and an optional opaque candidate.
- Empty changes preserve records, coverage, and provenance.

### Explicit-range snapshot

- Used for an exact caller-supplied range that the current entry cannot truthfully cover and for explicit-range refresh.
- Executes anchor-free and never accepts a default candidate.
- Publishes scoped provenance for exactly the provider-reported or requested range.

### Legacy fallback snapshot

- Uses the unchanged public `WorkoutDataProviding` witness.
- Is always authoritative snapshot behavior with no candidate and no acceptance invocation.
- Derives default/scoped provenance from the request and preserves provider-reported coverage.
- When coverage is absent, an explicit request uses its exact range; a default request uses the existing 30-day default window ending at the transaction's captured request-start instant.

## Snapshot and Change Application

### Snapshot normalization

- Collapse repeated UUIDs before publication; the final occurrence in the provider result wins.
- Sort by start date descending, then UUID.
- Publish one newly constructed whole entry with matching default/scoped provenance.
- An empty snapshot is a valid empty entry.

### Anchored reconciliation

- Reject changes when no compatible default baseline exists; request a baseline instead.
- Copy prior records into a UUID map, apply upserts, then deletions; deletion wins.
- Unknown deletions are no-ops.
- Preserve baseline coverage and default provenance.
- Normalize/sort and publish one newly constructed whole entry.
- Follow the prepared result's actual semantic; a baseline returned for anchored intent is a baseline, not changes.

## Caller Waiter Lifecycle

- Every caller registers one actor-owned waiter identity before suspension.
- One actor settlement authority handles success, failure, cancellation, supersession, and invalidation. It removes each waiter before resuming it; no other path resumes a caller continuation directly.
- A non-owner cancellation settles only that waiter and preserves the owner and remaining coalesced callers.
- An owner cancellation retires the request, cancels its provider task, releases its logical lane turn, and settles every attached waiter exactly once.
- Registration/cancellation/provider-result races are actor-serialized. Once removed, late or duplicate terminal events are no-ops.

## Provider Lane Lifecycle

- The default baseline/anchored domain has one logical provider lane.
- Every exact anchor-free explicit range has an independent range lane; different ranges may progress concurrently.
- A lane stores an active request identity plus FIFO queued identities, never a separately synchronized continuation holder.
- Ordinary identical reads may coalesce on one request. An explicit refresh supersedes the prior same-key request and becomes an eligible queued/current successor in the same lane.
- Owner cancellation and refresh supersession remove affected same-generation identities, cancel task handles, settle callers, release logical ownership, and pump the next eligible queued successor.
- `invalidateWorkouts()`, `invalidateAll()`, and authorization reset advance generation, revoke and settle every old active/queued request, and carry none of that queued work forward. A fresh request registered after reset may start immediately in the new generation.
- Logical revocation does not await non-cooperative provider return. A late result fails generation/key/request currentness and cannot publish, invoke acceptance, or clear newer ownership.

## Cache/Checkpoint Acceptance

The cache actor is the sole acceptance authority for prepared results used by `HealthDataCache`.

For a current prepared baseline/change with a candidate:

1. Provider query completes without persisting the candidate.
2. The actor validates reset generation, semantic/range key, request identity, lane ownership, and baseline compatibility.
3. The actor constructs the normalized immutable entry containing that exact opaque candidate.
4. The actor publishes the entry and, without suspension, synchronously invokes provider acceptance for the matching candidate.
5. Only after invocation returns does the actor release/pump the lane, retire the request, and settle success waiters.

A rejected or stale result performs neither publication nor acceptance. A prepared baseline/change with no candidate, legacy fallback, and explicit-range snapshot publish checkpoint-absent state and invoke no acceptance.

Checkpoint contents are opaque. Cache currentness uses generation/key/request identity only; the cache never decodes, compares, timestamps, orders, or carries forward a prior checkpoint. The delivered `Void` acceptance guarantees invocation order, not durable persistence. Durable state may silently remain at c1, so a later query may replay B and resubmit c2; UUID reconciliation makes this safe.

The direct public `HealthKitService.fetchWorkouts(dateRange:)` path remains an anchor-free authoritative snapshot and never becomes a second default-anchor writer.

## Required Deterministic Sequences

### Settlement sequence — AC-S1

Exercise owner/coalesced waiters through success, provider error, non-owner cancellation, owner cancellation, supersession, workout invalidation, and global invalidation. Assert one terminal outcome per waiter and verify the production source has one continuation-resume site.

### Lane/reset sequence — AC-S2

1. Hold an active default request and queue a same-generation same-lane successor.
2. Start distinct explicit-range requests and observe independent lane progress.
3. Supersede or owner-retire the default request and observe the eligible queued successor start before stale release.
4. In a separate reset case, hold old-generation active and queued requests, invalidate/authorize-reset, and observe every old caller settle and every old queue identity disappear.
5. Register a new post-reset request and observe it start before the old stale provider is released.
6. Release each stale provider and verify it cannot publish, accept, or clear newer ownership.

### Compatible-baseline sequence — AC-S3

Apply anchored changes against no entry and a scoped entry and observe rejection plus default rebuild. Apply the same shape against a default baseline and observe UUID reconciliation with unchanged baseline coverage/provenance.

### Legacy sequence — AC-S4

Return unsorted duplicate-UUID snapshots through a legacy provider for default and explicit requests. Observe deterministic normalized output and request-derived provenance. Preserve provider coverage when present; when absent, observe the exact explicit range or the existing 30-day default window ending at that transaction's captured request-start instant. Then prove explicit-to-default rebuild.

### Replay sequence — AC-S5

1. Accept baseline A/c1 and advance durable state to c1.
2. Complete anchored query B/c2 and hold after query completion before cache acceptance.
3. Cancel or supersede it; verify c2 is rejected and newer lane ownership remains.
4. Replacement reads durable c1 and returns B/c2.
5. Publish A+B/c2; observe matching acceptance invocation before owner/coalesced success.
6. In one case advance durable state to c2. In another, silently retain c1 and prove the next request replays B and resubmits c2 safely.
7. In a separate reset sequence, prove all old-generation active/queued callers terminate once, register a fresh post-reset request, and observe it start before old stale release.

The gates for provider started, query complete, cache acceptance, acceptance invocation, durable anchor, reset successor, and stale release are distinct. An in-provider release gate is insufficient.

## Compatibility

- Existing callers of `HealthDataCache.workoutData(in:)` and `refreshWorkouts(in:)` require no source changes.
- Existing callers of `HealthKitService.fetchWorkouts(dateRange:)` require no source changes.
- Existing public provider conformers add no witness and receive snapshot-only fallback behavior.
- T023-001 source and provider-contract tests remain unchanged.
- Existing cache telemetry, filtering, no-provider empty result, error propagation, invalidation, and authorization-revocation behavior remain covered.

## Privacy and Logging

Allowed: semantic, aggregate count, duration, and cache outcome. Forbidden: workout health values, record identifiers, record-specific timestamps, source details, or checkpoint contents.
