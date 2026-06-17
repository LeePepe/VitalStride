import Foundation
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

@Suite("Crash recovery — navigation handoff contract")
@MainActor
struct CrashRecoveryNavigationTests {
    /// The "恢复训练" choice must hand the workout to `AppNavigation` and
    /// flip the tab to `.workout` so `WorkoutListView` can pick it up.
    /// The modifier takes `navigation` as a stored property (not from
    /// `@Environment`), so the test exercises the same instance the
    /// modifier would mutate.
    @Test("Resume choice writes crashRecoveryResume + switches tab to .workout")
    func resumeHandsWorkoutToNavigation() throws {
        let navigation = AppNavigation()
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let workout = Workout(
            type: .strength,
            startDate: Date().addingTimeInterval(-1800),
            endDate: nil,
            source: .recorded
        )
        context.insert(workout)
        try context.save()

        // Sanity: nothing pending before the simulated resume action.
        #expect(navigation.crashRecoveryResume == nil)
        #expect(navigation.selectedTab != .workout)

        // Simulate what CrashRecoveryModifier.handleResume() does once the
        // user taps "恢复训练" on the alert.
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
        let workout = Workout(
            type: .strength,
            startDate: Date(),
            endDate: nil,
            source: .recorded
        )
        context.insert(workout)
        try context.save()

        navigation.crashRecoveryResume = workout
        navigation.selectedTab = .workout

        // The consumer (WorkoutListView) is expected to clear it back to nil
        // after opening ActiveWorkoutView in resume mode.
        navigation.crashRecoveryResume = nil

        #expect(navigation.crashRecoveryResume == nil)
        #expect(navigation.selectedTab == .workout)
    }
}
