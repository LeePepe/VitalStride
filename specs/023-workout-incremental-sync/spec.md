# Feature Spec: HealthKit workout incremental sync

**Spec ID**: 023-workout-incremental-sync
**Status**: Successor candidate for planning review
**Origin**: Multica MY-1477; successor planning after cancelled MY-1483 / T023-002
**Successor baseline**: `main` at `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`
**Constitution refs**: §I Health data privacy, §II Swift 6 strict concurrency, §III SPM package first, Cross-Cutting Quality Bars A-D/I

## Outcome

A person who has Apple Watch or HealthKit workouts in the workout list keeps seeing the previously synchronized records after reopening or refreshing the list. Anchored changes add, update, and delete records without treating an empty delta as an empty snapshot.

## Actors

- **Workout-list user**: expects Watch/HealthKit history to remain stable across repeated reads and refreshes.
- **HealthKitService client**: asks for the current workout view without needing to interpret HealthKit anchor mechanics.
- **HealthKit provider/cache**: distinguishes an authoritative snapshot from anchored changes and commits one immutable cache entry.

## Executable Successor Acceptance Tests

These five acceptance tests are the entry contract for the successor. They are tested through the public cache interface with deterministic, actor-safe provider adapters; implementation-private state is not a test interface.

- **AC-S1 — Single settlement authority**: Drive success, provider failure, non-owner cancellation, owner cancellation, refresh supersession, `invalidateWorkouts()`, and `invalidateAll()` across an owner plus coalesced waiters. Every caller records exactly one terminal outcome, a non-owner cancellation affects only that waiter, owner retirement settles all attached waiters, and a source audit finds exactly one continuation-resume site that removes the waiter before resuming it.
- **AC-S2 — Real provider lanes**: Hold an active default-anchor request, enqueue a same-generation same-lane successor, and start two different explicit-range requests. Supersession or owner retirement pumps the eligible queued successor before the stale provider is released, while the independent range lanes progress independently. Separately, invalidation/authorization reset drains every old-generation active and queued caller; a newly registered post-reset request starts before the old stale provider is released. Late stale completions cannot publish, accept a checkpoint, or clear newer ownership.
- **AC-S3 — Compatible anchored baseline**: Attempt anchored changes with no cache entry and with an explicit-range entry, then with a compatible default entry. Incompatible changes are rejected and cause a default baseline rebuild; compatible changes preserve the baseline's concrete coverage and default provenance while applying the UUID delta.
- **AC-S4 — Deterministic legacy snapshots**: Feed a legacy public provider unsorted records with duplicate UUIDs for both a default request and an explicit range. Each snapshot is UUID-normalized and sorted by start date descending then UUID; provider-reported coverage is preserved. When coverage is absent, an explicit request uses its exact range and a default request uses the existing 30-day window ending at that transaction's captured request-start instant. Request-derived default/scoped provenance prevents a scoped entry from satisfying a later default read.
- **AC-S5 — Distinct transaction gates**: Use separate provider-started, query-complete, cache-acceptance, acceptance-invocation, durable-anchor, reset-successor, and stale-release gates. Prove A/c1 → completed B/c2 → rejection → replay from durable c1 → A+B/c2 publication → c2 acceptance invocation → owner/coalesced success; separately prove silent durable no-advance replays safely. For reset, prove old-generation owners, coalesced waiters, and queued requests all terminate once, then register a fresh post-reset request and prove it starts before the old stale provider is released.

## Existing Behavior at the Successor Baseline

- T023-001 is delivered. `HealthKitService` can prepare baseline snapshots, anchored changes, and explicit-range snapshots, and can synchronously accept or reject a prepared result. The direct public fetch remains an anchor-free snapshot.
- `HealthDataCache.workoutData(in:)` currently caches one process-memory entry, treats nil coverage as covering every request, and coalesces all workout work through one global task.
- `refreshWorkouts(in:)` cancels that global task and starts a replacement. Provider results replace the whole workout array; deleted UUIDs and prepared semantics are not consumed.
- Existing public-cache behavior includes cache hit/miss/refresh telemetry, date filtering, no-provider empty results, thrown provider errors, workout invalidation, global invalidation, and authorization-revocation clearing.
- Existing cache tests use lock-owned mutable state plus sleep timing and do not expose the query-complete/cache-acceptance or reset-successor boundaries.

