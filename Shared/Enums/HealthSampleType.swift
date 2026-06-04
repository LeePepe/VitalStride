import Foundation

enum HealthSampleType: String, Codable, CaseIterable {
    case heartRate
    case stepCount
    case bodyMass
    case sleepAnalysis
    case activeEnergyBurned
}
