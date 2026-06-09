import Foundation
import HealthKit
import Testing

@testable import HealthKitService

// MARK: - Mock Health Store

final class MockHealthStore: HealthStoreProviding, @unchecked Sendable {
    nonisolated(unsafe) static var isHealthDataAvailable: Bool = true

    var authorizationRequestStatus: HKAuthorizationRequestStatus = .unnecessary
    var requestAuthorizationCalled = false
    var queryResults: [HKSampleType: AnchoredQueryResult] = [:]
    var queryError: (any Error)?
    var queryErrors: [HKSampleType: any Error] = [:]
    var capturedPredicates: [HKSampleType: NSPredicate?] = [:]
    var capturedAnchors: [HKSampleType: HKQueryAnchor?] = [:]
    private let lock = NSLock()

    func requestAuthorization(
        toShare typesToShare: Set<HKSampleType>,
        read typesToRead: Set<HKObjectType>
    ) async throws {
        requestAuthorizationCalled = true
    }

    func statusForAuthorizationRequest(
        toShare typesToShare: Set<HKSampleType>,
        read typesToRead: Set<HKObjectType>
    ) async throws -> HKAuthorizationRequestStatus {
        authorizationRequestStatus
    }

    func executeAnchoredQuery(
        type: HKSampleType,
        predicate: NSPredicate?,
        anchor: HKQueryAnchor?,
        limit: Int
    ) async throws -> AnchoredQueryResult {
        lock.withLock {
            capturedPredicates[type] = predicate
            capturedAnchors[type] = anchor
        }
        let perTypeError = lock.withLock { queryErrors[type] }
        if let error = perTypeError {
            throw error
        }
        if let error = queryError {
            throw error
        }
        return lock.withLock {
            queryResults[type] ?? AnchoredQueryResult(
                samples: [],
                deletedObjectUUIDs: [],
                newAnchor: nil
            )
        }
    }

    func executeObserverAnchoredQuery(
        type: HKSampleType,
        predicate: NSPredicate?,
        anchor: HKQueryAnchor?,
        limit: Int
    ) -> AsyncStream<AnchoredQueryResult> {
        AsyncStream { $0.finish() }
    }

    func stopQuery(_ query: HKQuery) {}
}

// MARK: - Test Helpers

enum TestError: Error {
    case simulated
}

private func makeQuantitySample(
    type identifier: HKQuantityTypeIdentifier,
    value: Double,
    unit: HKUnit,
    start: Date = Date(),
    end: Date = Date()
) -> HKQuantitySample {
    HKQuantitySample(
        type: HKQuantityType(identifier),
        quantity: HKQuantity(unit: unit, doubleValue: value),
        start: start,
        end: end
    )
}

private func makeSleepSample(
    value: HKCategoryValueSleepAnalysis,
    start: Date = Date(),
    end: Date = Date()
) -> HKCategorySample {
    HKCategorySample(
        type: HKCategoryType(.sleepAnalysis),
        value: value.rawValue,
        start: start,
        end: end
    )
}

private func makeTestDefaults() -> UserDefaults {
    UserDefaults(suiteName: "HealthKitServiceTests_\(UUID().uuidString)")!
}

// MARK: - HealthKitService Tests

@Suite("HealthKitService Tests")
struct HealthKitServiceTests {
    let mockStore: MockHealthStore
    let anchorStore: HealthKitAnchorStore
    let service: HealthKitService

    init() {
        let mock = MockHealthStore()
        let defaults = makeTestDefaults()
        let anchors = HealthKitAnchorStore(defaults: defaults, keyPrefix: "test")
        mockStore = mock
        anchorStore = anchors
        service = HealthKitService(
            healthStore: mock,
            anchorStore: anchors,
            deviceIdentifier: "test-device"
        )
    }

    @Test("Fetch heart rate returns correct data points")
    func fetchHeartRate() async throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = Date(timeIntervalSince1970: 1_000_060)
        let sample = makeQuantitySample(
            type: .heartRate,
            value: 72.0,
            unit: HKUnit.count().unitDivided(by: .minute()),
            start: start,
            end: end
        )
        let anchor = HKQueryAnchor(fromValue: 1)
        mockStore.queryResults[HKQuantityType(.heartRate)] = AnchoredQueryResult(
            samples: [sample],
            deletedObjectUUIDs: [],
            newAnchor: anchor
        )

        let result = try await service.fetchData(for: .heartRate)

