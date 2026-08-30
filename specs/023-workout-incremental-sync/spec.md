# Feature Spec: HealthKit workout incremental sync

**Spec ID**: 023-workout-incremental-sync
**Status**: Candidate for planning review
**Origin**: Multica MY-1477; follow-up correctness repair after spec 018
**Constitution refs**: §I Health data privacy, §II Swift 6 strict concurrency, §III SPM package first, Cross-Cutting Quality Bars A-D/I

## Outcome

A person who has Apple Watch or HealthKit workouts in the workout list keeps seeing the previously synchronized records after reopening or refreshing the list. Anchored changes add, update, and delete records without treating an empty delta as an empty snapshot.

## Actors

- **Workout-list user**: expects Watch/HealthKit history to remain stable across repeated reads and refreshes.
- **HealthKitService client**: asks for the current workout view without needing to interpret HealthKit anchor mechanics.
- **HealthKit provider/cache**: distinguishes an authoritative snapshot from anchored changes and commits one immutable cache entry.

## User Story 1 - Preserve and reconcile HealthKit workout history (Priority: P1)

As a workout-list user, I want repeated HealthKit synchronization to retain existing workouts while incorporating later additions, updates, and deletions, so my Watch history does not disappear after an empty incremental response.

**Why this priority**: The current replacement behavior causes previously visible HealthKit workouts to disappear and directly recreates MY-1477.

**Independent Test**: A deterministic provider sequence establishes a baseline, emits anchored changes, and verifies the public cache result after each step without HealthKit hardware.

### Acceptance Scenarios

1. **Given** a baseline snapshot containing workout A, **when** the next anchored result has no upserts and no deletions, **then** the cache still returns A.
2. **Given** a baseline containing A, **when** an anchored result adds B and deletes A, **then** the cache returns only B.
3. **Given** an existing workout A, **when** an anchored result carries a changed record with A's UUID, **then** the changed record replaces A and no duplicate remains.
4. **Given** a delta has already been applied, **when** the identical delta is applied again, **then** the result is unchanged.
5. **Given** records with different start times or the same start time, **when** the result is read, **then** records are ordered by start time descending with UUID as the deterministic tie-breaker.
6. **Given** the in-memory workout cache is empty while a persisted HealthKit anchor exists, **when** workouts are requested, **then** an authoritative baseline is rebuilt before anchored changes are accepted.
7. **Given** a cached default-window snapshot, **when** a wider explicit date range is requested, **then** the wider range is fetched as its own authoritative snapshot rather than being satisfied by the narrower cache.
8. **Given** an explicit range snapshot, **when** the default workout view is requested later, **then** that scoped snapshot is not treated as the default anchored baseline.
9. **Given** baseline A and an anchored delta containing B has completed its provider query, **when** that request is cancelled or superseded before cache acceptance, **then** its checkpoint is rejected, the next read still obtains B from the prior durable anchor, and the replacement candidate is submitted to provider acceptance only after A+B is published; silent durable no-advance remains replayable.
10. **Given** an anchored refresh is superseded by another refresh with the same semantic and range, **when** the older request completes late, **then** it cannot publish cache state, persist its checkpoint, or clear the newer request's in-flight ownership.
11. **Given** callers coalesce on one request, **when** a non-owning caller cancels while the owner continues, **then** only that caller completes with cancellation exactly once and the remaining callers receive the accepted result; when the owning caller cancels, that request is retired and every attached waiter completes exactly once without accepting its result.
12. **Given** an active provider turn and queued successor work, **when** cancellation, supersession, `invalidateWorkouts()`, or `invalidateAll()` retires the active generation, **then** every affected waiter is released, current-generation successor work can start without waiting for a non-cooperative stale provider, and any late stale result is rejected.
13. **Given** cache-accepted state A/c1 and a current anchored result B/c2, **when** the result is accepted, **then** the immutable cache entry records A+B with candidate c2 and the cache synchronously invokes provider acceptance for c2 in the same actor turn before any success waiter completes. If that `Void` acceptance silently does not advance durable state, the next query still reads c1 and safely replays B; c2 is never decoded, compared, or ordered by the cache.

## Edge Cases

- Deleting an unknown UUID is a no-op.
- If the same UUID appears in both upserts and deletions in one delta, deletion wins.
- An empty authoritative snapshot establishes an empty cache; an empty delta preserves the prior cache.
- Duplicate UUIDs within one provider response collapse to one record deterministically.
- Switching between default-window and explicit-range requests may rebuild the single workout cache entry; it must never claim coverage it did not fetch.
- In-flight work for different query shapes or ranges must not be coalesced together.
- Cache invalidation must win over non-cooperative provider cancellation.
- A checkpoint-persistence failure after cache publication leaves the previous anchor intact; replay from the older anchor is safe because UUID reconciliation is idempotent.
- Synchronous provider acceptance reports no persistence outcome. A silent no-advance is modeled as durable-anchor lag and replay, never as confirmed persistence or cache rollback.
- Cancellation racing registration or settlement must have one terminal winner; a late or duplicate completion event is a no-op.
- Invalidation must drain active and queued caller waits before discarding their indexes; no continuation may be orphaned.
- Forward checkpoint progress is decided by generation/key/request-instance currentness, never by inspecting opaque anchor contents or timestamps.

