# Research: HealthKit workout incremental sync

## Question

Why can a repeated workout synchronization remove previously visible Apple Watch workouts, and what is the smallest durable seam that preserves snapshot, range, and invalidation correctness?

## Evidence

| Observation | Repository evidence | Consequence |
|---|---|---|
| Default workout fetch uses the persisted workout anchor | `HealthKitService.swift:565-591` | Later calls return changes, not a complete list. |
| Explicit date range uses no anchor | `HealthKitService.swift:568-584` | The same provider method also returns authoritative range snapshots. |
| Deleted UUIDs are returned | `HealthKitService.swift:606-607`; `HealthWorkoutRecord.swift:122-130` | The cache has enough deletion data but does not consume it. |
| Cache extracts only workouts | `HealthDataCache.swift:785-795` | Empty delta replaces the cached baseline with an empty array. |
| Default baseline is 30 days | `HealthKitService.swift:365,571-574` | A default result is bounded even though the cache records nil coverage. |
| Nil coverage claims every request is covered | `HealthDataCache.swift:745-755` | A later 90-day request can be incorrectly satisfied by 30 days of data. |
| Workout cache is memory-only; anchor persists | Cache state in `HealthDataCache.swift`; workout anchor in `HealthKitAnchorStore.swift:46-74` | A process restart can receive changes without a base snapshot. |
| One in-flight workout task is global | `HealthDataCache.swift:766-788` | Different ranges or request semantics can incorrectly share one result. |
| Workout anchor is saved before the result reaches the cache | `HealthKitService.swift:594-607` | A result rejected after provider completion can advance the anchor past changes that never reached the cache. |
| T023-001's prepared-fetch methods are package-internal while the cache owns the capability declaration | Post-T023-001 `HealthKitService.swift` and the T023-002 ownership table in `tasks.md` | A public prepared capability would require excluded public witness edits; a package-internal capability can be adopted across files in the same Swift module without widening scope. |
| Invalidated SHA `d85372895fd4561aba3185e31605076d9429d517` adds three unchecked Sendable mutable helpers | Reviewer FAIL `2b2f618d-9f89-41da-8848-32e8b19bfea2`; `HealthDataCache.swift` waiter/in-flight/provider-turn declarations | Locking mutable classes bypasses the required actor model and still permits double completion and stranded waits. |
| Coalesced cancellation has more than one continuation-resume path | Reviewer FAIL; invalidated waiter cancellation/registration flow | Cancellation can trap on double resume or skip a marked waiter without completing it. |
| Provider-turn cancellation removes a queued waiter without resuming it; invalidation does not drain turn state | Reviewer FAIL; invalidated provider-turn and invalidation paths | A cancelled or stale provider can indefinitely block a required successor and orphan callers. |
| Anchored acceptance records the previous checkpoint while persisting the candidate | Reviewer FAIL; invalidated anchored acceptance path | Cache and persisted checkpoint can advance to different logical states. |
| Cache-side opaque checkpoint comparison rejects normal forward progress | Reviewer FAIL; invalidated checkpoint-order helper | Anchor contents and timestamps are not a cache ordering contract; request currentness is the authority. |
| Draft PR #423 is open at the invalidated SHA with auto-merge disabled | GitHub PR state captured during replanning | The PR is preserved as evidence and must not be treated as a shippable or incremental-fix authority. |

## Decision 1: Make request and result semantics explicit

**Chosen**: Distinguish baseline snapshot, anchored changes, and explicit-range snapshot at the provider seam. Identify snapshot versus changes in the result and give snapshots concrete coverage.

**Why**: The optional date range currently overloads query scope and synchronization meaning. The cache cannot safely decide replacement versus merge from arrays alone.

**Compatibility**: Existing public cache methods and direct `fetchWorkouts(dateRange:)` remain source-compatible. The precise prepared-fetch capability remains package-internal; existing public provider conformers retain anchor-free snapshot-only fallback behavior and require no new public witnesses. Fallback results carry no checkpoint, so the cache publishes checkpoint-absent state and invokes no checkpoint acceptance.

### Alternatives rejected

- **Treat every nil request as a delta when cache exists**: fails after process restart because the anchor persists but the base does not.
- **Infer snapshot from empty cache**: a persisted-anchor delta can arrive to an empty cache and be mistaken for a complete baseline.
- **Reset the anchor on every read**: correct but discards the benefit of anchored synchronization and broadens anchor lifecycle changes.
- **Persist workout records in L2**: larger schema/privacy scope not required to fix MY-1477.
- **Expose prepared checkpoint operations as public provider requirements**: adds ordering and persistence knowledge to the public interface, forces T023-001 witness access changes in a T023-002 repair, and provides no external caller leverage.

## Decision 2: Keep one authoritative workout cache entry

