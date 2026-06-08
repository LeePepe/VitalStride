import Foundation
import HealthKit
import os

// MARK: - Notifications

extension Notification.Name {
    public static let healthKitAuthorizationChanged = Notification.Name("healthKitAuthorizationChanged")
}

// MARK: - HealthStore Abstraction

public protocol HealthStoreProviding: Sendable {
    static var isHealthDataAvailable: Bool { get }

    func requestAuthorization(
        toShare typesToShare: Set<HKSampleType>,
        read typesToRead: Set<HKObjectType>
    ) async throws

    func statusForAuthorizationRequest(
        toShare typesToShare: Set<HKSampleType>,
        read typesToRead: Set<HKObjectType>
    ) async throws -> HKAuthorizationRequestStatus

    func executeAnchoredQuery(
        type: HKSampleType,
        predicate: NSPredicate?,
        anchor: HKQueryAnchor?,
        limit: Int
    ) async throws -> AnchoredQueryResult

    func executeObserverAnchoredQuery(
        type: HKSampleType,
        predicate: NSPredicate?,
        anchor: HKQueryAnchor?,
        limit: Int
    ) -> AsyncStream<AnchoredQueryResult>

    func stopQuery(_ query: HKQuery)
}

public struct AnchoredQueryResult: Sendable {
    public let samples: [HKSample]
    public let deletedObjectUUIDs: [UUID]
    public let newAnchor: HKQueryAnchor?

    public init(samples: [HKSample], deletedObjectUUIDs: [UUID], newAnchor: HKQueryAnchor?) {
        self.samples = samples
        self.deletedObjectUUIDs = deletedObjectUUIDs
        self.newAnchor = newAnchor
    }
}

// MARK: - HKHealthStore Conformance

extension HKHealthStore: HealthStoreProviding {
    public static var isHealthDataAvailable: Bool {
        Self.isHealthDataAvailable()
    }

    public func executeAnchoredQuery(
        type: HKSampleType,
        predicate: NSPredicate?,
        anchor: HKQueryAnchor?,
        limit: Int
    ) async throws -> AnchoredQueryResult {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: type,
                predicate: predicate,
                anchor: anchor,
                limit: limit
            ) { _, samples, deletedObjects, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: AnchoredQueryResult(
                    samples: samples ?? [],
                    deletedObjectUUIDs: (deletedObjects ?? []).map(\.uuid),
                    newAnchor: newAnchor
                ))
            }
            self.execute(query)
        }
    }

    public func executeObserverAnchoredQuery(
        type: HKSampleType,
        predicate: NSPredicate?,
        anchor: HKQueryAnchor?,
        limit: Int
    ) -> AsyncStream<AnchoredQueryResult> {
        let store = self
        return AsyncStream { continuation in
            let query = HKAnchoredObjectQuery(
                type: type,
                predicate: predicate,
                anchor: anchor,
                limit: limit
            ) { _, samples, deletedObjects, newAnchor, error in
                guard error == nil else {
                    continuation.finish()
                    return
                }
                let result = AnchoredQueryResult(
                    samples: samples ?? [],
                    deletedObjectUUIDs: (deletedObjects ?? []).map(\.uuid),
                    newAnchor: newAnchor
                )
                continuation.yield(result)
            }

            query.updateHandler = { _, samples, deletedObjects, newAnchor, error in
                guard error == nil else {
                    continuation.finish()
                    return
                }
                let result = AnchoredQueryResult(
                    samples: samples ?? [],
                    deletedObjectUUIDs: (deletedObjects ?? []).map(\.uuid),
                    newAnchor: newAnchor
                )
                continuation.yield(result)
            }

            continuation.onTermination = { _ in
                store.stop(query)
            }

            store.execute(query)
        }
    }

    public func stopQuery(_ query: HKQuery) {
        stop(query)
    }
}

// MARK: - HealthKitService

public final class HealthKitService: Sendable {
    private let healthStore: any HealthStoreProviding
    private let anchorStore: HealthKitAnchorStore
    private let deviceIdentifier: String
    private let logger: Logger
    private let signposter: OSSignposter