## Compatibility

- Preserve the public call shapes and defaults of `HealthDataCache.workoutData(in:)`, `HealthDataCache.refreshWorkouts(in:)`, `HealthKitService.fetchWorkouts(dateRange:)`, and the public `WorkoutDataProviding` witness.
- Preserve T023-001 provider-contract behavior and tests, existing cache telemetry semantics, date filtering, no-provider empty results, error propagation, invalidation, and authorization-revocation clearing.
- Add no public witness, AppUI-facing interface, package dependency, schema, persistence store, refresh policy, or HealthKit write behavior. The precise prepared capability remains package-internal.
- Continue to permit legacy public providers through anchor-free snapshot fallback; they do not supply or accept checkpoints.

## Removed Behavior

The successor explicitly removes only the following behaviors observed at exact baseline `e8cfc19…`; no existing product behavior or accepted test is removed or weakened. Removal authority is the accepted planning revision `67614a0c5d29450326a88c60d45e175416bba0aa`, carried forward and sharpened by Owner stop decision `01a138de-d88f-7206-a2de-82f3e45579ee`.

- Remove the single global workout in-flight task as the coalescing/scheduling authority (baseline: `HealthDataCache.workoutInFlightFetch`; authority: accepted plan + Owner stop requirement 2).
- Remove whole-result replacement for anchored changes (baseline: `performWorkoutFetch` consumes only `.workouts`; authority: accepted plan + Owner stop requirements 3 and 5).
- Remove nil-coverage-as-unbounded cache compatibility (baseline: `coversRange`; authority: accepted plan + Owner stop requirements 3 and 4).
- Remove `@unchecked Sendable`/`NSLock` state and `Task.sleep` coordination from the successor test infrastructure (baseline: `HealthWorkoutCacheTests`; authority: accepted plan + Owner stop requirements 1, 2, and 5).

## Prohibited Successor Designs and Final Audit

These are prospective design constraints, not claims about behavior present at the baseline:

- No caller, provider task, reset path, or lane-drain path may resume a continuation outside the one actor-owned remove-before-resume settlement authority.
- The cache must not decode, compare, timestamp/order, or carry forward checkpoints, and request-order recency must not substitute for generation/key/request identity.
- Lanes may store request identities only; they must not introduce continuation-holder turns, lock-owned state, or sleep/yield polling.

## User Story 1 - Preserve and reconcile HealthKit workout history (Priority: P1)

As a workout-list user, I want repeated HealthKit synchronization to retain existing workouts while incorporating later additions, updates, and deletions, so my Watch history does not disappear after an empty incremental response.

**Why this priority**: The current replacement behavior causes previously visible HealthKit workouts to disappear and directly recreates MY-1477.

**Independent Test**: A deterministic provider sequence establishes a baseline, emits anchored changes, and verifies the public cache result after each step without HealthKit hardware.

### Acceptance Scenarios