**Chosen**: A snapshot replaces the entry for its declared provenance/coverage. Anchored changes reconcile only into a compatible default baseline. Switching between incompatible default/range shapes rebuilds rather than claiming false coverage.

**Why**: This keeps the current cache topology and avoids a new multi-range cache policy. Correctness is preferred over retaining every prior query shape in memory.

### Alternatives rejected

- **Merge arbitrary range snapshots into one interval**: can claim unfetched gaps are covered.
- **Introduce a persistent or multi-segment workout cache**: unnecessary architecture growth for this bug.

## Decision 3: Reconcile changes by UUID with immutable publication

**Chosen**: Build a new UUID-keyed collection from the prior entry, apply upserts, apply deletions last, sort deterministically, and assign one new entry.

**Why**: UUID is already the record identity and deleted-object identity. Whole-entry assignment preserves the package red line against in-place cache mutation.

**Conflict rule**: If one delta both upserts and deletes a UUID, deletion wins.

## Decision 4: Defer checkpoint persistence to cache acceptance

**Chosen**: A prepared baseline/change fetch returns an opaque pending checkpoint and does not persist it. The cache actor validates currentness, publishes the corresponding whole cache entry, then synchronously invokes provider acceptance for that checkpoint without an intervening suspension point.

**Why**: Cache-first/acceptance-invocation-second gives at-least-once delivery. The existing acceptance returns no persistence outcome and can silently no-op, so the cache does not claim confirmed durability. If persistence is interrupted or silently does not advance, the old anchor replays changes and UUID reconciliation is idempotent. Persisting the checkpoint first creates an unsafe at-most-once gap where changes can be skipped permanently.

**Direct-call compatibility**: The existing direct service call shape remains, but it becomes an anchor-free authoritative snapshot with no default-anchor side effect. The cache-facing provider path is the only anchor prepare/accept authority.

### Alternatives rejected

- **Provider persists before returning, cache clears anchor when rejecting**: a process crash between persistence and cleanup still loses the delta.
- **Persist checkpoint and cache entry concurrently**: has no ordering guarantee and recreates the unsafe state.
- **Allow direct service calls to commit independently**: creates a second anchor writer outside cache acceptance and can move the anchor past an unaccepted cache transition.
- **Persist cache workouts alongside the anchor**: introduces workout L2 persistence and schema/privacy scope not required by MY-1477.

## Decision 5: Key coalescing and add request-instance currentness

**Chosen**: Key in-flight work by request semantic plus date range, and give each owning fetch a unique request instance. Add a workout-specific generation that changes on invalidation and incompatible snapshot operations. An explicit refresh creates a new owner even when its key matches the prior refresh.

**Why**: Actor isolation does not prevent stale writes after an `await`; cooperative cancellation alone cannot guarantee invalidation wins. Generation/key checks alone also cannot distinguish two same-semantic refreshes.

## Decision 6: Keep logs aggregate-only

**Chosen**: Query semantic, count, duration, and cache outcome may be logged. Workout values, timestamps tied to a record, source details, and identifiers may not be logged.

**Why**: Constitution §I permits aggregate operational metadata but prohibits actual health values/details.

## Decision 7: Keep the prepared-fetch capability at an internal seam

**Chosen**: Declare the prepared-fetch capability and the HealthKitService conformance in T023-002's cache-owned file with package-internal visibility. The existing public provider seam remains unchanged and acts as anchor-free snapshot-only compatibility behavior.

**Why**: The production adapter, cache consumer, and deterministic test adapter are all in the same Swift module. Package-internal witnesses declared by T023-001 are visible across source files, while making the capability public would force public witnesses in an excluded file without serving an external use case.

**Result semantic**: Cache acceptance follows the prepared result's declared semantic. If a requested anchored preparation legitimately falls back to a baseline because no persisted anchor exists, the cache publishes baseline coverage/provenance rather than treating the result as changes.

### Alternatives rejected

- **Add `HealthKitService.swift` to T023-002**: overlaps T023-001 ownership and expands the reviewed file graph for an access-control issue that can be solved at the owning seam.
- **Move the capability declaration into `HealthKitService.swift`**: changes file ownership but not Swift module visibility or behavior.
- **Remove production conformance and use only the public fallback**: bypasses prepared checkpoint acceptance and recreates the independent anchor/cache authority gap.

## Decision 8: Use one actor-owned transaction registry

**Chosen**: Keep request, owner/coalesced waiter, provider task, lane, prepared outcome, and terminal state as plain values owned by `HealthDataCache`. Route registration, settlement, and reset through three conceptual actor transitions.

**Why**: The cache entry, currentness generation, and in-flight ownership already live in this actor. Concentrating the mutable state there maximizes locality and lets Swift enforce isolation without unchecked annotations or independent locks.

### Alternatives compared

