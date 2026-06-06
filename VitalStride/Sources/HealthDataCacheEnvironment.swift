import HealthKitService
import SwiftUI

private struct HealthDataCacheKey: EnvironmentKey {
    static let defaultValue = HealthDataCache(
        dataProvider: HealthKitService(deviceIdentifier: "ios-display")
    )
}

private struct HealthKitServiceKey: EnvironmentKey {
    static let defaultValue = HealthKitService(deviceIdentifier: "ios-display")
}

extension EnvironmentValues {
    var healthDataCache: HealthDataCache {
        get { self[HealthDataCacheKey.self] }
        set { self[HealthDataCacheKey.self] = newValue }
    }

    var healthKitService: HealthKitService {
        get { self[HealthKitServiceKey.self] }
        set { self[HealthKitServiceKey.self] = newValue }
    }
}