1. **AC-01**: **Given** a baseline snapshot containing workout A, **when** the next anchored result has no upserts and no deletions, **then** the cache still returns A.
2. **AC-02**: **Given** a baseline containing A, **when** an anchored result adds B and deletes A, **then** the cache returns only B.
3. **AC-03**: **Given** an existing workout A, **when** an anchored result carries a changed record with A's UUID, **then** the changed record replaces A and no duplicate remains.
4. **AC-04**: **Given** a delta has already been applied, **when** the identical delta is applied again, **then** the result is unchanged.
5. **AC-05**: **Given** records with different start times or the same start time, **when** the result is read, **then** records are ordered by start time descending with UUID as the deterministic tie-breaker.
6. **AC-06**: **Given** the in-memory workout cache is empty while a persisted HealthKit anchor exists, **when** workouts are requested, **then** an authoritative baseline is rebuilt before anchored changes are accepted.
7. **AC-07**: **Given** a cached default-window snapshot, **when** a wider explicit date range is requested, **then** the wider range is fetched as its own authoritative snapshot rather than being satisfied by the narrower cache.
8. **AC-08**: **Given** an explicit range snapshot, **when** the default workout view is requested later, **then** that scoped snapshot is not treated as the default anchored baseline.
9. **AC-09**: **Given** baseline A and an anchored delta containing B has completed its provider query, **when** that request is cancelled or superseded before cache acceptance, **then** its checkpoint is rejected, the next read still obtains B from the prior durable anchor, and the replacement candidate is submitted to provider acceptance only after A+B is published; silent durable no-advance remains replayable.
10. **AC-10**: **Given** an anchored refresh is superseded by another refresh with the same semantic and range, **when** the older request completes late, **then** it cannot publish cache state, accept a checkpoint, or clear the newer request's in-flight ownership.
11. **AC-11**: **Given** callers coalesce on one request, **when** a non-owning caller cancels while the owner continues, **then** only that caller completes with cancellation exactly once and the remaining callers receive the accepted result; when the owning caller cancels, that request is retired and every attached waiter completes exactly once without accepting its result.
12. **AC-12**: **Given** an active provider turn and queued work, **when** owner cancellation or supersession retires the request without changing generation, **then** every affected waiter is released and the next eligible same-generation successor starts without waiting for the stale provider. **When** workout/global invalidation or authorization reset advances generation, **then** all old active/queued callers are settled and removed; a newly registered post-reset request may start before the old stale provider returns, and any late old-generation result is rejected.
13. **AC-13**: **Given** cache-accepted state A/c1 and a current anchored result B/c2, **when** the result is accepted, **then** the immutable cache entry records A+B with candidate c2 and the cache synchronously invokes provider acceptance for c2 in the same actor turn before any success waiter completes. If that `Void` acceptance silently does not advance durable state, the next query still reads c1 and safely replays B; c2 is never decoded, compared, or ordered by the cache.

## Edge Cases

- Deleting an unknown UUID is a no-op.
- If the same UUID appears in both upserts and deletions in one delta, deletion wins.
- An empty authoritative snapshot establishes an empty cache; an empty delta preserves the prior cache.
- Duplicate UUIDs within one provider response collapse to one record deterministically.
- Switching between default-window and explicit-range requests may rebuild the single workout cache entry; it must never claim coverage it did not fetch.
- In-flight work for different query shapes or ranges must not be coalesced together.
- Cache invalidation must win over non-cooperative provider cancellation.
- A checkpoint-persistence failure after cache publication leaves the previous anchor intact; replay from the older anchor is safe because UUID reconciliation is idempotent.
- A prepared baseline/change result with no candidate checkpoint and a legacy snapshot fallback both publish checkpoint-absent state and invoke no checkpoint acceptance.
- Cancellation racing registration or settlement has one terminal winner; a late or duplicate completion event is a no-op.
- Invalidation drains active and queued caller waits before discarding their indexes; no continuation may be orphaned.
- A reset never carries an old queued request into the new generation; its observable successor is a newly registered post-reset request.
- Forward progress is decided by generation, semantic/range key, and request identity, never by inspecting opaque checkpoint contents or timestamps.

## Functional Requirements

