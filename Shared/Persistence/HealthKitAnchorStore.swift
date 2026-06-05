import Foundation

struct AnchorRecord: Codable {
    let anchorData: Data
    let lastSyncDate: Date
}

final class HealthKitAnchorStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let keyPrefix: String

    init(defaults: UserDefaults = .standard, keyPrefix: String = "healthkit_anchor") {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    func anchor(for sampleType: HealthSampleType, deviceIdentifier: String) -> AnchorRecord? {
        let key = storageKey(sampleType: sampleType, deviceIdentifier: deviceIdentifier)
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AnchorRecord.self, from: data)
    }

    func setAnchor(_ record: AnchorRecord, for sampleType: HealthSampleType, deviceIdentifier: String) {
        let key = storageKey(sampleType: sampleType, deviceIdentifier: deviceIdentifier)
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: key)
    }

    func removeAnchor(for sampleType: HealthSampleType, deviceIdentifier: String) {
        let key = storageKey(sampleType: sampleType, deviceIdentifier: deviceIdentifier)
        defaults.removeObject(forKey: key)
    }

    func removeAllAnchors(for deviceIdentifier: String) {
        for sampleType in HealthSampleType.allCases {
            removeAnchor(for: sampleType, deviceIdentifier: deviceIdentifier)
        }
    }

    private func storageKey(sampleType: HealthSampleType, deviceIdentifier: String) -> String {
        "\(keyPrefix)_\(sampleType.rawValue)_\(deviceIdentifier)"
    }
}
