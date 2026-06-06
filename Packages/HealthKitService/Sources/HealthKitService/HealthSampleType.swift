import Foundation

public enum HealthSampleType: String, Codable, CaseIterable, Sendable {
    case heartRate
    case stepCount
    case bodyMass
    case sleepAnalysis
    case activeEnergyBurned
}
