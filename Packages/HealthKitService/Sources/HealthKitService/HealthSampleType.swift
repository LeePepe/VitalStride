import Foundation

public enum HealthSampleType: String, Codable, CaseIterable, Sendable {
    case heartRate
    case stepCount
    case bodyMass
    case sleepAnalysis
    case activeEnergyBurned

    // Activity
    case basalEnergyBurned
    case distanceWalkingRunning
    case distanceCycling
    case appleExerciseTime
    case appleStandTime
    case flightsClimbed

    // Body
    case bodyFatPercentage
    case leanBodyMass
    case height
    case bodyMassIndex

    // Heart
    case restingHeartRate
    case heartRateVariabilitySDNN
    case vo2Max

    // Nutrition
    case dietaryEnergyConsumed
    case dietaryProtein
    case dietaryCarbohydrates
    case dietaryFatTotal
    case dietaryWater
}
