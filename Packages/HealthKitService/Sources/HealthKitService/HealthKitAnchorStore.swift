import Foundation

public struct AnchorRecord: Codable, Sendable {
    public let anchorData: Data
    public let lastSyncDate: Date

    public init(anchorData: Data, lastSyncDate: Date) {
        self.anchorData = anchorData
        self.lastSyncDate = lastSyncDate
    }
}

public final class HealthKitAnchorStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let keyPrefix: String

    public init(defaults: UserDefaults = .standard, keyPrefix: String = "healthkit_anchor") {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    public func anchor(for sampleType: HealthSampleType, deviceIdentifier: String) -> AnchorRecord? {
        let key = storageKey(sampleType: sampleType, deviceIdentifier: deviceIdentifier)
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AnchorRecord.self, from: data)
    }

    public func setAnchor(_ record: AnchorRecord, for sampleType: HealthSampleType, deviceIdentifier: String) {
        let key = storageKey(sampleType: sampleType, deviceIdentifier: deviceIdentifier)
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: key)
    }

    public func removeAnchor(for sampleType: HealthSampleType, deviceIdentifier: String) {
        let key = storageKey(sampleType: sampleType, deviceIdentifier: deviceIdentifier)
        defaults.removeObject(forKey: key)
    }

    public func removeAllAnchors(for deviceIdentifier: String) {
        for sampleType in HealthSampleType.allCases {
            removeAnchor(for: sampleType, deviceIdentifier: deviceIdentifier)
        }
        removeWorkoutAnchor(for: deviceIdentifier)
    }

    // MARK: - Workout Anchors

    private static let workoutAnchorKey = "workout"

    public func workoutAnchor(for deviceIdentifier: String) -> AnchorRecord? {
        let key = workoutStorageKey(deviceIdentifier: deviceIdentifier)
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AnchorRecord.self, from: data)
    }

    public func setWorkoutAnchor(_ record: AnchorRecord, for deviceIdentifier: String) {
        let key = workoutStorageKey(deviceIdentifier: deviceIdentifier)
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: key)
    }

    public func removeWorkoutAnchor(for deviceIdentifier: String) {
        let key = workoutStorageKey(deviceIdentifier: deviceIdentifier)
        defaults.removeObject(forKey: key)
    }

    // MARK: - Private

    private func storageKey(sampleType: HealthSampleType, deviceIdentifier: String) -> String {
        "\(keyPrefix)_\(sampleType.rawValue)_\(deviceIdentifier)"
    }

    private func workoutStorageKey(deviceIdentifier: String) -> String {
        "\(keyPrefix)_\(Self.workoutAnchorKey)_\(deviceIdentifier)"
    }
}
