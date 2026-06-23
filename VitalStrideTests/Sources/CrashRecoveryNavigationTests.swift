import Foundation
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

/// Tests the navigation + resolution contracts that `CrashRecoveryModifier`
/// relies on. The modifier itself is a `ViewModifier` (no host without a
/// running SwiftUI environment), so we exercise the same service entry
/// points the modifier calls and verify the side-effects on
/// `AppNavigation` and the SwiftData `ModelContext` directly.
@Suite("Crash recovery — navigation + resolution contracts")
@MainActor
struct CrashRecoveryNavigationTests {

    // MARK: - Navigation handoff

    /// The "Resume" choice must hand the workout to `AppNavigation` and
    /// flip the tab to `.workout` so `WorkoutListView` can pick it up.
    @Test("Resume choice writes crashRecoveryResume + switches tab to .workout")
    func resumeHandsWorkoutToNavigation() throws {
        let navigation = AppNavigation()
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let workout = makeOrphan(in: context)

        #expect(navigation.crashRecoveryResume == nil)
        #expect(navigation.selectedTab != .workout)

        // Same two-line action the modifier's handleResume() performs.
        navigation.crashRecoveryResume = workout
        navigation.selectedTab = .workout

        #expect(navigation.crashRecoveryResume?.persistentModelID == workout.persistentModelID)
        #expect(navigation.selectedTab == .workout)
    }

    @Test("Clearing crashRecoveryResume after consumption returns navigation to a clean state")
    func consumerClearsResume() throws {
        let navigation = AppNavigation()
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let workout = makeOrphan(in: context)

        navigation.crashRecoveryResume = workout
        navigation.selectedTab = .workout

        navigation.crashRecoveryResume = nil

        #expect(navigation.crashRecoveryResume == nil)
        #expect(navigation.selectedTab == .workout)
    }

    // MARK: - Save & End

    /// "Save & End" must mark the workout finished AND persist. On success
    /// the workout disappears from the orphan query (because endDate is now
    /// set) and the caller receives `.success`.
    @Test("saveAndEnd marks workout finished and removes it from orphan query on success")
    func saveAndEndSucceeds() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let workout = makeOrphan(in: context)
        try context.save()

        #expect(CrashRecoveryService.findOrphans(in: context).count == 1)

        let outcome = CrashRecoveryService.saveAndEnd(workout: workout, context: context)

        #expect(outcome == .success)
        #expect(workout.endDate != nil)
        #expect(CrashRecoveryService.findOrphans(in: context).isEmpty)
    }

    /// When persistence fails the caller must learn so it can surface a
    /// retry prompt. The workout's `endDate` mutation in memory is kept so
    /// the retry has the right state to re-attempt; the user-facing surface
    /// is responsible for either retrying or leaving the orphan to be
    /// detected again on the next launch.
    @Test("saveAndEnd reports persistFailed when context.save throws")
    func saveAndEndReportsPersistFailure() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let workout = makeOrphan(in: context)
        try context.save()

        let outcome = CrashRecoveryService.saveAndEnd(
            workout: workout,
            context: context,
            save: { throw TestError.injected }
        )

        #expect(outcome == .persistFailed)
    }

    // MARK: - Discard

    /// "Discard" must delete the workout AND persist. On success the orphan
    /// query is empty.
    @Test("discard removes the workout from the store on success")
    func discardSucceeds() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let workout = makeOrphan(in: context)
        try context.save()

        #expect(CrashRecoveryService.findOrphans(in: context).count == 1)

        let outcome = CrashRecoveryService.discard(workout: workout, context: context)

        #expect(outcome == .success)
        #expect(CrashRecoveryService.findOrphans(in: context).isEmpty)
    }

    /// On persist failure the discard MUST be rolled back so the workout
    /// remains visible to the orphan query. Otherwise the user would be
    /// left with a half-deleted workout that's gone from history but still
    /// occupies the store row, defeating the whole crash-recovery purpose.
    @Test("discard rolls back when persist fails so the workout remains discoverable")
    func discardRollsBackOnPersistFailure() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let workout = makeOrphan(in: context)
        try context.save()

        let outcome = CrashRecoveryService.discard(
            workout: workout,
            context: context,
            save: { throw TestError.injected }
        )

        #expect(outcome == .persistFailed)
        // After rollback the workout should still be findable as an orphan.
        #expect(CrashRecoveryService.findOrphans(in: context).count == 1)
    }

    // MARK: - Helpers

    private func makeOrphan(
        in context: ModelContext,
        startedSecondsAgo: TimeInterval = 1800
    ) -> Workout {
        let workout = Workout(
            type: .strength,
            startDate: Date().addingTimeInterval(-startedSecondsAgo),
            endDate: nil,
            source: .recorded
        )
        context.insert(workout)
        return workout
    }

    private enum TestError: Error {
        case injected
    }
}
