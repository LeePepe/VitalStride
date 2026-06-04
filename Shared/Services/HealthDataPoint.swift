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

struct HealthFetchResult: Sendable {
    let dataPoints: [HealthDataPoint]
    let deletedObjectIDs: [UUID]
}

enum HealthKitServiceError: Error, Sendable {
    case healthDataNotAvailable
    case authorizationNotDetermined
    case queryFailed(underlying: any Error)
}