- **Separate private coordinator actor**: offers an isolated queue but forces cross-actor coordination around the cache entry and synchronous checkpoint acceptance, creating a shallower interface and another reentrancy seam.
- **Shared unstructured task values with caller-local cancellation**: keeps the common caller short but cannot centrally express owner versus non-owner cancellation, provider-lane release, or exactly-once continuation settlement.
- **Selected hybrid — actor registry plus provider adapters**: `HealthDataCache` owns orchestration; HealthKitService and deterministic tests remain adapters at the existing package-internal prepared seam. This keeps two real adapters while hiding transaction complexity.

## Decision 9: Queue request identities, not provider-turn continuations

**Chosen**: Model each provider lane as one active request identity plus queued identities. The actor starts the next eligible provider task; no separately synchronized object waits for a turn.

**Why**: Cancellation and invalidation can delete queued identities, settle their caller waits, revoke an active logical turn, and start a successor without depending on a stale provider's cooperation. A late result is rejected by its captured currentness identity.

## Decision 10: Centralize remove-before-resume settlement

**Chosen**: One actor authority owns all caller continuation completion. It removes each waiter before resuming it and treats later events as no-ops. A non-owner cancellation settles only that waiter; owner cancellation retires the request and settles every attached waiter.

**Why**: Actor serialization makes registration/cancellation/provider-result races deterministic and eliminates the invalidated design's direct second resume, skipped cancelled waiter, and unreachable waiter set.

## Decision 11: Publish one opaque candidate and invoke acceptance

**Chosen**: Build the accepted immutable entry with the prepared candidate checkpoint, publish it, synchronously invoke provider acceptance for that same checkpoint without suspension, and only then settle success. Never parse or compare checkpoint contents.

**Why**: The actor turn provides the observable cache-acceptance linearization point. T023-001's `Void` acceptance cannot report archive failure, so T023-002 proves invocation ordering rather than durable success. Process failure or silent no-advance leaves the durable anchor behind and causes idempotent replay; it never authorizes a persisted checkpoint ahead of its matching cache entry.

**Checkpoint absence**: A prepared baseline/change may supply no candidate, and a legacy snapshot fallback cannot supply one. Those results still publish valid records/coverage/provenance with checkpoint absent; the cache skips checkpoint acceptance because there is no candidate to submit.

**Rejected for this revision**: Reopening T023-001 so acceptance returns or throws a persistence outcome would require `HealthKitService.swift` and provider-contract-test ownership changes. Team Lead required the existing package/API/file boundaries, so that expansion is not authorized.

## Decision 12: Repair with vertical RED→GREEN tracer bullets

**Chosen**: Work one public-cache behavior at a time in fixed dependency order: reconciliation foundation, waiter settlement, provider-lane reset, atomic rejection/replay, then the remaining deterministic matrix.

**Why**: The invalidated candidate added a large test/implementation batch whose green suite missed the required transaction boundaries. One failing behavior followed by its minimal actor-owned implementation keeps tests sensitive to observable outcomes rather than the private mechanism.

## Decision 13: Treat the preserved rejected tree as a fingerprint, not a repair claim

**Evidence**: Repeated exact-SHA reviews `00966211-f963-48f7-ac63-8623621e0298` and `9d352f6d-5742-40a7-a047-365e1aae2cea` found the same five P1s at `f5690f1461a6cb07504d7f6e945220cb5213b2fb`. The second Fullstack handoff reused the same SHA and tree. The test blob is identical to invalidated `d85372895fd4561aba3185e31605076d9429d517`.

**Chosen**: Preserve the clean worktree/branch/Draft PR exactly at `f5690f…` until a reviewed dispatch, then replace the rejected design through A–F without reset or re-checkout. Stage 0 records source-pattern and test-blob fingerprints; every later exit proves an observable RED→GREEN behavior and the required byte removal/replacement.

**Why**: A package-green or audit statement cannot prove a changed tree. Fingerprints make unchanged source and insensitive tests mechanically visible while preserving the evidence chain and workspace continuity.

## Decision 14: Reject same-tree delivery before review

**Chosen**: Final readiness requires both mandatory file blobs to differ from `f5690f…`, the new commit SHA to differ from `f5690f…` and `d853728…`, the obsolete-pattern audit to be empty, the full package gate to pass, and local/tracking/remote/PR head equality at that new SHA. Fullstack must author the exact-SHA review request.

**Why**: The prior same-SHA rerun spent a review cycle without a remediation delta. A new commit hash alone is also insufficient if its tree is unchanged; the mandatory production and test deltas plus pattern audit prove replacement occurred.

## Validation Decision

All implementation changes are package-only. Repository-declared verification is:

```bash
cd Packages/HealthKitService
swift build && swift test
```

`xcodebuild` is forbidden for this scope.