        #expect(result.dataPoints.count == 1)
        #expect(result.dataPoints[0].sampleType == .heartRate)
        #expect(result.dataPoints[0].value == 72.0)
        #expect(result.dataPoints[0].unit == "bpm")
        #expect(result.dataPoints[0].startDate == start)
        #expect(result.dataPoints[0].endDate == end)
        #expect(result.dataPoints[0].sleepStage == nil)
        #expect(result.deletedObjectIDs.isEmpty)
    }

    @Test("Fetch step count returns correct data points")
    func fetchStepCount() async throws {
        let sample = makeQuantitySample(type: .stepCount, value: 1500.0, unit: .count())
        mockStore.queryResults[HKQuantityType(.stepCount)] = AnchoredQueryResult(
            samples: [sample],
            deletedObjectUUIDs: [],
            newAnchor: HKQueryAnchor(fromValue: 1)
        )

        let result = try await service.fetchData(for: .stepCount)

        #expect(result.dataPoints.count == 1)
        #expect(result.dataPoints[0].value == 1500.0)
        #expect(result.dataPoints[0].unit == "count")
    }

    @Test("Fetch body mass returns correct data points")
    func fetchBodyMass() async throws {
        let sample = makeQuantitySample(type: .bodyMass, value: 75.5, unit: .gramUnit(with: .kilo))
        mockStore.queryResults[HKQuantityType(.bodyMass)] = AnchoredQueryResult(
            samples: [sample],
            deletedObjectUUIDs: [],
            newAnchor: HKQueryAnchor(fromValue: 1)
        )

        let result = try await service.fetchData(for: .bodyMass)

        #expect(result.dataPoints.count == 1)
        #expect(result.dataPoints[0].value == 75.5)
        #expect(result.dataPoints[0].unit == "kg")
    }

    @Test("Fetch active energy returns correct data points")
    func fetchActiveEnergy() async throws {
        let sample = makeQuantitySample(type: .activeEnergyBurned, value: 350.0, unit: .kilocalorie())
        mockStore.queryResults[HKQuantityType(.activeEnergyBurned)] = AnchoredQueryResult(
            samples: [sample],
            deletedObjectUUIDs: [],
            newAnchor: HKQueryAnchor(fromValue: 1)
        )

        let result = try await service.fetchData(for: .activeEnergyBurned)

        #expect(result.dataPoints.count == 1)
        #expect(result.dataPoints[0].value == 350.0)
        #expect(result.dataPoints[0].unit == "kcal")
    }

    @Test("Fetch sleep analysis parses stages correctly")
    func fetchSleepAnalysis() async throws {
        let samples: [HKSample] = [
            makeSleepSample(value: .inBed),
            makeSleepSample(value: .asleepCore),
            makeSleepSample(value: .asleepDeep),
            makeSleepSample(value: .asleepREM),
            makeSleepSample(value: .awake),
        ]
        mockStore.queryResults[HKCategoryType(.sleepAnalysis)] = AnchoredQueryResult(
            samples: samples,
            deletedObjectUUIDs: [],
            newAnchor: HKQueryAnchor(fromValue: 5)
        )

        let result = try await service.fetchData(for: .sleepAnalysis)

        #expect(result.dataPoints.count == 5)
        #expect(result.dataPoints[0].sleepStage == .inBed)
        #expect(result.dataPoints[1].sleepStage == .asleepCore)
        #expect(result.dataPoints[2].sleepStage == .asleepDeep)
        #expect(result.dataPoints[3].sleepStage == .asleepREM)
        #expect(result.dataPoints[4].sleepStage == .awake)
        #expect(result.dataPoints[0].unit == "category")
    }

    @Test("Anchor is saved after successful query")
    func anchorSaved() async throws {
        let anchor = HKQueryAnchor(fromValue: 42)
        mockStore.queryResults[HKQuantityType(.heartRate)] = AnchoredQueryResult(
            samples: [],
            deletedObjectUUIDs: [],
            newAnchor: anchor
        )

        _ = try await service.fetchData(for: .heartRate)

        let record = anchorStore.anchor(for: .heartRate, deviceIdentifier: "test-device")
        #expect(record != nil)
        #expect(record?.lastSyncDate != nil)
    }

    @Test("Query without dateRange uses saved anchor for incremental fetch")
    func queryUsesSavedAnchor() async throws {
        let initialAnchor = HKQueryAnchor(fromValue: 10)
        let anchorData = try NSKeyedArchiver.archivedData(
            withRootObject: initialAnchor,
            requiringSecureCoding: true
        )
        let record = AnchorRecord(anchorData: anchorData, lastSyncDate: Date())
        anchorStore.setAnchor(record, for: .stepCount, deviceIdentifier: "test-device")

        mockStore.queryResults[HKQuantityType(.stepCount)] = AnchoredQueryResult(
            samples: [makeQuantitySample(type: .stepCount, value: 500.0, unit: .count())],
            deletedObjectUUIDs: [],
            newAnchor: HKQueryAnchor(fromValue: 11)
        )

        let result = try await service.fetchData(for: .stepCount)

        #expect(result.dataPoints.count == 1)
        #expect(result.dataPoints[0].value == 500.0)
        let capturedAnchor = mockStore.capturedAnchors[HKQuantityType(.stepCount)]
        #expect(capturedAnchor != nil)
        #expect(capturedAnchor! != nil)
    }

    @Test("Query with dateRange passes nil anchor for full fetch")
    func queryWithDateRangeIgnoresAnchor() async throws {
        let initialAnchor = HKQueryAnchor(fromValue: 10)
        let anchorData = try NSKeyedArchiver.archivedData(
            withRootObject: initialAnchor,
            requiringSecureCoding: true
        )
        let record = AnchorRecord(anchorData: anchorData, lastSyncDate: Date())
        anchorStore.setAnchor(record, for: .stepCount, deviceIdentifier: "test-device")

        mockStore.queryResults[HKQuantityType(.stepCount)] = AnchoredQueryResult(
            samples: [makeQuantitySample(type: .stepCount, value: 500.0, unit: .count())],
            deletedObjectUUIDs: [],
            newAnchor: HKQueryAnchor(fromValue: 11)
        )

        let dateRange = DateInterval(
            start: Date(timeIntervalSinceNow: -86400),
            end: Date()
        )
        let result = try await service.fetchData(for: .stepCount, dateRange: dateRange)

        #expect(result.dataPoints.count == 1)
        let capturedAnchor = mockStore.capturedAnchors[HKQuantityType(.stepCount)]
        #expect(capturedAnchor == nil || capturedAnchor! == nil)
    }

    @Test("Throws error when health data is not available")
    func healthDataNotAvailable() async {
        MockHealthStore.isHealthDataAvailable = false
        defer { MockHealthStore.isHealthDataAvailable = true }

        await #expect(throws: HealthKitServiceError.self) {
            try await service.fetchData(for: .heartRate)
        }
    }

    @Test("Throws error when authorization not determined")
    func authorizationNotDetermined() async {
        mockStore.authorizationRequestStatus = .shouldRequest

        await #expect(throws: HealthKitServiceError.self) {
            try await service.fetchData(for: .heartRate)
        }
    }

    @Test("Propagates query errors")
    func queryError() async {
        mockStore.queryError = TestError.simulated

        await #expect(throws: HealthKitServiceError.self) {
            try await service.fetchData(for: .heartRate)
        }
    }

    @Test("Fetch all data returns results for every type")
    func fetchAllData() async throws {
        for sampleType in HealthSampleType.allCases {
            let hkType = sampleType.hkSampleType
            if sampleType == .sleepAnalysis {
                mockStore.queryResults[hkType] = AnchoredQueryResult(
                    samples: [makeSleepSample(value: .asleepCore)],
                    deletedObjectUUIDs: [],
                    newAnchor: HKQueryAnchor(fromValue: 1)
                )
            } else if let quantityType = hkType as? HKQuantityType {
                let sample = HKQuantitySample(
                    type: quantityType,
                    quantity: HKQuantity(unit: sampleType.hkUnit, doubleValue: 1.0),
                    start: Date(),
                    end: Date()
                )
                mockStore.queryResults[hkType] = AnchoredQueryResult(
                    samples: [sample],
                    deletedObjectUUIDs: [],
                    newAnchor: HKQueryAnchor(fromValue: 1)
                )
            }
        }

        let results = try await service.fetchAllData()

        #expect(results.count == 23)
        for sampleType in HealthSampleType.allCases {
            #expect(results[sampleType]?.dataPoints.isEmpty == false)
        }
    }

    @Test("Request authorization calls health store")
    func requestAuthorization() async throws {
        try await service.requestAuthorization()
        #expect(mockStore.requestAuthorizationCalled)
    }

    @Test("Empty query result returns empty array")
    func emptyResult() async throws {
        mockStore.queryResults[HKQuantityType(.heartRate)] = AnchoredQueryResult(
            samples: [],
            deletedObjectUUIDs: [],
            newAnchor: HKQueryAnchor(fromValue: 0)
        )

        let result = try await service.fetchData(for: .heartRate)
        #expect(result.dataPoints.isEmpty)
    }

    @Test("Throws error when authorization status is unknown")
    func authorizationUnknown() async {
        mockStore.authorizationRequestStatus = .unknown

        await #expect(throws: HealthKitServiceError.self) {
            try await service.fetchData(for: .heartRate)
        }
    }

    @Test("Deleted objects IDs are empty when no deletions")
    func deletedObjectsEmpty() async throws {
        let sample = makeQuantitySample(type: .heartRate, value: 72.0, unit: HKUnit.count().unitDivided(by: .minute()))
        mockStore.queryResults[HKQuantityType(.heartRate)] = AnchoredQueryResult(
            samples: [sample],
            deletedObjectUUIDs: [],
            newAnchor: HKQueryAnchor(fromValue: 2)
        )

        let result = try await service.fetchData(for: .heartRate)

        #expect(result.dataPoints.count == 1)
        #expect(result.deletedObjectIDs.isEmpty)
    }

    @Test("Deleted object UUIDs are returned to caller")
    func deletedObjectsReturned() async throws {
        let deletedID1 = UUID()
        let deletedID2 = UUID()
        let sample = makeQuantitySample(type: .heartRate, value: 72.0, unit: HKUnit.count().unitDivided(by: .minute()))
        mockStore.queryResults[HKQuantityType(.heartRate)] = AnchoredQueryResult(
            samples: [sample],
            deletedObjectUUIDs: [deletedID1, deletedID2],
            newAnchor: HKQueryAnchor(fromValue: 3)
        )

        let result = try await service.fetchData(for: .heartRate)

        #expect(result.dataPoints.count == 1)
        #expect(result.deletedObjectIDs.count == 2)
        #expect(result.deletedObjectIDs.contains(deletedID1))
        #expect(result.deletedObjectIDs.contains(deletedID2))
    }

    @Test("First sync applies default time predicate")
    func firstSyncAppliesPredicate() async throws {
        mockStore.queryResults[HKQuantityType(.heartRate)] = AnchoredQueryResult(
            samples: [],
            deletedObjectUUIDs: [],
            newAnchor: HKQueryAnchor(fromValue: 0)
        )

        _ = try await service.fetchData(for: .heartRate)

        let captured = mockStore.capturedPredicates[HKQuantityType(.heartRate)]
        #expect(captured != nil)
    }

    @Test("Query always applies date predicate even with saved anchor")
    func alwaysAppliesDatePredicate() async throws {
        let initialAnchor = HKQueryAnchor(fromValue: 10)
        let anchorData = try NSKeyedArchiver.archivedData(
            withRootObject: initialAnchor,
            requiringSecureCoding: true
        )
        let record = AnchorRecord(anchorData: anchorData, lastSyncDate: Date())
        anchorStore.setAnchor(record, for: .heartRate, deviceIdentifier: "test-device")

        mockStore.queryResults[HKQuantityType(.heartRate)] = AnchoredQueryResult(
            samples: [],
            deletedObjectUUIDs: [],
            newAnchor: HKQueryAnchor(fromValue: 11)
        )

        _ = try await service.fetchData(for: .heartRate)

        let captured = mockStore.capturedPredicates[HKQuantityType(.heartRate)]
        #expect(captured != nil)
    }

    @Test("Custom date range overrides default predicate")
    func customDateRange() async throws {
        mockStore.queryResults[HKQuantityType(.heartRate)] = AnchoredQueryResult(
            samples: [],
            deletedObjectUUIDs: [],
            newAnchor: HKQueryAnchor(fromValue: 0)
        )

        let range = DateInterval(
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 86400)
        )
        _ = try await service.fetchData(for: .heartRate, dateRange: range)

        let captured = mockStore.capturedPredicates[HKQuantityType(.heartRate)]
        #expect(captured != nil)
    }

    @Test("Anchor is NOT saved when dateRange is provided")
    func anchorNotSavedWithDateRange() async throws {
        let anchor = HKQueryAnchor(fromValue: 99)
        mockStore.queryResults[HKQuantityType(.heartRate)] = AnchoredQueryResult(
            samples: [],
            deletedObjectUUIDs: [],
            newAnchor: anchor
        )

        let dateRange = DateInterval(
            start: Date(timeIntervalSinceNow: -86400),
            end: Date()
        )
        _ = try await service.fetchData(for: .heartRate, dateRange: dateRange)

        let record = anchorStore.anchor(for: .heartRate, deviceIdentifier: "test-device")
        #expect(record == nil)
    }
}

