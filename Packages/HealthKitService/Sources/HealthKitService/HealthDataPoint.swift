import Foundation

public struct HealthDataPoint: Sendable, Identifiable, Codable {
    public let id: UUID
    public let sampleType: HealthSampleType
    public let startDate: Date
    public let endDate: Date
    public let value: Double
    public let unit: String
    public let sleepStage: SleepStage?
    public let sourceName: String?

    public init(
        id: UUID,
        sampleType: HealthSampleType,
        startDate: Date,
        endDate: Date,
        value: Double,
        unit: String,
        sleepStage: SleepStage?,
        sourceName: String?
    ) {
        self.id = id
        self.sampleType = sampleType
        self.startDate = startDate
        self.endDate = endDate
        self.value = value
        self.unit = unit
        self.sleepStage = sleepStage
        self.sourceName = sourceName
    }
}

public enum SleepStage: String, Sendable, Codable, CaseIterable {
    case inBed
    case asleepUnspecified
    case asleepCore
    case asleepDeep
    case asleepREM
    case awake
}

public struct HealthFetchResult: Sendable {
    public let dataPoints: [HealthDataPoint]
    public let deletedObjectIDs: [UUID]

    public init(dataPoints: [HealthDataPoint], deletedObjectIDs: [UUID]) {
        self.dataPoints = dataPoints
        self.deletedObjectIDs = deletedObjectIDs
    }
}

public enum HealthKitServiceError: Error, Sendable {
    case healthDataNotAvailable
    case authorizationNotDetermined
    case queryFailed(underlying: any Error)
    case deleteFailed(underlying: any Error)
}