- **FR-001**: The workout fetch contract MUST identify whether a response is an authoritative snapshot or anchored changes.
- **FR-002**: Every authoritative snapshot MUST publish concrete date coverage. Provider-reported coverage MUST be preserved. When a legacy fallback omits coverage, an explicit request MUST use its exact requested range and a default request MUST use the existing 30-day default window ending at the transaction's captured request-start instant; nil MUST NOT be represented as unbounded coverage.
- **FR-003**: Anchored changes MUST carry UUID-keyed upserts and deleted UUIDs, and MUST apply only to a compatible baseline snapshot.
- **FR-004**: Anchored changes MUST reconcile by UUID using whole-entry replacement: upsert changed records, apply deletions after upserts, deduplicate, then publish one newly built cache entry.
- **FR-005**: Empty anchored changes MUST preserve the prior records and coverage.
- **FR-006**: Explicit date-range requests MUST use anchor-free snapshot semantics and MUST NOT advance the default incremental anchor.
- **FR-007**: An empty, invalidated, or incompatible workout cache MUST force a baseline snapshot before accepting anchored changes.
- **FR-008**: Workout fetch coalescing MUST be keyed by request semantic and date range so unrelated work cannot share a result.
- **FR-009**: Workout currentness MUST combine invalidation generation with a unique request instance so cancelled, late, or same-semantic superseded work cannot publish cache state, persist an anchor checkpoint, or clear a newer in-flight owner.
- **FR-010**: `workoutData(in:)`, `refreshWorkouts(in:)`, and the existing direct `fetchWorkouts(dateRange:)` entry point MUST remain source-compatible; the direct service entry point MUST use anchor-free snapshot behavior and MUST NOT independently read or advance the default workout anchor.
- **FR-011**: The precise prepared-fetch capability MUST remain package-internal and MUST NOT add public witness requirements. Existing public provider conformers and tests MUST remain source-compatible through anchor-free snapshot-only fallback behavior.
- **FR-012**: Final workout projections MUST be deterministically ordered by start date descending, then UUID.
- **FR-013**: Logs and signposts MUST contain only aggregate metadata such as query type, count, and duration; no workout health values or details may be logged.
- **FR-014**: Provider failure, cancellation, invalidation, or rejected currentness MUST preserve the last accepted cache/anchor pair and surface existing error behavior to the caller.
- **FR-015**: An anchor-advancing provider fetch MUST be available only through the cache-facing prepare/accept seam and may return an opaque pending checkpoint without persisting it. When a current prepared baseline/change supplies a candidate, the cache MUST publish one immutable entry containing it and synchronously invoke provider acceptance for the same candidate in one actor turn before waiter completion. Candidate absence is valid and invokes no acceptance. The existing `Void` acceptance is an invocation, not a persistence receipt; rejected results and direct snapshots MUST invoke no acceptance.
- **FR-016**: All mutable workout request, transaction, waiter, and provider-lane state MUST be isolated to `HealthDataCache` as compiler-checked Sendable value/task state. The two successor files MUST contain no `@unchecked Sendable`, `@preconcurrency`, or `nonisolated(unsafe)`; production transaction state MUST contain no lock-owned mutable helper or yield-based polling.
- **FR-017**: One actor-isolated settlement authority MUST remove a waiter before resuming it and MUST be the only path that completes caller waits for success, failure, cancellation, supersession, or invalidation. Non-owner cancellation MUST affect only that waiter; owner cancellation MUST retire the request and complete all attached waiters exactly once.
- **FR-018**: Provider-turn scheduling MUST use lane-domain identities with actor-owned active and queued request identities. Baseline and anchored work share the default-anchor lane; distinct explicit ranges use independent lanes. Owner cancellation and supersession MUST retire affected same-generation work and pump the next eligible queued successor without awaiting a stale provider. Invalidation and authorization reset MUST advance generation and drain all old active/queued work; only a newly registered post-reset request may start in the new generation before an old stale provider returns.
- **FR-019**: Pending checkpoints MUST remain opaque to `HealthDataCache`. Cache currentness MUST rely only on generation, semantic/range key, and request-instance identity; the cache MUST NOT parse, compare, timestamp-order, or otherwise infer ordering from checkpoint contents.
- **FR-020**: Every authoritative snapshot, including legacy fallback, MUST be normalized to one record per UUID before publication; the final occurrence of a repeated UUID in one provider result wins. The projection MUST then be sorted by start date descending and UUID. Legacy provenance MUST be derived from the request as default or scoped. Provider-reported coverage MUST be preserved; missing explicit coverage MUST use that exact request, while missing default coverage MUST use the existing 30-day default window ending at the transaction's captured request-start instant.

## Key Entities

- **Workout snapshot**: Authoritative records for one concrete date coverage.
- **Workout changes**: Anchored UUID upserts and deletions relative to a compatible snapshot.
- **Workout cache entry**: One immutable, sorted record set plus its coverage, snapshot provenance, and optional opaque cache-accepted candidate checkpoint.
- **Workout fetch key**: Request semantic plus optional date range; identifies coalescible work.
- **Pending anchor checkpoint**: Opaque continuation state returned by a baseline/delta query and persisted only after the matching cache transition is accepted.
- **Workout request instance**: Unique identity used with the workout generation and fetch key to reject stale or same-semantic superseded results.
- **Workout transaction**: Actor-owned request state binding one request identity, its owner and coalesced waiters, provider task/lane phase, prepared outcome, and terminal result.
- **Caller waiter**: Actor-owned identity plus pending continuation that transitions once from pending to success, failure, or cancellation.
- **Provider lane**: Actor-owned active request identity plus queued request identities for one lane domain; it contains no separately synchronized continuation holder.
- **Lane domain**: The default incremental anchor domain or one exact anchor-free explicit range; it is distinct from the semantic/range fetch key used for coalescing and currentness.