    public static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.heartRate),
        HKQuantityType(.stepCount),
        HKQuantityType(.bodyMass),
        HKQuantityType(.activeEnergyBurned),
        HKCategoryType(.sleepAnalysis),
    ]

    public init(
        healthStore: any HealthStoreProviding = HKHealthStore(),
        anchorStore: HealthKitAnchorStore = HealthKitAnchorStore(),
        deviceIdentifier: String
    ) {
        self.healthStore = healthStore
        self.anchorStore = anchorStore
        self.deviceIdentifier = deviceIdentifier
        self.logger = Logger(subsystem: "com.vitalstride", category: "HealthKitService")
        self.signposter = OSSignposter(subsystem: "com.vitalstride", category: "HealthKitService")
    }

    public func clearAllAnchors() {
        anchorStore.removeAllAnchors(for: deviceIdentifier)
    }

    public func probeReadAccess(for types: Set<HealthSampleType>) async -> Bool {
        guard type(of: healthStore).isHealthDataAvailable else { return false }
        let window = HKQuery.predicateForSamples(
            withStart: Date(timeIntervalSinceNow: -30 * 24 * 3600),
            end: Date()
        )
        for sampleType in types {
            do {
                let result = try await healthStore.executeAnchoredQuery(
                    type: sampleType.hkSampleType,
                    predicate: window,
                    anchor: nil,
                    limit: 1
                )
                if !result.samples.isEmpty { return true }
            } catch {
                continue
            }
        }
        return false
    }

    public func requestAuthorization() async throws {
        guard type(of: healthStore).isHealthDataAvailable else {
            throw HealthKitServiceError.healthDataNotAvailable
        }
        try await healthStore.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    public func authorizationStatus() async throws -> HKAuthorizationRequestStatus {
        guard type(of: healthStore).isHealthDataAvailable else {
            throw HealthKitServiceError.healthDataNotAvailable
        }
        return try await healthStore.statusForAuthorizationRequest(toShare: [], read: Self.readTypes)
    }

    public static let defaultFirstSyncWindow: TimeInterval = 30 * 24 * 3600

    public func fetchData(
        for sampleType: HealthSampleType,
        dateRange: DateInterval? = nil
    ) async throws -> HealthFetchResult {
        guard type(of: healthStore).isHealthDataAvailable else {
            throw HealthKitServiceError.healthDataNotAvailable
        }

        let hkType = sampleType.hkSampleType
        let status = try await healthStore.statusForAuthorizationRequest(
            toShare: [],
            read: [hkType]
        )
        guard status == .unnecessary else {
            throw HealthKitServiceError.authorizationNotDetermined
        }

        let start = ContinuousClock.now
        let existingRecord = anchorStore.anchor(for: sampleType, deviceIdentifier: deviceIdentifier)
        let isFirstSync = existingRecord == nil

        let predicate: NSPredicate? = if let dateRange {
            HKQuery.predicateForSamples(withStart: dateRange.start, end: dateRange.end)
        } else {
            HKQuery.predicateForSamples(
                withStart: Date(timeIntervalSinceNow: -Self.defaultFirstSyncWindow),
                end: Date()
            )
        }

        let queryAnchor: HKQueryAnchor? = if dateRange == nil, let record = existingRecord {
            try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: HKQueryAnchor.self,
                from: record.anchorData
            )
        } else {
            nil
        }

        do {
            let result = try await healthStore.executeAnchoredQuery(
                type: hkType,
                predicate: predicate,
                anchor: queryAnchor,
                limit: HKObjectQueryNoLimit
            )

            if dateRange == nil, let newAnchor = result.newAnchor {
                saveAnchor(newAnchor, for: sampleType)
            }

            let dataPoints = result.samples.compactMap { sample in
                convertToDataPoint(sample, sampleType: sampleType)
            }

            logQuery(sampleType: sampleType, count: dataPoints.count, start: start, isFirstSync: isFirstSync, error: nil)
            return HealthFetchResult(dataPoints: dataPoints, deletedObjectIDs: result.deletedObjectUUIDs)
        } catch {
            logQuery(sampleType: sampleType, count: 0, start: start, isFirstSync: isFirstSync, error: error)
            throw HealthKitServiceError.queryFailed(underlying: error)
        }
    }

    public func fetchAllData(dateRange: DateInterval? = nil) async throws -> [HealthSampleType: HealthFetchResult] {
        try await withThrowingTaskGroup(of: (HealthSampleType, HealthFetchResult).self) { group in
            for sampleType in HealthSampleType.allCases {
                group.addTask {
                    let result = try await self.fetchData(for: sampleType, dateRange: dateRange)
                    return (sampleType, result)
                }
            }

            var results: [HealthSampleType: HealthFetchResult] = [:]
            for try await (sampleType, result) in group {
                results[sampleType] = result
            }
            return results
        }
    }

    // MARK: - Real-time Observation

    public func observeHeartRate() -> AsyncStream<HealthDataPoint> {
        let healthStore = self.healthStore
        let logger = self.logger
        let signposter = self.signposter

        return AsyncStream { continuation in
            guard type(of: healthStore).isHealthDataAvailable else {
                logger.info("heartrate_observe_stop reason=healthkit_unavailable")
                signposter.emitEvent("heartrate_observe_stop", "reason=healthkit_unavailable")
                continuation.finish()
                return
            }

            let hkType = HealthSampleType.heartRate.hkSampleType
            let hkUnit = HealthSampleType.heartRate.hkUnit
            let unitString = HealthSampleType.heartRate.unitString

            let observeTask = Task {
                let status: HKAuthorizationRequestStatus
                do {
                    status = try await healthStore.statusForAuthorizationRequest(
                        toShare: [],
                        read: [hkType]
                    )
                } catch {
                    logger.info("heartrate_observe_stop reason=permission_denied")
                    signposter.emitEvent("heartrate_observe_stop", "reason=permission_denied")
                    continuation.finish()
                    return
                }

                guard status == .unnecessary else {
                    logger.info("heartrate_observe_stop reason=permission_denied")
                    signposter.emitEvent("heartrate_observe_stop", "reason=permission_denied")
                    continuation.finish()
                    return
                }

                logger.info("heartrate_observe_start")
                let signpostID = signposter.makeSignpostID()
                let state = signposter.beginInterval("heartrate_observe", id: signpostID)

                let stream = healthStore.executeObserverAnchoredQuery(
                    type: hkType,
                    predicate: nil,
                    anchor: nil,
                    limit: HKObjectQueryNoLimit
                )

                for await result in stream {
                    let heartRateSamples = result.samples.compactMap { sample -> HealthDataPoint? in
                        guard let quantitySample = sample as? HKQuantitySample else { return nil }
                        let value = quantitySample.quantity.doubleValue(for: hkUnit)
                        return HealthDataPoint(
                            id: quantitySample.uuid,
                            sampleType: .heartRate,
                            startDate: quantitySample.startDate,
                            endDate: quantitySample.endDate,
                            value: value,
                            unit: unitString,
                            sleepStage: nil,
                            sourceName: quantitySample.sourceRevision.source.name
                        )
                    }

                    if !heartRateSamples.isEmpty {
                        logger.info("heartrate_sample_received count=\(heartRateSamples.count)")
                        signposter.emitEvent("heartrate_sample_received", "\(heartRateSamples.count) samples")
                    }

                    for dataPoint in heartRateSamples {
                        continuation.yield(dataPoint)
                    }
                }

                let stopReason = Task.isCancelled ? "task_cancelled" : "stream_ended"
                logger.info("heartrate_observe_stop reason=\(stopReason)")
                signposter.endInterval("heartrate_observe", state)
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                observeTask.cancel()
            }
        }
    }

    // MARK: - Private Helpers

    private func saveAnchor(_ anchor: HKQueryAnchor, for sampleType: HealthSampleType) {
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: anchor,
            requiringSecureCoding: true
        ) else { return }
        let record = AnchorRecord(anchorData: data, lastSyncDate: Date())
        anchorStore.setAnchor(record, for: sampleType, deviceIdentifier: deviceIdentifier)
    }

    private func convertToDataPoint(_ sample: HKSample, sampleType: HealthSampleType) -> HealthDataPoint? {
        switch sampleType {
        case .sleepAnalysis:
            return convertSleepSample(sample)
        case .heartRate, .stepCount, .bodyMass, .activeEnergyBurned:
            return convertQuantitySample(sample, sampleType: sampleType)
        }
    }

    private func convertQuantitySample(_ sample: HKSample, sampleType: HealthSampleType) -> HealthDataPoint? {
        guard let quantitySample = sample as? HKQuantitySample else { return nil }
        let value = quantitySample.quantity.doubleValue(for: sampleType.hkUnit)

        return HealthDataPoint(
            id: quantitySample.uuid,
            sampleType: sampleType,
            startDate: quantitySample.startDate,
            endDate: quantitySample.endDate,
            value: value,
            unit: sampleType.unitString,
            sleepStage: nil,
            sourceName: quantitySample.sourceRevision.source.name
        )
    }

    private func convertSleepSample(_ sample: HKSample) -> HealthDataPoint? {
        guard let categorySample = sample as? HKCategorySample else { return nil }
        let stage = HKCategoryValueSleepAnalysis(rawValue: categorySample.value)
            .flatMap { SleepStage(from: $0) }

        return HealthDataPoint(
            id: categorySample.uuid,
            sampleType: .sleepAnalysis,
            startDate: categorySample.startDate,
            endDate: categorySample.endDate,
            value: Double(categorySample.value),
            unit: "category",
            sleepStage: stage,
            sourceName: categorySample.sourceRevision.source.name
        )
    }

    private func logQuery(
        sampleType: HealthSampleType,
        count: Int,
        start: ContinuousClock.Instant,
        isFirstSync: Bool,
        error: (any Error)?
    ) {
        let elapsed = ContinuousClock.now - start
        let ms = elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
        let status = error == nil ? "success" : "failed"

        if let error {
            logger.error(
                "query type=\(sampleType.rawValue, privacy: .private) count=\(count, privacy: .private) ms=\(ms) firstSync=\(isFirstSync, privacy: .private) status=\(status) error=\(error.localizedDescription, privacy: .private)"
            )
        } else {
            logger.info(
                "query type=\(sampleType.rawValue, privacy: .private) count=\(count, privacy: .private) ms=\(ms) firstSync=\(isFirstSync, privacy: .private) status=\(status)"
            )
        }
    }
}