// MARK: - Authorization Flow Tests

@Suite("HealthKit Authorization Flow Tests")
struct HealthKitAuthorizationFlowTests {
    let mockStore: MockHealthStore
    let service: HealthKitService

    init() {
        let mock = MockHealthStore()
        mock.authorizationRequestStatus = .shouldRequest
        let defaults = makeTestDefaults()
        let anchors = HealthKitAnchorStore(defaults: defaults, keyPrefix: "authflow")
        mockStore = mock
        service = HealthKitService(
            healthStore: mock,
            anchorStore: anchors,
            deviceIdentifier: "test-device"
        )
    }

    @Test("requestAuthorization succeeds and enables data fetch")
    func requestAuthorizationEnablesFetch() async throws {
        mockStore.queryResults[HKQuantityType(.stepCount)] = AnchoredQueryResult(
            samples: [],
            deletedObjectUUIDs: [],
            newAnchor: HKQueryAnchor(fromValue: 1)
        )

        try await service.requestAuthorization()
        #expect(mockStore.requestAuthorizationCalled)

        mockStore.authorizationRequestStatus = .unnecessary
        let result = try await service.fetchData(for: .stepCount)
        #expect(result.dataPoints.isEmpty)
    }

    @Test("requestAuthorization is idempotent")
    func requestAuthorizationIdempotent() async throws {
        try await service.requestAuthorization()
        try await service.requestAuthorization()
        #expect(mockStore.requestAuthorizationCalled)
    }

