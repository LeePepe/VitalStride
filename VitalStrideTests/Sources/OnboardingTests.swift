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
    @Test("OnboardingView permission scope includes workoutType in shareTypes on iOS")
    func shareTypesIncludeWorkout() {
        let shareTypes = OnboardingView.shareTypes
        #if os(iOS)
        #expect(shareTypes.count == 1)
        #expect(shareTypes.contains(.workoutType()))
        #else
        #expect(shareTypes.isEmpty)
        #endif
    }

    @MainActor
    @Test("OnboardingView permission scope reads all required health types")
    func readTypesIncludeAllHealthData() {
        let readTypes = OnboardingView.readTypes
        #expect(readTypes.count == 24)
        #expect(readTypes.contains(HKObjectType.workoutType()))
        #expect(readTypes.contains(HKObjectType.quantityType(forIdentifier: .heartRate)!))
        #expect(readTypes.contains(HKObjectType.quantityType(forIdentifier: .stepCount)!))
        #expect(readTypes.contains(HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!))
        #expect(readTypes.contains(HKObjectType.quantityType(forIdentifier: .bodyMass)!))
        #expect(readTypes.contains(HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!))
        #expect(readTypes.contains(HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!))
        #expect(readTypes.contains(HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!))
        #expect(readTypes.contains(HKObjectType.quantityType(forIdentifier: .distanceCycling)!))
        #expect(readTypes.contains(HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!))
        #expect(readTypes.contains(HKObjectType.quantityType(forIdentifier: .appleStandTime)!))
        #expect(readTypes.contains(HKObjectType.quantityType(forIdentifier: .flightsClimbed)!))
        #expect(readTypes.contains(HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!))
        #expect(readTypes.contains(HKObjectType.quantityType(forIdentifier: .leanBodyMass)!))
        #expect(readTypes.contains(HKObjectType.quantityType(forIdentifier: .height)!))
        #expect(readTypes.contains(HKObjectType.quantityType(forIdentifier: .bodyMassIndex)!))
        #expect(readTypes.contains(HKObjectType.quantityType(forIdentifier: .restingHeartRate)!))
        #expect(readTypes.contains(HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!))
        #expect(readTypes.contains(HKObjectType.quantityType(forIdentifier: .vo2Max)!))
        #expect(readTypes.contains(HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!))
        #expect(readTypes.contains(HKObjectType.quantityType(forIdentifier: .dietaryProtein)!))
        #expect(readTypes.contains(HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)!))
        #expect(readTypes.contains(HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)!))
        #expect(readTypes.contains(HKObjectType.quantityType(forIdentifier: .dietaryWater)!))
    }
}