## Functional Requirements

- **FR-001**: The workout fetch contract MUST identify whether a response is an authoritative snapshot or anchored changes.
- **FR-002**: Every authoritative snapshot MUST report the concrete date coverage it fetched; the default first-sync window MUST NOT be represented as unbounded coverage.
- **FR-003**: Anchored changes MUST carry UUID-keyed upserts and deleted UUIDs, and MUST apply only to a compatible baseline snapshot.
- **FR-004**: Anchored changes MUST reconcile by UUID using whole-entry replacement: upsert changed records, apply deletions after upserts, deduplicate, then publish one newly built cache entry.
- **FR-005**: Empty anchored changes MUST preserve the prior records and coverage.
- **FR-006**: Explicit date-range requests MUST use anchor-free snapshot semantics and MUST NOT advance the default incremental anchor.
- **FR-007**: An empty, invalidated, or incompatible workout cache MUST force a baseline snapshot before accepting anchored changes.
- **FR-008**: Workout fetch coalescing MUST be keyed by request semantic and date range so unrelated work cannot share a result.
- **FR-009**: Workout currentness MUST combine invalidation generation with a unique request instance so cancelled, late, or same-semantic superseded work cannot publish cache state, persist an anchor checkpoint, or clear a newer in-flight owner.
- **FR-010**: `workoutData(in:)`, `refreshWorkouts(in:)`, and the existing direct `fetchWorkouts(dateRange:)` entry point MUST remain source-compatible; the direct service entry point MUST use anchor-free snapshot behavior and MUST NOT independently read or advance the default workout anchor.
- **FR-011**: The precise prepared-fetch capability MUST remain package-internal and MUST NOT add public witness requirements. Existing public provider conformers and tests MUST remain source-compatible through anchor-free snapshot-only fallback behavior, while HealthKitService and cache tests may adopt the package-internal capability for precise snapshot/delta semantics.
- **FR-012**: Final workout projections MUST be deterministically ordered by start date descending, then UUID.
- **FR-013**: Logs and signposts MUST contain only aggregate metadata such as query type, count, and duration; no workout health values or details may be logged.
- **FR-014**: Provider failure, cancellation, invalidation, or rejected currentness MUST preserve the last accepted cache/anchor pair and surface existing error behavior to the caller.
- **FR-015**: An anchor-advancing provider fetch MUST be available only through the cache-facing prepare/accept seam and return an opaque pending checkpoint without persisting it. For a current result, the cache acceptance authority MUST construct one immutable entry containing the matching candidate checkpoint, publish that entry, and synchronously invoke provider acceptance for the same checkpoint in one actor turn with no intervening suspension or waiter completion. The existing `Void` acceptance is not a persistence receipt: silent no-advance leaves the durable anchor behind and MUST be handled by idempotent replay. A rejected result and the direct snapshot entry point MUST neither publish a candidate checkpoint nor invoke acceptance.
- **FR-016**: All mutable workout request, transaction, waiter, and provider-turn state MUST be isolated to `HealthDataCache`. The implementation MUST use compiler-checked Sendable value/task state; the final T023-002 production and test files MUST contain no `@unchecked Sendable`, `@preconcurrency`, or `nonisolated(unsafe)`, and production transaction state MUST contain no lock-owned mutable helper object or yield-based polling.
- **FR-017**: One actor-isolated settlement authority MUST remove a waiter before resuming it and MUST be the only path that completes caller waits for success, failure, cancellation, supersession, or invalidation. Non-owner cancellation MUST affect only that waiter; owner cancellation MUST retire the request and complete all attached waiters exactly once.
- **FR-018**: Provider-turn scheduling MUST use actor-owned request identities rather than independently synchronized continuation holders. Cancellation, supersession, and invalidation MUST retire active/queued turns, release every affected caller, and make eligible successor work runnable without awaiting a stale non-cooperative provider.
- **FR-019**: Pending checkpoints MUST remain opaque to `HealthDataCache`. Cache currentness MUST rely only on generation, semantic/range key, and request-instance identity; the cache MUST NOT parse, compare, timestamp-order, or otherwise infer ordering from checkpoint contents.

## Key Entities