    @Test("fetchData fails before authorization is granted")
    func fetchDataFailsBeforeAuth() async {
        await #expect(throws: HealthKitServiceError.self) {
            try await service.fetchData(for: .heartRate)
        }
    }

    @Test("Notification name constant is defined")
    func notificationNameDefined() {
        let name = Notification.Name.healthKitAuthorizationChanged
        #expect(name.rawValue == "healthKitAuthorizationChanged")
    }

    @Test("authorizationStatus returns current status from health store")
    func authorizationStatusReturnsStatus() async throws {
        mockStore.authorizationRequestStatus = .shouldRequest
        let status = try await service.authorizationStatus()
        #expect(status == .shouldRequest)
    }

    @Test("authorizationStatus returns unnecessary after authorization")
    func authorizationStatusAfterAuth() async throws {
        mockStore.authorizationRequestStatus = .unnecessary
        let status = try await service.authorizationStatus()
        #expect(status == .unnecessary)
    }
}

// MARK: - SleepStage Tests

@Suite("SleepStage Mapping Tests")
struct SleepStageTests {
    @Test("Maps all HKCategoryValueSleepAnalysis values")
    func mapAllValues() {
        #expect(SleepStage(from: .inBed) == .inBed)
        #expect(SleepStage(from: .asleepUnspecified) == .asleepUnspecified)
        #expect(SleepStage(from: .asleepCore) == .asleepCore)
        #expect(SleepStage(from: .asleepDeep) == .asleepDeep)
        #expect(SleepStage(from: .asleepREM) == .asleepREM)
        #expect(SleepStage(from: .awake) == .awake)
    }

