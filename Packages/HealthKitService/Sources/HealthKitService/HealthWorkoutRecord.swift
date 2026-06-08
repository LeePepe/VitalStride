import Foundation

public enum WorkoutActivityType: UInt, Sendable, Codable, CaseIterable {
    case cycling = 13
    case dance = 14
    case elliptical = 16
    case functionalStrengthTraining = 20
    case hiking = 24
    case rowing = 35
    case running = 37
    case swimming = 46
    case traditionalStrengthTraining = 50
    case walking = 52
    case yoga = 54
    case highIntensityIntervalTraining = 63
    case other = 3000
}

public struct HealthWorkoutRecord: Sendable, Identifiable, Codable, Equatable {
    public let id: UUID
    public let activityTypeRawValue: UInt
    public let duration: TimeInterval
    public let totalEnergyBurned: Double?
    public let totalDistance: Double?
    public let startDate: Date
    public let endDate: Date
    public let sourceName: String?

    public var activityType: WorkoutActivityType {
        WorkoutActivityType(rawValue: activityTypeRawValue) ?? .other
    }

    public init(
        id: UUID,
        activityTypeRawValue: UInt,
        duration: TimeInterval,
        totalEnergyBurned: Double?,
        totalDistance: Double?,
        startDate: Date,
        endDate: Date,
        sourceName: String?
    ) {
        self.id = id
        self.activityTypeRawValue = activityTypeRawValue
        self.duration = duration
        self.totalEnergyBurned = totalEnergyBurned
        self.totalDistance = totalDistance
        self.startDate = startDate
        self.endDate = endDate
        self.sourceName = sourceName
    }
}

public struct WorkoutFetchResult: Sendable {
    public let workouts: [HealthWorkoutRecord]
    public let deletedObjectIDs: [UUID]

    public init(workouts: [HealthWorkoutRecord], deletedObjectIDs: [UUID]) {
        self.workouts = workouts
        self.deletedObjectIDs = deletedObjectIDs
    }
}
