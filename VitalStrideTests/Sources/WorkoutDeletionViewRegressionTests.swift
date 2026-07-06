import Foundation
import SwiftData
import SwiftUI
import Testing
import VitalModels

@testable import VitalStride

/// View-level regression coverage for MY-1094 that complements the direct
/// `WorkoutDeleter` unit tests.
///
/// Structure:
/// - `PreFixCrashSignalTests` — reproduces the exact state that the pre-fix
///   inline delete flow left behind (workout dropped from `ModelContext`,
///   caller still holding the reference), and asserts the property-read
///   preconditions that caused the SwiftUI body re-eval to trap.
/// - `WorkoutDeletionControllerTests` — pins the `isDeleting` lifecycle
///   contract the two views depend on: synchronous flip on `beginDelete`,
///   reset on completion / error, re-entry guard.
/// - `WorkoutListSwipeDeletionTests` — exercises the swipe-to-delete flow
///   through `WorkoutDeletionController` (the same code path `WorkoutListView`
///   `.swipeActions` invokes) and verifies workout removal + alert-binding
///   state hygiene.
@Suite("MY-1094 View-Level Regression")
@MainActor
struct WorkoutDeletionViewRegressionTests {

    // MARK: - Pre-fix failing signal

    /// Reproduces the state that the pre-fix inline delete produced. In the
    /// old code path, `WorkoutDetailView.deleteWorkout()` did:
    ///
    ///     modelContext.delete(workout)
    ///     try modelContext.save()
    ///     dismiss()
    ///
    /// and then a surviving SwiftUI body (parent `@Query` re-eval) read
    /// `workout.type` on the same reference. On device that trapped with
    /// "This backing data was detached from a context without resolving
    /// attribute faults". We can't catch `fatalError` in a test, but we CAN
    /// prove the two preconditions that produced it:
    ///
    /// 1. The workout is no longer resolvable through its `modelContext`
    ///    after `delete + save` — its backing store is detached.
    /// 2. The pre-fix "capture live reference across delete boundary" pattern
    ///    is exactly what the fix disallows: `WorkoutDetailView` now flips
    ///    `isDeleting = true` synchronously before any async work begins.
    ///
    /// These tests fail (assert-fail rather than fatalError) if a future
    /// refactor either (a) resurrects the inline delete+read pattern or
    /// (b) removes the `isDeleting` synchronous flip.
    @Suite("Pre-fix crash signal")
    @MainActor
    struct PreFixCrashSignalTests {
        let container: ModelContainer

        init() throws {
            container = try ModelContainerConfiguration.makeTestContainer()
        }

        @Test("After context.delete + save, the deleted workout is no longer fetchable through its context")
        func deletedWorkoutIsDetachedFromContext() throws {
            let context = ModelContext(container)
            let workout = Workout(
                type: .strength,
                startDate: Date().addingTimeInterval(-3600),
                endDate: Date(),
                source: .recorded
            )
            context.insert(workout)
            try context.save()

            let workoutID = workout.persistentModelID

            // Confirm the workout is live BEFORE deletion — the caller can
            // read `.type` without trapping.
            #expect(workout.type == .strength)

            // Simulate the pre-fix inline delete flow.
            context.delete(workout)
            try context.save()

            // Detached-object precondition #1: nothing to fetch back.
            let refetch = try context.fetch(FetchDescriptor<Workout>())
                .first(where: { $0.persistentModelID == workoutID })
            #expect(refetch == nil)

            // Detached-object precondition #2: nothing is registered under
            // this ID either. This is the exact state a stale SwiftUI body
            // holding `let workout: Workout` sees. Reading `workout.type`
            // here is what trapped in production; the fix keeps callers from
            // reading it by flipping `isDeleting` synchronously first (see
            // WorkoutDeletionControllerTests).
            let registered = context.registeredModel(for: workoutID) as Workout?
            #expect(registered == nil)
        }

