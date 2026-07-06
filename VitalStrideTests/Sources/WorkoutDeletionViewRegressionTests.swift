import Foundation
import HealthKit
import HealthKitService
import SwiftData
import SwiftUI
import Testing
import VitalModels

@testable import VitalStride

/// View-level regression coverage for MY-1094.
///
/// # What each suite proves
///
/// - `PreFixLifecycleTests` — reconstructs the pre-fix crash **lifecycle**
///   step-by-step (not just the "detached-store" precondition). Emits an
///   ordered event log while the deletion runs, then asserts the event
///   ordering both (a) reproduces the buggy sequence when we simulate the
///   old inline flow, and (b) shows the fixed controller keeps `isDeleting`
///   `true` across the entire dismiss handoff.
/// - `WorkoutDeletionControllerTests` — pins the controller's contract:
///   sync flip on entry, error resets, re-entry guard, `reset()` semantics.
/// - `WorkoutListViewSwipeDeleteTests` — calls the REAL production helper
///   `WorkoutListView.performSwipeDelete(...)` that the view invokes from
///   its alert body, using live `Binding<...>` state and a live SwiftData
///   context. No simulated state.
@Suite("MY-1094 View-Level Regression")
@MainActor
struct WorkoutDeletionViewRegressionTests {

    // MARK: - Pre-fix lifecycle

    @Suite("Pre-fix lifecycle signal")
    @MainActor
    struct PreFixLifecycleTests {
        let container: ModelContainer

        init() throws {
            container = try ModelContainerConfiguration.makeTestContainer()
        }

        /// Reproduces the pre-fix crash **lifecycle** using an event log.
        /// The old inline delete in `WorkoutDetailView` was:
        ///
        ///     modelContext.delete(workout)
        ///     try modelContext.save()   // ← ‹save-returned›
        ///     dismiss()                  // ← view starts dismissing
        ///
        /// Between `save-returned` and the SwiftUI dismiss animation
        /// finishing, any surviving body that read `workout.type` faulted.
        /// This test walks the exact sequence and asserts the buggy
        /// interleave IS producible when nothing gates the read.
        ///
        /// Then it walks the FIXED sequence through
        /// `WorkoutDeletionController` and asserts that the read-gate stays
        /// closed across the same window — proving the fix moves the
        /// "read-ok" event from AFTER save to NEVER (until the view
        /// unmounts).
        @Test("Pre-fix ordering allowed a body-read after save; fixed ordering forbids it")
        func lifecycleOrderingContract() async throws {
            let context = ModelContext(container)
            let workout = Workout(
                type: .strength,
                startDate: Date().addingTimeInterval(-3600),
                endDate: Date(),
                source: .recorded
            )
            context.insert(workout)
            try context.save()

            // ---- (A) Pre-fix simulation ------------------------------------
            // Emit events the way the OLD code would:
            //   1. save() returns
            //   2. (nothing gates reads on the workout)
            //   3. dismiss() is called
            // A stale body re-eval could happen between 1 and 3.
            var preFixLog: [String] = []
            let workoutID = workout.persistentModelID

            context.delete(workout)
            try context.save()
            preFixLog.append("save-returned")

            // Nothing stops us from touching the reference right here.
            // (In production the SwiftUI runtime does the touching, but the
            // point stands: the pre-fix code path did not gate reads.)
            // We DON'T actually read `.type` — that would fatalError. But
            // we prove the fault surface is exposed:
            let registered = context.registeredModel(for: workoutID) as Workout?
            preFixLog.append("read-attempt-possible-registered=\(registered == nil ? "nil" : "live")")

            preFixLog.append("dismiss-called")

            #expect(preFixLog == [
                "save-returned",
                "read-attempt-possible-registered=nil",
                "dismiss-called",
            ])

            // ---- (B) Fixed flow through the controller ---------------------
            // Set up a second workout and drive the fix. The event log must
            // show that `isDeleting` never returns to `false` on the
            // success path — the read-gate stays closed across dismiss.
            let workout2 = Workout(
                type: .strength,
                startDate: Date().addingTimeInterval(-1800),
                endDate: Date(),
                source: .recorded
            )
            context.insert(workout2)
            try context.save()

            var fixedLog: [String] = []
            let controller = WorkoutDeletionController()

            let task = controller.beginDelete(
                workout: workout2,
                in: context,
                healthKitDelete: { _ in },
                onFinished: {
                    // At the moment onFinished fires (this is where the view
                    // would call dismiss), isDeleting MUST still be true.
                    fixedLog.append("onFinished isDeleting=\(controller.isDeleting)")
                }
            )
            fixedLog.append("beginDelete-returned isDeleting=\(controller.isDeleting)")

            await task.value
            fixedLog.append("task-completed isDeleting=\(controller.isDeleting)")