    @Test("SleepStage has all expected cases")
    func allCases() {
        #expect(SleepStage.allCases.count == 6)
    }
}

// MARK: - HealthSampleType Extension Tests

@Suite("HealthSampleType HK Extension Tests")
struct HealthSampleTypeHKExtensionTests {
    @Test("Each sample type maps to correct HK type")
    func hkSampleTypeMapping() {
        #expect(HealthSampleType.heartRate.hkSampleType == HKQuantityType(.heartRate))
        #expect(HealthSampleType.stepCount.hkSampleType == HKQuantityType(.stepCount))
        #expect(HealthSampleType.bodyMass.hkSampleType == HKQuantityType(.bodyMass))
        #expect(HealthSampleType.activeEnergyBurned.hkSampleType == HKQuantityType(.activeEnergyBurned))
        #expect(HealthSampleType.sleepAnalysis.hkSampleType == HKCategoryType(.sleepAnalysis))
    }

    @Test("Each sample type has a unit string")
    func unitStrings() {
        #expect(HealthSampleType.heartRate.unitString == "bpm")
        #expect(HealthSampleType.stepCount.unitString == "count")
        #expect(HealthSampleType.bodyMass.unitString == "kg")
        #expect(HealthSampleType.activeEnergyBurned.unitString == "kcal")
        #expect(HealthSampleType.sleepAnalysis.unitString == "category")
    }
}