// MARK: - HealthSampleType + HealthKit

extension HealthSampleType {
    public var hkSampleType: HKSampleType {
        switch self {
        case .heartRate: HKQuantityType(.heartRate)
        case .stepCount: HKQuantityType(.stepCount)
        case .bodyMass: HKQuantityType(.bodyMass)
        case .activeEnergyBurned: HKQuantityType(.activeEnergyBurned)
        case .sleepAnalysis: HKCategoryType(.sleepAnalysis)
        }
    }

    public var hkUnit: HKUnit {
        switch self {
        case .heartRate: HKUnit.count().unitDivided(by: .minute())
        case .stepCount: .count()
        case .bodyMass: .gramUnit(with: .kilo)
        case .activeEnergyBurned: .kilocalorie()
        case .sleepAnalysis: .count()
        }
    }

    public var unitString: String {
        switch self {
        case .heartRate: "bpm"
        case .stepCount: "count"
        case .bodyMass: "kg"
        case .activeEnergyBurned: "kcal"
        case .sleepAnalysis: "category"
        }
    }
}

// MARK: - SleepStage + HealthKit

extension SleepStage {
    public init?(from value: HKCategoryValueSleepAnalysis) {
        switch value {
        case .inBed: self = .inBed
        case .asleepUnspecified: self = .asleepUnspecified
        case .asleepCore: self = .asleepCore
        case .asleepDeep: self = .asleepDeep
        case .asleepREM: self = .asleepREM
        case .awake: self = .awake
        @unknown default: return nil
        }
    }
}