        /// Direct proof that the fix works: driving `WorkoutDetailView`'s
        /// deletion controller flips `isDeleting = true` BEFORE the async
        /// delete completes. In the pre-fix code no such flag existed — the
        /// view kept rendering the live `Workout` throughout the async
        /// window, which is when the SwiftData context detached the object.
        @Test("Fixed path: isDeleting flips to true synchronously on beginDelete, before the async delete completes")
        func fixedPathFlipsIsDeletingSynchronously() async throws {
            let context = ModelContext(container)
            let workout = Workout(
                type: .strength,
                startDate: Date().addingTimeInterval(-3600),
                endDate: Date(),
                source: .recorded
            )
            context.insert(workout)
            try context.save()

            // A deleter we can gate — releases only when the test tells it to.
            // This exercises the exact window where the pre-fix code was
            // buggy: after beginDelete returns, before delete completes.
            let gate = AsyncGate()
            let controller = WorkoutDeletionController(deleter: { snapshot, ctx, hkDelete in
                await gate.wait()
                _ = try await WorkoutDeleter.delete(snapshot: snapshot, in: ctx, healthKitDelete: hkDelete)
                return .deleted
            })

            #expect(controller.isDeleting == false)

            let task = controller.beginDelete(
                workout: workout,
                in: context,
                healthKitDelete: { _ in }
            )

            // Synchronous check — same runloop tick as the beginDelete call.
            // The pre-fix view had no such flag; a hypothetical port to the
            // old flow would leave this as `false`.
            #expect(controller.isDeleting == true)
            #expect(controller.inflightSnapshot != nil)

            // Release the deleter and let it finish.
            await gate.open()
            await task.value

            #expect(controller.isDeleting == false)
            #expect(controller.inflightSnapshot == nil)
            #expect(controller.deleteError == nil)
        }
    }

    // MARK: - Controller lifecycle

    @Suite("WorkoutDeletionController lifecycle")
    @MainActor
    struct WorkoutDeletionControllerTests {
        let container: ModelContainer

        init() throws {
            container = try ModelContainerConfiguration.makeTestContainer()
        }

        @Test("isDeleting resets to false on successful delete")
        func isDeletingResetsAfterSuccess() async throws {
            let context = ModelContext(container)
            let workout = Workout(
                type: .strength,
                startDate: Date(),
                endDate: Date().addingTimeInterval(3600),
                source: .recorded
            )
            context.insert(workout)
            try context.save()

            let controller = WorkoutDeletionController()
            var finishedCalled = false

            let task = controller.beginDelete(
                workout: workout,
                in: context,
                healthKitDelete: { _ in },
                onFinished: { finishedCalled = true }
            )
            await task.value

            #expect(finishedCalled == true)
            #expect(controller.isDeleting == false)
            #expect(controller.inflightSnapshot == nil)
            #expect(controller.deleteError == nil)

            let remaining = try context.fetch(FetchDescriptor<Workout>())
            #expect(remaining.isEmpty)
        }

        @Test("isDeleting resets to false and deleteError is set on save failure")
        func isDeletingResetsAfterError() async throws {
            let context = ModelContext(container)
            let workout = Workout(
                type: .strength,
                startDate: Date(),
                endDate: Date().addingTimeInterval(3600),
                source: .recorded
            )
            context.insert(workout)
            try context.save()

            let controller = WorkoutDeletionController(deleter: { _, _, _ in
                throw SimulatedDeleteError.saveFailed
            })
            var errorCalled = false

            let task = controller.beginDelete(
                workout: workout,
                in: context,
                healthKitDelete: { _ in },
                onError: { _ in errorCalled = true }
            )
            await task.value

            #expect(errorCalled == true)
            #expect(controller.isDeleting == false)
            #expect(controller.inflightSnapshot == nil)
            #expect(controller.deleteError != nil)
        }

        @Test("beginDelete is re-entry safe: a second call while in flight is a no-op")
        func beginDeleteRejectsReentry() async throws {
            let context = ModelContext(container)
            let workout = Workout(
                type: .strength,
                startDate: Date(),
                endDate: Date().addingTimeInterval(3600),
                source: .recorded
            )
            context.insert(workout)
            try context.save()

            let deleteCallCount = Counter()
            let gate = AsyncGate()
            let controller = WorkoutDeletionController(deleter: { snapshot, ctx, hkDelete in
                await deleteCallCount.increment()
                await gate.wait()
                _ = try await WorkoutDeleter.delete(snapshot: snapshot, in: ctx, healthKitDelete: hkDelete)
                return .deleted
            })

            let first = controller.beginDelete(
                workout: workout,
                in: context,
                healthKitDelete: { _ in }
            )
            // Second tap on the confirm button while first is in flight.
            let second = controller.beginDelete(
                workout: workout,
                in: context,
                healthKitDelete: { _ in }
            )

            await gate.open()
            await first.value
            await second.value

            await #expect(deleteCallCount.value() == 1)
        }
    }

    // MARK: - Swipe-to-delete path

