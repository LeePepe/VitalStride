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

## Decision 1: Make request and result semantics explicit

**Chosen**: Distinguish baseline snapshot, anchored changes, and explicit-range snapshot at the provider seam. Identify snapshot versus changes in the result and give snapshots concrete coverage.

**Why**: The optional date range currently overloads query scope and synchronization meaning. The cache cannot safely decide replacement versus merge from arrays alone.

**Compatibility**: Existing public cache methods and direct `fetchWorkouts(dateRange:)` remain source-compatible. Provider/result extensions need defaults and tests for existing conformers.

### Alternatives rejected

- **Treat every nil request as a delta when cache exists**: fails after process restart because the anchor persists but the base does not.
- **Infer snapshot from empty cache**: a persisted-anchor delta can arrive to an empty cache and be mistaken for a complete baseline.
- **Reset the anchor on every read**: correct but discards the benefit of anchored synchronization and broadens anchor lifecycle changes.
- **Persist workout records in L2**: larger schema/privacy scope not required to fix MY-1477.

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

## Decision 4: Key coalescing and add workout generation

**Chosen**: Key in-flight work by request semantic plus date range. Add a workout-specific generation that changes on workout invalidation and superseding snapshot operations.

**Why**: Actor isolation does not prevent stale writes after an `await`; cooperative cancellation alone cannot guarantee invalidation wins.

## Decision 5: Keep logs aggregate-only

**Chosen**: Query semantic, count, duration, and cache outcome may be logged. Workout values, timestamps tied to a record, source details, and identifiers may not be logged.

**Why**: Constitution §I permits aggregate operational metadata but prohibits actual health values/details.

## Validation Decision

All implementation changes are package-only. Repository-declared verification is:

```bash
cd Packages/HealthKitService
swift build && swift test
```

`xcodebuild` is forbidden for this scope.
