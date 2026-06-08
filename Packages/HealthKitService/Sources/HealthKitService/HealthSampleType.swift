import Foundation

public enum HealthSampleType: String, Codable, CaseIterable, Sendable {
    case heartRate
    case stepCount
    case bodyMass
    case sleepAnalysis
    case activeEnergyBurned

    public static let overviewTypes: Set<HealthSampleType> = [
        .stepCount, .heartRate, .sleepAnalysis, .bodyMass
    ]
}