## Files in Scope

- `Packages/HealthKitService/Sources/HealthKitService/HealthDataCache.swift`
- `Packages/HealthKitService/Tests/HealthKitServiceTests/HealthWorkoutCacheTests.swift`

## Files NOT to Touch

- `VitalStride/Sources/WorkoutListView.swift` and all other AppUI files
- `Packages/VitalModels/**` and SwiftData/CloudKit schemas
- `Packages/HealthKitService/Sources/HealthKitService/HealthKitService.swift`
- `Packages/HealthKitService/Sources/HealthKitService/HealthWorkoutRecord.swift`
- `Packages/HealthKitService/Tests/HealthKitServiceTests/HealthWorkoutQueryContractTests.swift`
- `Packages/HealthKitService/Tests/HealthKitServiceTests/PrivacyLoggingTests.swift`
- `Packages/HealthKitService/Sources/HealthKitService/WorkoutSessionManager.swift`
- WatchConnectivity and live heart-rate paths
- HealthKit workout write/delete behavior outside consumption of anchored deleted IDs
- `VitalStride.xcodeproj/**` and `project.yml`

## Public Signatures

- Preserve the current public call shape and defaults of `HealthDataCache.workoutData(in:)`.
- Preserve the current public call shape and defaults of `HealthDataCache.refreshWorkouts(in:)`.
- Preserve the current public call shape and defaults of `HealthKitService.fetchWorkouts(dateRange:)`.
- Define the direct service method as an anchor-free authoritative snapshot; reserve anchor preparation/commit for the cache-facing provider seam.
- Consume the delivered prepared request/result/acceptance seam through a package-internal capability declared in the cache-owned file; add no public provider, witness, or AppUI interface.

## Success Criteria

- **SC-001**: AC-S1 through AC-S5 and AC-01 through AC-13 are deterministic unit tests and pass without HealthKit hardware.
- **SC-002**: The original regression sequence (A, then empty anchored changes) returns A after the second fetch.
- **SC-003**: The add/update/delete/idempotency/order matrix produces the same UUID-ordered projection on every repetition.
- **SC-004**: A default 30-day snapshot cannot satisfy a wider explicit-range request in tests.
- **SC-005**: A query-complete/cache-not-yet-accepted adversarial test proves anchored B/c2 is rejected after cancellation or supersession, the replacement query reads from c1, A+B/c2 becomes the next cache-accepted state, provider acceptance for c2 is invoked before caller success, and stale work cannot publish, accept, or clear newer ownership.
- **SC-006**: From `Packages/HealthKitService`, `swift build && swift test` exits successfully.
- **SC-007**: No AppUI, model schema, or generated project file changes appear in the implementation diff.
- **SC-008**: Cancellation/invalidation tests use explicit gates and prove every owner, coalesced waiter, and queued provider request reaches one terminal outcome without sleeps, yield loops, hangs, or double continuation resume.
- **SC-009**: The final two-file diff contains no unsafe concurrency annotation; production contains one continuation-resume site and no checkpoint decoding/ordering, lock-owned waiter state, continuation-holder turn, request-order currentness, prior-checkpoint carry-forward, or timing polling.

## Non-Goals

- Persisting workout records in the L2 SwiftData health cache.
- Adding observer/background workout synchronization or a new refresh policy/TTL.
- Redesigning the workout list or workout detail UI.
- Changing HealthKit authorization, workout writing, or live workout control.
- Broad refactoring of the health-sample cache path.

## Assumptions

- HealthKit anchored queries continue to return only changes after a saved anchor.
- The workout UUID is the stable identity for upsert and deletion.
- The existing 30-day default first-sync window remains the product baseline.
- The workout cache remains process-memory-only; loss of the process cache therefore requires a new baseline even if an anchor persisted.
- One app-owned `HealthDataCache` is the sole workout-anchor acceptance authority for its provider/device identity.
- Prepared checkpoint acceptance remains synchronous and non-suspending at the package-internal provider seam.
- Process failure or silent no-op acceptance may leave the durable anchor behind the in-memory transition; replay is safe and acceptance invocation is not a durable-persistence receipt.