- **Workout snapshot**: Authoritative records for one concrete date coverage.
- **Workout changes**: Anchored UUID upserts and deletions relative to a compatible snapshot.
- **Workout cache entry**: One immutable, sorted record set plus its coverage, snapshot provenance, and optional opaque cache-accepted candidate checkpoint; the checkpoint is present for accepted baseline/delta state and absent for anchor-free explicit-range snapshots.
- **Workout fetch key**: Request semantic plus optional date range; identifies coalescible work.
- **Pending anchor checkpoint**: Opaque continuation state returned by a baseline/delta query and submitted to synchronous provider acceptance only after the matching cache transition is published; submission does not prove durable advancement.
- **Workout request instance**: Unique identity used with the workout generation and fetch key to reject stale or same-semantic superseded results.
- **Workout transaction**: Actor-owned request state that binds one request instance, its owner and coalesced waiters, provider task/turn phase, prepared outcome, and terminal result.
- **Caller waiter**: Actor-owned identity plus pending continuation that can transition once from pending to success, failure, or cancellation.
- **Provider lane**: Actor-owned active request identity plus queued request identities for one anchor domain; it contains no separately synchronized waiter object.
- **Cache-accepted workout state**: One immutable workout cache entry whose optional recorded checkpoint matches the candidate submitted to synchronous provider acceptance for the same transaction; durable provider state may lag silently and replay.

## Files in Scope

- `Packages/HealthKitService/Sources/HealthKitService/HealthDataCache.swift`
- `Packages/HealthKitService/Sources/HealthKitService/HealthKitService.swift`
- `Packages/HealthKitService/Sources/HealthKitService/HealthWorkoutRecord.swift`
- `Packages/HealthKitService/Tests/HealthKitServiceTests/HealthWorkoutCacheTests.swift`
- `Packages/HealthKitService/Tests/HealthKitServiceTests/HealthWorkoutQueryContractTests.swift` (new, if the provider contract needs focused coverage)
- `Packages/HealthKitService/Tests/HealthKitServiceTests/PrivacyLoggingTests.swift` only if the existing audit needs an additional aggregate-only assertion

## Files NOT to Touch

- `VitalStride/Sources/WorkoutListView.swift` and all other AppUI files
- `Packages/VitalModels/**` and SwiftData/CloudKit schemas
- `Packages/HealthKitService/Sources/HealthKitService/WorkoutSessionManager.swift`
- WatchConnectivity and live heart-rate paths
- HealthKit workout write/delete behavior outside consumption of anchored deleted IDs
- `VitalStride.xcodeproj/**` and `project.yml`

## Public Signatures

- Preserve the current public call shape and defaults of `HealthDataCache.workoutData(in:)`.
- Preserve the current public call shape and defaults of `HealthDataCache.refreshWorkouts(in:)`.
- Preserve the current public call shape and defaults of `HealthKitService.fetchWorkouts(dateRange:)`.
- Define the direct service method as an anchor-free authoritative snapshot; reserve anchor preparation/commit for the cache-facing provider seam.
- Keep the prepared request/result/acceptance seam package-internal, with no new public provider or witness requirement; preserve source compatibility for existing public providers through snapshot-only fallback behavior and behavioral tests.

## Success Criteria

- **SC-001**: All thirteen acceptance scenarios are deterministic unit tests and pass without HealthKit hardware.
- **SC-002**: The original regression sequence (A, then empty anchored changes) returns A after the second fetch.
- **SC-003**: The add/update/delete/idempotency/order matrix produces the same UUID-ordered projection on every repetition.
- **SC-004**: A default 30-day snapshot cannot satisfy a wider explicit-range request in tests.
- **SC-005**: A query-complete/cache-not-yet-accepted adversarial test proves anchored B/c2 is rejected after cancellation or supersession, the replacement query reads from c1, A+B/c2 becomes the next cache-accepted state, provider acceptance for c2 is invoked before caller success, and the stale request cannot repopulate, invoke acceptance, or clear newer ownership.
- **SC-006**: From `Packages/HealthKitService`, `swift build && swift test` exits successfully.
- **SC-007**: No AppUI, model schema, or generated project file changes appear in the implementation diff.
- **SC-008**: Cancellation/invalidation tests use explicit gates and prove every owner, coalesced waiter, and queued provider request reaches one terminal outcome without sleeps, yield loops, hangs, or double continuation resume.
- **SC-009**: The final two-file diff contains no new unsafe concurrency annotation and production `HealthDataCache.swift` contains no checkpoint decoding/ordering or out-of-actor lock-based waiter state.

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
- Process failure or a silent no-op acceptance may leave the persisted anchor behind the in-memory transition, which is safe to replay. The current `Void` seam cannot confirm durable advancement; planning requires invocation ordering and replay safety rather than a false persistence-success guarantee.
