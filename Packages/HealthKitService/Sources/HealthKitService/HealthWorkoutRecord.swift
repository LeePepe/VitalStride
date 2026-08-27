import Foundation
import HealthKit

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

/// Coarse category of the device that authored a workout sample. Derived from
/// `HKSourceRevision.productType` by prefix, so a single enum is stable across
/// specific model identifiers (iPhone12,1 / Watch5,2 / etc.).
public enum SourceDeviceKind: String, Sendable, Codable, CaseIterable {
    case appleWatch
    case iPhone
    case iPad
    case mac
    case other

    /// Map a raw `HKSourceRevision.productType` string to a coarse device kind.
    /// Returns `nil` for a `nil` input; unknown / non-matching strings map to
    /// `.other` (so they're still classified as "some Apple device").
    public static func from(productType: String?) -> SourceDeviceKind? {
        guard let productType, !productType.isEmpty else { return nil }
        if productType.hasPrefix("Watch") { return .appleWatch }
        if productType.hasPrefix("iPhone") { return .iPhone }
        if productType.hasPrefix("iPad") { return .iPad }
        if productType.hasPrefix("Mac") { return .mac }
        return .other
    }
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
    /// Average heart rate (bpm) computed over the workout window via
    /// `HKStatisticsQuery.discreteAverage`. `nil` if no samples or query failed.
    public let averageHeartRate: Int?
    /// Coarse source device kind. `nil` when unknown.
    public let sourceDeviceKind: SourceDeviceKind?
    /// True when `HKMetadataKeyWasUserEntered == true`; false otherwise.
    public let isUserEntered: Bool

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
        sourceName: String?,
        averageHeartRate: Int? = nil,
        sourceDeviceKind: SourceDeviceKind? = nil,
        isUserEntered: Bool = false
    ) {
        self.id = id
        self.activityTypeRawValue = activityTypeRawValue
        self.duration = duration
        self.totalEnergyBurned = totalEnergyBurned
        self.totalDistance = totalDistance
        self.startDate = startDate
        self.endDate = endDate
        self.sourceName = sourceName
        self.averageHeartRate = averageHeartRate
        self.sourceDeviceKind = sourceDeviceKind
        self.isUserEntered = isUserEntered
    }

    // MARK: - Codable (backward-compatible)

    private enum CodingKeys: String, CodingKey {
        case id
        case activityTypeRawValue
        case duration
        case totalEnergyBurned
        case totalDistance
        case startDate
        case endDate
        case sourceName
        case averageHeartRate
        case sourceDeviceKind
        case isUserEntered
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.activityTypeRawValue = try container.decode(UInt.self, forKey: .activityTypeRawValue)
        self.duration = try container.decode(TimeInterval.self, forKey: .duration)
        self.totalEnergyBurned = try container.decodeIfPresent(Double.self, forKey: .totalEnergyBurned)
        self.totalDistance = try container.decodeIfPresent(Double.self, forKey: .totalDistance)
        self.startDate = try container.decode(Date.self, forKey: .startDate)
        self.endDate = try container.decode(Date.self, forKey: .endDate)
        self.sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName)
        // Backward-compat: older cached payloads pre-date these three fields.
        self.averageHeartRate = try container.decodeIfPresent(Int.self, forKey: .averageHeartRate)
        self.sourceDeviceKind = try container.decodeIfPresent(SourceDeviceKind.self, forKey: .sourceDeviceKind)
        self.isUserEntered = try container.decodeIfPresent(Bool.self, forKey: .isUserEntered) ?? false
    }
}

public enum WorkoutAnchorSource: String, Sendable, Codable, Equatable {
    case baselineSnapshot
    case anchoredChanges
    case explicitRangeSnapshot
}

public struct WorkoutAnchorCheckpoint: Sendable, Codable, Equatable {
    public let source: WorkoutAnchorSource
    public let lastSyncDate: Date
    let anchorData: Data

    public init(source: WorkoutAnchorSource, anchor: HKQueryAnchor, lastSyncDate: Date = Date()) {
        self.source = source
        self.lastSyncDate = lastSyncDate
        self.anchorData = (try? NSKeyedArchiver.archivedData(
            withRootObject: anchor,
            requiringSecureCoding: true
        )) ?? Data()
    }

    var anchor: HKQueryAnchor? {
        guard !anchorData.isEmpty else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: HKQueryAnchor.self,
            from: anchorData
        )
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case lastSyncDate
        case anchorData
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.source = try container.decode(WorkoutAnchorSource.self, forKey: .source)
        self.lastSyncDate = try container.decode(Date.self, forKey: .lastSyncDate)
        self.anchorData = try container.decode(Data.self, forKey: .anchorData)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(lastSyncDate, forKey: .lastSyncDate)
        try container.encode(anchorData, forKey: .anchorData)
    }
}

public struct PreparedWorkoutFetch: Sendable, Equatable {
    public let workouts: [HealthWorkoutRecord]
    public let deletedObjectIDs: [UUID]
    public let source: WorkoutAnchorSource
    public let coverage: DateInterval?
    public let checkpoint: WorkoutAnchorCheckpoint?

    public init(
        workouts: [HealthWorkoutRecord],
        deletedObjectIDs: [UUID],
        source: WorkoutAnchorSource,
        coverage: DateInterval? = nil,
        checkpoint: WorkoutAnchorCheckpoint?
    ) {
        self.workouts = workouts
        self.deletedObjectIDs = deletedObjectIDs
        self.source = source
        self.coverage = coverage
        self.checkpoint = checkpoint
    }
}

public struct WorkoutFetchResult: Sendable {
    public let workouts: [HealthWorkoutRecord]
    public let deletedObjectIDs: [UUID]
    public let coverage: DateInterval?

    public init(workouts: [HealthWorkoutRecord], deletedObjectIDs: [UUID], coverage: DateInterval? = nil) {
        self.workouts = workouts
        self.deletedObjectIDs = deletedObjectIDs
        self.coverage = coverage
    }
}

// MARK: - Metadata helpers (pure, testable without HKObject)

/// Pure helper: extracts `HKMetadataKeyWasUserEntered` from a metadata dict.
/// Kept separate so it's unit-testable without instantiating an `HKObject`.
///
/// - Parameter metadata: The raw metadata dictionary from `HKObject.metadata`.
/// - Returns: `true` when the key is present and set to `true`; `false` otherwise.
public func healthWorkoutIsUserEntered(metadata: [String: Any]?) -> Bool {
    guard let metadata else { return false }
    // HKMetadataKeyWasUserEntered = "HKWasUserEntered"; we hardcode the string
    // so this helper doesn't have to import HealthKit (keeps it testable on
    // platforms where HealthKit tests would otherwise pull in the framework).
    if let raw = metadata["HKWasUserEntered"] {
        if let b = raw as? Bool { return b }
        if let n = raw as? NSNumber { return n.boolValue }
    }
    return false
}