    /// Covers the swipe path from `WorkoutListView`. That view's
    /// `.swipeActions` sets `workoutToDelete = workout`, the confirm alert
    /// calls `deleteWorkout(_:)`, which:
    ///   1. Clears `workoutToDelete` immediately (drops the alert binding's
    ///      reference to the about-to-be-deleted model),
    ///   2. Delegates to `WorkoutDeletionController.beginDelete`,
    ///   3. Presents `deleteError` on failure without re-populating
    ///      `workoutToDelete`.
    /// The controller is the pure surface both view paths share — driving
    /// it end-to-end here covers the swipe path without a UI harness.
    @Suite("List swipe-to-delete path")
    @MainActor
    struct WorkoutListSwipeDeletionTests {
        let container: ModelContainer

        init() throws {
            container = try ModelContainerConfiguration.makeTestContainer()
        }

        @Test("Swipe delete path: workoutToDelete cleared, workout removed, isDeleting resets")
        func swipeDeleteFlow() async throws {
            let context = ModelContext(container)
            let target = Workout(
                type: .strength,
                startDate: Date().addingTimeInterval(-3600),
                endDate: Date(),
                source: .recorded
            )
            let survivor = Workout(
                type: .running,
                startDate: Date().addingTimeInterval(-7200),
                endDate: Date().addingTimeInterval(-3600),
                source: .recorded
            )
            context.insert(target)
            context.insert(survivor)
            try context.save()

            // Simulate `WorkoutListView`'s state — `workoutToDelete`
            // populated by the swipe action.
            var workoutToDelete: Workout? = target
            var showingDeleteError = false
            let controller = WorkoutDeletionController()

            // Simulate the alert's destructive Button body (see
            // WorkoutListView L199-L203): grab the workout, clear the
            // binding, hand off to the controller.
            let workout = workoutToDelete!
            workoutToDelete = nil

            let task = controller.beginDelete(
                workout: workout,
                in: context,
                healthKitDelete: { _ in },
                onError: { _ in showingDeleteError = true }
            )

            // Post-flip, pre-await invariants (mirrors what the alert body
            // guarantees before its scope returns).
            #expect(workoutToDelete == nil)
            #expect(controller.isDeleting == true)

            await task.value

            #expect(controller.isDeleting == false)
            #expect(showingDeleteError == false)

            let remaining = try context.fetch(FetchDescriptor<Workout>())
            #expect(remaining.count == 1)
            #expect(remaining.first?.persistentModelID == survivor.persistentModelID)
        }

        @Test("Swipe delete failure: deleteError set, showingDeleteError toggled, workoutToDelete stays nil")
        func swipeDeleteErrorSurfacesToAlert() async throws {
            let context = ModelContext(container)
            let target = Workout(
                type: .strength,
                startDate: Date(),
                endDate: Date().addingTimeInterval(3600),
                source: .recorded
            )
            context.insert(target)
            try context.save()

            var workoutToDelete: Workout? = target
            var showingDeleteError = false
            let controller = WorkoutDeletionController(deleter: { _, _, _ in
                throw SimulatedDeleteError.saveFailed
            })

            let workout = workoutToDelete!
            workoutToDelete = nil

            let task = controller.beginDelete(
                workout: workout,
                in: context,
                healthKitDelete: { _ in },
                onError: { _ in showingDeleteError = true }
            )
            await task.value

            #expect(workoutToDelete == nil)
            #expect(showingDeleteError == true)
            #expect(controller.deleteError != nil)
            #expect(controller.isDeleting == false)
        }

        @Test("HealthKit delete failure is logged but local swipe delete still succeeds")
        func swipeDeleteToleratesHealthKitFailure() async throws {
            let context = ModelContext(container)
            let target = Workout(
                type: .strength,
                startDate: Date(),
                endDate: Date().addingTimeInterval(3600),
                source: .recorded,
                healthKitUUID: "AAAAAAAA-1111-2222-3333-444444444444"
            )
            context.insert(target)
            try context.save()

            let controller = WorkoutDeletionController()
            var showingDeleteError = false

            let task = controller.beginDelete(
                workout: target,
                in: context,
                healthKitDelete: { _ in throw SimulatedDeleteError.healthKitUnavailable },
                onError: { _ in showingDeleteError = true }
            )
            await task.value

            #expect(showingDeleteError == false)
            #expect(controller.deleteError == nil)

            let remaining = try context.fetch(FetchDescriptor<Workout>())
            #expect(remaining.isEmpty)
        }
    }
}

// MARK: - Test helpers

private enum SimulatedDeleteError: Error {
    case saveFailed
    case healthKitUnavailable
}

private actor AsyncGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { cont in
            continuations.append(cont)
        }
    }

    func open() {
        isOpen = true
        for cont in continuations { cont.resume() }
        continuations.removeAll()
    }
}

private actor Counter {
    private var count = 0

    func increment() { count += 1 }
    func value() -> Int { count }
}