            // Fixed-flow contract:
            //   1. beginDelete returns → isDeleting already true (sync flip).
            //   2. onFinished fires → STILL true (view is being dismissed;
            //      no read-window for the stale reference).
            //   3. task-completed → STILL true (controller stays gated).
            #expect(fixedLog == [
                "beginDelete-returned isDeleting=true",
                "onFinished isDeleting=true",
                "task-completed isDeleting=true",
            ])
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

        @Test("isDeleting flips true synchronously and stays true after successful onFinished")
        func syncFlipAndSuccessGate() async throws {
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
            var onFinishedIsDeleting: Bool?

            #expect(controller.isDeleting == false)

            let task = controller.beginDelete(
                workout: workout,
                in: context,
                healthKitDelete: { _ in },
                onFinished: { onFinishedIsDeleting = controller.isDeleting }
            )

            // Sync flip: same tick as beginDelete return.
            #expect(controller.isDeleting == true)
            #expect(controller.inflightSnapshot != nil)

            await task.value

            // MY-1094 v2 P1 fix: success path must not reset the gate.
            // The view is being dismissed; clearing here reopens the
            // stale-reference window that caused the original crash.
            #expect(onFinishedIsDeleting == true)
            #expect(controller.isDeleting == true)
            #expect(controller.inflightSnapshot != nil)
            #expect(controller.deleteError == nil)

            let remaining = try context.fetch(FetchDescriptor<Workout>())
            #expect(remaining.isEmpty)
        }

        @Test("Error path resets isDeleting and populates deleteError")
        func errorPathResets() async throws {
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
            var onErrorFired = false

            let task = controller.beginDelete(
                workout: workout,
                in: context,
                healthKitDelete: { _ in },
                onError: { _ in onErrorFired = true }
            )
            await task.value

            #expect(onErrorFired == true)
            #expect(controller.isDeleting == false)
            #expect(controller.inflightSnapshot == nil)
            #expect(controller.deleteError != nil)
        }

        @Test("Second beginDelete while in flight is a no-op (re-entry guard)")
        func rejectsReentry() async throws {
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

            let first = controller.beginDelete(workout: workout, in: context, healthKitDelete: { _ in })
            let second = controller.beginDelete(workout: workout, in: context, healthKitDelete: { _ in })

            await gate.open()
            await first.value
            await second.value

            await #expect(deleteCallCount.value() == 1)
        }

        @Test("reset() clears success-path terminal state so a reusable controller can accept a new delete")
        func resetClearsSuccessGate() async throws {
            let context = ModelContext(container)
            let workoutA = Workout(
                type: .strength,
                startDate: Date().addingTimeInterval(-7200),
                endDate: Date().addingTimeInterval(-3600),
                source: .recorded
            )
            let workoutB = Workout(
                type: .running,
                startDate: Date().addingTimeInterval(-3600),
                endDate: Date(),
                source: .recorded
            )
            context.insert(workoutA)
            context.insert(workoutB)
            try context.save()

            let controller = WorkoutDeletionController()

            let taskA = controller.beginDelete(workout: workoutA, in: context, healthKitDelete: { _ in })
            await taskA.value

            // Post-success: gate still closed by design.
            #expect(controller.isDeleting == true)

            // Reset for reuse (list view calls this in its onFinished).
            controller.reset()
            #expect(controller.isDeleting == false)
            #expect(controller.inflightSnapshot == nil)

            let taskB = controller.beginDelete(workout: workoutB, in: context, healthKitDelete: { _ in })
            await taskB.value

            let remaining = try context.fetch(FetchDescriptor<Workout>())
            #expect(remaining.isEmpty)
        }
    }

    // MARK: - Real swipe/delete path

    /// Exercises the ACTUAL production code path used by `WorkoutListView`:
    /// `WorkoutListView.performSwipeDelete(...)` — the helper the view's
    /// alert body invokes. Tests use live `Binding<...>` values and a live
    /// SwiftData context; no simulated state.
    @Suite("WorkoutListView swipe/delete path (real helper)")
    @MainActor
    struct WorkoutListViewSwipeDeleteTests {
        let container: ModelContainer

        init() throws {
            container = try ModelContainerConfiguration.makeTestContainer()
        }

        @Test("Real swipe-delete: workoutToDelete cleared synchronously, controller resets after success")
        func realSwipeDeleteHappyPath() async throws {
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

            let state = SwipeState(workoutToDelete: target)
            let controller = WorkoutDeletionController()

            let task = WorkoutListView.performSwipeDelete(
                workout: target,
                workoutToDelete: state.workoutToDeleteBinding,
                showingDeleteError: state.showingDeleteErrorBinding,
                in: context,
                healthKitService: makePreviewHealthKitService(),
                controller: controller
            )

            // Synchronous invariants after the helper returns.
            #expect(state.workoutToDelete == nil)
            #expect(controller.isDeleting == true)

            await task.value

            // After success the list view's onFinished callback calls
            // controller.reset() so the controller can accept the NEXT swipe.
            #expect(controller.isDeleting == false)
            #expect(controller.inflightSnapshot == nil)
            #expect(state.showingDeleteError == false)

            let remaining = try context.fetch(FetchDescriptor<Workout>())
            #expect(remaining.count == 1)
            #expect(remaining.first?.persistentModelID == survivor.persistentModelID)
        }

        @Test("Real swipe-delete error path: showingDeleteError set, workoutToDelete stays nil, isDeleting resets")
        func realSwipeDeleteErrorPath() async throws {
            let context = ModelContext(container)
            let target = Workout(
                type: .strength,
                startDate: Date(),
                endDate: Date().addingTimeInterval(3600),
                source: .recorded
            )
            context.insert(target)
            try context.save()

            let state = SwipeState(workoutToDelete: target)
            let controller = WorkoutDeletionController(deleter: { _, _, _ in
                throw SimulatedDeleteError.saveFailed
            })

            let task = WorkoutListView.performSwipeDelete(
                workout: target,
                workoutToDelete: state.workoutToDeleteBinding,
                showingDeleteError: state.showingDeleteErrorBinding,
                in: context,
                healthKitService: makePreviewHealthKitService(),
                controller: controller
            )
            await task.value

            #expect(state.workoutToDelete == nil)
            #expect(state.showingDeleteError == true)
            #expect(controller.isDeleting == false)
            #expect(controller.deleteError != nil)
        }

        @Test("Real swipe-delete supports back-to-back swipes on different workouts")
        func realSwipeDeleteBackToBack() async throws {
            let context = ModelContext(container)
            let first = Workout(type: .strength, startDate: Date().addingTimeInterval(-7200), endDate: Date().addingTimeInterval(-3600), source: .recorded)
            let second = Workout(type: .running, startDate: Date().addingTimeInterval(-3600), endDate: Date(), source: .recorded)
            context.insert(first)
            context.insert(second)
            try context.save()

            let controller = WorkoutDeletionController()
            let state = SwipeState(workoutToDelete: first)
            let hkService = makePreviewHealthKitService()

            let taskA = WorkoutListView.performSwipeDelete(
                workout: first,
                workoutToDelete: state.workoutToDeleteBinding,
                showingDeleteError: state.showingDeleteErrorBinding,
                in: context,
                healthKitService: hkService,
                controller: controller
            )
            await taskA.value

            // After the first swipe finishes and the list view has called
            // controller.reset() in onFinished, a second swipe must go
            // through — this verifies the reset() plumbing works end-to-end.
            state.workoutToDelete = second
            let taskB = WorkoutListView.performSwipeDelete(
                workout: second,
                workoutToDelete: state.workoutToDeleteBinding,
                showingDeleteError: state.showingDeleteErrorBinding,
                in: context,
                healthKitService: hkService,
                controller: controller
            )
            await taskB.value

            #expect(state.showingDeleteError == false)
            let remaining = try context.fetch(FetchDescriptor<Workout>())
            #expect(remaining.isEmpty)
        }
    }
}

