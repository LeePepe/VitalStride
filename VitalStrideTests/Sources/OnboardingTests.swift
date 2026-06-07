import Foundation
import HealthKit
import Testing

@testable import VitalStride

@Suite("Onboarding Tests")
struct OnboardingTests {
    @Test("hasCompletedOnboarding defaults to false")
    func defaultOnboardingState() {
        let defaults = UserDefaults(suiteName: "OnboardingTests-\(UUID().uuidString)")!
        let value = defaults.bool(forKey: "hasCompletedOnboarding")
        #expect(value == false)
    }

    @Test("hasCompletedOnboarding persists true after completion")
    func onboardingCompletionPersists() {
        let defaults = UserDefaults(suiteName: "OnboardingTests-\(UUID().uuidString)")!
        defaults.set(true, forKey: "hasCompletedOnboarding")
        #expect(defaults.bool(forKey: "hasCompletedOnboarding") == true)
    }

    @MainActor
    @Test("OnboardingView permission scope includes workoutType in shareTypes")
    func shareTypesIncludeWorkout() {
        let shareTypes = OnboardingView.shareTypes
        #expect(shareTypes.count == 1)
        #expect(shareTypes.contains(.workoutType()))
    }

    @MainActor
    @Test("OnboardingView permission scope reads all required health types")
    func readTypesIncludeAllHealthData() {
        let readTypes = OnboardingView.readTypes
        #expect(readTypes.count == 6)
    }
}
