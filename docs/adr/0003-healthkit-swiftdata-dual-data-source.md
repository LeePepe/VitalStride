# ADR-0003: HealthKit + SwiftData Dual Data Source

**Status**: Accepted
**Date**: 2026-06-18 (backfilled)
**Deciders**: tianpli (project owner)

## Context

VitalStride needs to display two categories of data:

1. **System-provided health metrics** (heart rate, steps, sleep, body weight, etc.) — owned by HealthKit, written by other apps and the Apple Watch.
2. **App-owned training records** (workouts, sets, reps, weights, rest, notes) — structured data the user creates inside VitalStride.

The data have different ownership models, sync semantics, and access patterns:

- HealthKit data: external source of truth, query-only from our perspective, must respect Apple privacy framing, intermittently expensive to query.
- App-owned data: full CRUD, needs offline editing, benefits from typed schema.

A single store cannot serve both well. Apple's own apps (Health, Fitness) treat them as separate stores too.

## Decision

Run a **dual data source** with explicit layering:

### App-owned data → SwiftData (CloudKit-isolated)

- Model lives in `Packages/VitalModels/Sources/VitalModels/Models/`.
- `ModelContainer` is configured `cloudKitDatabase: .none` for the local-only training data. CloudKit sync is deliberately off for this layer in current scope.
- Training types: `Workout`, `Exercise`, `ExerciseSet`, `ExerciseSubSet`, etc.

### HealthKit data → HealthKit + L2 SwiftData cache

- `Packages/HealthKitService` wraps `HKHealthStore` and is the *only* code that talks to HealthKit.
- `HealthCacheEntry` (in `VitalModels`) is the SwiftData L2 cache — a typed, persistent copy of selected HealthKit samples for offline display and aggregation.
- `HealthDataCache` (actor in `HealthKitService`) is the L1 in-memory cache layer above the L2 store.
- Anchor queries keep the cache incrementally consistent without re-reading the whole HealthKit store.

### Unified read path

- `UnifiedWorkout` (in `VitalStride/Sources/Models/`) is a thin enum-based wrapper. UI code reads through it without caring whether a row is a SwiftData `Workout` or a `HKWorkout`-derived view model.

## Consequences

### Positive
- Each store is good at the job it has.
- HealthKit L2 cache makes the app responsive offline and dramatically reduces repeated queries.
- Privacy boundary is mechanical: HealthKit values never leak into the SwiftData "app-owned" container (they live in the separate `HealthCacheEntry` rows, never the workout records themselves).
- Clear test surface: `HealthKitServiceTests`, `HealthDataCacheTests`, `VitalModelsTests` each test a layer.

### Negative
- Two stores → two migration paths. SwiftData schema changes and HealthKit-anchor invalidation are separate concerns.
- Reading "all the data I've seen" requires the unified layer; ad-hoc code that forgets the wrapper will only see half the truth.
- The L1/L2/source three-layer cache for HealthKit needs careful invalidation (anchor + memory both).

### Trade-offs we accepted
- No CloudKit sync for training data (yet). User who switches devices loses their workouts. Acceptable for single-user solo dev phase, must be revisited before broader use.
- No write-back to HealthKit for training. Recording a workout in VitalStride does **not** push an `HKWorkout` to Health. Considered, deferred to a later iteration.

## Implementation references

- `Packages/VitalModels/Sources/VitalModels/Models/HealthCacheEntry.swift`
- `Packages/HealthKitService/Sources/HealthKitService/HealthDataCache.swift`
- `Packages/HealthKitService/Sources/HealthKitService/HealthKitService.swift`
- `VitalStride/Sources/Models/UnifiedWorkout.swift`
- `Packages/HealthKitService/Tests/HealthKitServiceTests/HealthDataCacheTests.swift`

## Revisit triggers

- Cross-device sync becomes a product requirement → re-evaluate CloudKit on the training store.
- HealthKit query budget becomes a bottleneck → re-evaluate L1/L2 ratios.
- Users ask for "VitalStride workouts in Apple Health" → consider HK write-back path.