// MARK: - ProbeAvailableTypes Tests

@Suite("ProbeAvailableTypes Tests")
struct ProbeAvailableTypesTests {
    let mockStore: MockHealthStore
    let service: HealthKitService

    init() {
        let mock = MockHealthStore()
        let defaults = makeTestDefaults()
        let anchors = HealthKitAnchorStore(defaults: defaults, keyPrefix: "probe")
        mockStore = mock
        service = HealthKitService(
            healthStore: mock,
            anchorStore: anchors,
            deviceIdentifier: "test-device"
        )
    }

    @Test("Returns all types when all have data")
    func allTypesAvailable() async {
        let types: Set<HealthSampleType> = [.heartRate, .stepCount, .bodyMass]
        for sampleType in types {
            let sample = makeQuantitySample(
                type: HKQuantityTypeIdentifier(rawValue: sampleType.hkSampleType.identifier),
                value: 1.0,
                unit: sampleType.hkUnit
            )
            mockStore.queryResults[sampleType.hkSampleType] = AnchoredQueryResult(
                samples: [sample],
                deletedObjectUUIDs: [],
                newAnchor: nil
            )
        }

        let result = await service.probeAvailableTypes(from: types)

        #expect(result == types)
    }

    @Test("Returns subset when only some types have data")
    func partialTypesAvailable() async {
        let heartRateSample = makeQuantitySample(
            type: .heartRate,
            value: 72.0,
            unit: HKUnit.count().unitDivided(by: .minute())
        )
        mockStore.queryResults[HKQuantityType(.heartRate)] = AnchoredQueryResult(
            samples: [heartRateSample],
            deletedObjectUUIDs: [],
            newAnchor: nil
        )
        mockStore.queryResults[HKQuantityType(.stepCount)] = AnchoredQueryResult(
            samples: [],
            deletedObjectUUIDs: [],
            newAnchor: nil
        )

        let result = await service.probeAvailableTypes(from: [.heartRate, .stepCount])

        #expect(result == [.heartRate])
    }

    @Test("Returns empty set when no types have data")
    func noTypesAvailable() async {
        mockStore.queryResults[HKQuantityType(.heartRate)] = AnchoredQueryResult(
            samples: [],
            deletedObjectUUIDs: [],
            newAnchor: nil
        )
        mockStore.queryResults[HKQuantityType(.stepCount)] = AnchoredQueryResult(
            samples: [],
            deletedObjectUUIDs: [],
            newAnchor: nil
        )

        let result = await service.probeAvailableTypes(from: [.heartRate, .stepCount])

        #expect(result.isEmpty)
    }

    @Test("Skips types that throw errors and returns the rest")
    func errorSkipsType() async {
        let stepSample = makeQuantitySample(type: .stepCount, value: 500.0, unit: .count())
        mockStore.queryResults[HKQuantityType(.stepCount)] = AnchoredQueryResult(
            samples: [stepSample],
            deletedObjectUUIDs: [],
            newAnchor: nil
        )
        mockStore.queryErrors[HKQuantityType(.heartRate)] = TestError.simulated

        let result = await service.probeAvailableTypes(from: [.heartRate, .stepCount])

        #expect(result == [.stepCount])
    }

    @Test("Returns empty set when HealthKit is unavailable")
    func healthKitUnavailable() async {
        MockHealthStore.isHealthDataAvailable = false
        defer { MockHealthStore.isHealthDataAvailable = true }

        let result = await service.probeAvailableTypes(from: [.heartRate, .stepCount])

        #expect(result.isEmpty)
    }

    @Test("Returns empty set for empty input")
    func emptyInput() async {
        let result = await service.probeAvailableTypes(from: [])

        #expect(result.isEmpty)
    }

    @Test("Includes sleep analysis category type")
    func sleepAnalysisProbe() async {
        let sleepSample = makeSleepSample(value: .asleepCore)
        mockStore.queryResults[HKCategoryType(.sleepAnalysis)] = AnchoredQueryResult(
            samples: [sleepSample],
            deletedObjectUUIDs: [],
            newAnchor: nil
        )

        let result = await service.probeAvailableTypes(from: [.sleepAnalysis])

        #expect(result == [.sleepAnalysis])
    }
}