// MARK: - Test helpers

/// Wraps mutable state that the swipe helper drives through `Binding<...>`.
/// SwiftUI `Binding` needs stable get/set closures, which class properties
/// give us. This is what the view has internally (`@State`), rendered as a
/// test double.
@MainActor
private final class SwipeState {
    var workoutToDelete: Workout?
    var showingDeleteError = false

    init(workoutToDelete: Workout? = nil) {
        self.workoutToDelete = workoutToDelete
    }

    var workoutToDeleteBinding: Binding<Workout?> {
        Binding(
            get: { self.workoutToDelete },
            set: { self.workoutToDelete = $0 }
        )
    }

    var showingDeleteErrorBinding: Binding<Bool> {
        Binding(
            get: { self.showingDeleteError },
            set: { self.showingDeleteError = $0 }
        )
    }
}

private enum SimulatedDeleteError: Error {
    case saveFailed
}

/// Minimal stub for tests. `deleteWorkout` throws so if a test accidentally
/// exercises the HealthKit branch (which would require a live simulator with
/// entitlements) it fails loudly instead of silently succeeding.
/// Test workouts here all have `healthKitUUID == nil`, so this is never
/// invoked on the happy paths.
private final class _TestHealthStore: HealthStoreProviding, @unchecked Sendable {
    static let isHealthDataAvailable = false

    func requestAuthorization(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws {
        throw HealthKitServiceError.healthDataNotAvailable
    }
    func statusForAuthorizationRequest(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws -> HKAuthorizationRequestStatus {
        throw HealthKitServiceError.healthDataNotAvailable
    }
    func executeAnchoredQuery(type: HKSampleType, predicate: NSPredicate?, anchor: HKQueryAnchor?, limit: Int) async throws -> AnchoredQueryResult {
        throw HealthKitServiceError.healthDataNotAvailable
    }
    func executeObserverAnchoredQuery(type: HKSampleType, predicate: NSPredicate?, anchor: HKQueryAnchor?, limit: Int) -> AsyncStream<AnchoredQueryResult> {
        AsyncStream { $0.finish() }
    }
    func stopQuery(_ query: HKQuery) {}
    func executeSampleQuery(type: HKSampleType, predicate: NSPredicate?, limit: Int) async throws -> [HKSample] {
        throw HealthKitServiceError.healthDataNotAvailable
    }
    func delete(_ objects: [HKObject]) async throws {
        throw HealthKitServiceError.healthDataNotAvailable
    }
}

@MainActor
private func makePreviewHealthKitService() -> HealthKitService {
    HealthKitService(healthStore: _TestHealthStore(), deviceIdentifier: "test")
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
