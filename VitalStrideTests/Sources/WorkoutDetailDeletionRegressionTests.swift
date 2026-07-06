import Foundation
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

/// Regression coverage for MY-1094: deleting a workout must not leave a caller
/// holding a reference that will fault on `\Workout.type` (SwiftData backing
/// data detached from context).
///
/// The pre-fix `WorkoutDetailView.deleteWorkout()` inlined
///   modelContext.delete(workout)
///   try modelContext.save()
///   dismiss()
/// then relied on `dismiss()` to unblock the view before the SwiftUI runtime
/// re-evaluated any body that still held a `let workout: Workout` reference. On
/// device this raced: on `source == .recorded`, the parent `@Query` refresh +
/// `RecentWorkoutsSection` body re-read `workout.type` on the detached backing
/// store first and trapped.
///
/// The fix moves deletion through `WorkoutDeleter` + `WorkoutDeletionSnapshot`,
/// so callers no longer keep a `Workout` reference across the delete boundary.
/// These tests exercise the snapshot-driven path and prove no caller code needs
/// to touch the model after `delete(...)` returns.
@Suite("Workout Detail Deletion Regression (MY-1094)")
@MainActor
struct WorkoutDetailDeletionRegressionTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    // MARK: - Snapshot capture

    @Test("Snapshot preserves source + healthKitUUID + persistentModelID")
    func snapshotCarriesEverythingNeeded() throws {
        let context = ModelContext(container)
        let workout = Workout(
            type: .strength,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            source: .recorded,
            healthKitUUID: "AB12CD34-EF56-7890-1234-56789ABCDEF0"
        )
        context.insert(workout)
        try context.save()

        let snapshot = WorkoutDeleter.snapshot(of: workout)

        #expect(snapshot.source == .recorded)
        #expect(snapshot.healthKitUUID == "AB12CD34-EF56-7890-1234-56789ABCDEF0")
        #expect(snapshot.persistentModelID == workout.persistentModelID)
    }

    // MARK: - Regression: detached-object path

    @Test("Deleting source=recorded workout via snapshot does not require touching the model afterwards")
    func deleteRecordedThroughSnapshotStaysSafe() async throws {
        let context = ModelContext(container)
        let workout = Workout(
            type: .strength,
            startDate: Date().addingTimeInterval(-3600),
            endDate: Date(),
            source: .recorded
        )
        context.insert(workout)
        try context.save()
        let snapshotID = workout.persistentModelID

        // Simulate the exact code path from WorkoutDetailView: capture the
        // snapshot, then rely ONLY on the snapshot for the rest of the flow.
        let snapshot = WorkoutDeleter.snapshot(of: workout)
        let outcome = try await WorkoutDeleter.delete(
            snapshot: snapshot,
            in: context,
            healthKitDelete: { _ in }
        )

        #expect(outcome == .deleted)

        // Post-condition: the model is gone from the store; any caller that
        // still holds `workout` MUST NOT read its properties. We verify by
        // fetching by ID (safe) rather than dereferencing the stale reference.
        let remaining = try context.fetch(FetchDescriptor<Workout>())
        #expect(remaining.isEmpty)
        #expect(!remaining.contains { $0.persistentModelID == snapshotID })
    }

    @Test("Deleting source=healthkit workout via snapshot skips HealthKit call")
    func deleteHealthKitSourceThroughSnapshot() async throws {
        let context = ModelContext(container)
        let workout = Workout(
            type: .running,
            startDate: Date().addingTimeInterval(-1800),
            endDate: Date(),
            source: .healthkit,
            healthKitUUID: "11111111-1111-1111-1111-111111111111"
        )
        context.insert(workout)
        try context.save()

        // Track whether the HealthKit delete closure was invoked. For
        // source=healthkit records the app-side delete must ONLY drop the
        // local SwiftData row; the HealthKit sample belongs to another source.
        let hkCallCount = Counter()

        let snapshot = WorkoutDeleter.snapshot(of: workout)
        let outcome = try await WorkoutDeleter.delete(
            snapshot: snapshot,
            in: context,
            healthKitDelete: { _ in
                await hkCallCount.increment()
            }
        )

        #expect(outcome == .deleted)
        await #expect(hkCallCount.value() == 0)

        let remaining = try context.fetch(FetchDescriptor<Workout>())
        #expect(remaining.isEmpty)
    }

    @Test("Deleting source=recorded + healthKitUUID invokes HealthKit delete exactly once")
    func deleteRecordedTriggersHealthKitPath() async throws {
        let context = ModelContext(container)
        let workout = Workout(
            type: .strength,
            startDate: Date().addingTimeInterval(-3600),
            endDate: Date(),
            source: .recorded,
            healthKitUUID: "22222222-2222-2222-2222-222222222222"
        )
        context.insert(workout)
        try context.save()

        let hkCallCount = Counter()

        let snapshot = WorkoutDeleter.snapshot(of: workout)
        _ = try await WorkoutDeleter.delete(
            snapshot: snapshot,
            in: context,
            healthKitDelete: { uuid in
                #expect(uuid == "22222222-2222-2222-2222-222222222222")
                await hkCallCount.increment()
            }
        )

        await #expect(hkCallCount.value() == 1)
    }

    @Test("HealthKit delete failure does not abort local SwiftData delete")
    func healthKitFailureFallsThroughToLocalDelete() async throws {
        let context = ModelContext(container)
        let workout = Workout(
            type: .strength,
            startDate: Date().addingTimeInterval(-3600),
            endDate: Date(),
            source: .recorded,
            healthKitUUID: "33333333-3333-3333-3333-333333333333"
        )
        context.insert(workout)
        try context.save()

        let snapshot = WorkoutDeleter.snapshot(of: workout)
        let outcome = try await WorkoutDeleter.delete(
            snapshot: snapshot,
            in: context,
            healthKitDelete: { _ in throw SimulatedHealthKitError.unavailable }
        )

        #expect(outcome == .deleted)
        let remaining = try context.fetch(FetchDescriptor<Workout>())
        #expect(remaining.isEmpty)
    }

    @Test("Deleting the same snapshot twice reports alreadyGone the second time")
    func doubleDeleteIsIdempotent() async throws {
        let context = ModelContext(container)
        let workout = Workout(
            type: .strength,
            startDate: Date().addingTimeInterval(-1800),
            endDate: Date(),
            source: .recorded
        )
        context.insert(workout)
        try context.save()

        let snapshot = WorkoutDeleter.snapshot(of: workout)
        let firstOutcome = try await WorkoutDeleter.delete(
            snapshot: snapshot,
            in: context,
            healthKitDelete: { _ in }
        )
        let secondOutcome = try await WorkoutDeleter.delete(
            snapshot: snapshot,
            in: context,
            healthKitDelete: { _ in }
        )

        #expect(firstOutcome == .deleted)
        #expect(secondOutcome == .alreadyGone)
    }
}

// MARK: - Test helpers

private enum SimulatedHealthKitError: Error {
    case unavailable
}

private actor Counter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}
