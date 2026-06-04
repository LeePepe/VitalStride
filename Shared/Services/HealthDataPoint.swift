import Foundation

struct HealthDataPoint: Sendable, Identifiable {
    let id: UUID
    let sampleType: HealthSampleType
    let startDate: Date
    let endDate: Date
    let value: Double
    let unit: String
    let sleepStage: SleepStage?
    let sourceName: String?
}

enum SleepStage: String, Sendable, Codable, CaseIterable {
    case inBed
    case asleepUnspecified
    case asleepCore
    case asleepDeep
    case asleepREM
    case awake
}

enum HealthKitServiceError: Error, Sendable {
    case healthDataNotAvailable
    case authorizationNotDetermined
    case queryFailed(underlying: any Error)
}
