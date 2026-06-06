import HealthKit
import HealthKitService
import SwiftUI

private struct _PreviewDataProvider: HealthDataProviding {
    func fetchData(
        for sampleType: HealthSampleType,
        dateRange: DateInterval?
    ) async throws -> HealthFetchResult {
        HealthFetchResult(dataPoints: [], deletedObjectIDs: [])
    }
}

private final class _PreviewHealthStore: HealthStoreProviding, @unchecked Sendable {
    static let isHealthDataAvailable = false

    func requestAuthorization(
        toShare typesToShare: Set<HKSampleType>,
        read typesToRead: Set<HKObjectType>
    ) async throws {
        throw HealthKitServiceError.healthDataNotAvailable
    }

    func statusForAuthorizationRequest(
        toShare typesToShare: Set<HKSampleType>,
        read typesToRead: Set<HKObjectType>
    ) async throws -> HKAuthorizationRequestStatus {
        throw HealthKitServiceError.healthDataNotAvailable
    }

    func executeAnchoredQuery(
        type: HKSampleType,
        predicate: NSPredicate?,
        anchor: HKQueryAnchor?,
        limit: Int
    ) async throws -> AnchoredQueryResult {
        throw HealthKitServiceError.healthDataNotAvailable
    }
}

private struct HealthDataCacheKey: EnvironmentKey {
    static let defaultValue = HealthDataCache(
        dataProvider: _PreviewDataProvider()
    )
}

private struct HealthKitServiceKey: EnvironmentKey {
    static let defaultValue = HealthKitService(
        healthStore: _PreviewHealthStore(),
        deviceIdentifier: "preview"
    )
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
