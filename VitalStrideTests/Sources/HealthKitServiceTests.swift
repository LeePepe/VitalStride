import Foundation
import HealthKit
import Testing

@testable import VitalStride

// MARK: - Mock Health Store

final class MockHealthStore: HealthStoreProviding, @unchecked Sendable {
    nonisolated(unsafe) static var isHealthDataAvailable: Bool = true

    var authorizationRequestStatus: HKAuthorizationRequestStatus = .unnecessary
    var requestAuthorizationCalled = false
    var queryResults: [HKSampleType: AnchoredQueryResult] = [:]
    var queryError: (any Error)?

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
        if let error = queryError {
            throw error
        }
        return queryResults[type] ?? AnchoredQueryResult(
            samples: [],
            deletedObjects: [],
            newAnchor: nil
        )
    }
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
            deletedObjects: [],
            newAnchor: anchor
        )

        let points = try await service.fetchData(for: .heartRate)

        #expect(points.count == 1)
        #expect(points[0].sampleType == .heartRate)
        #expect(points[0].value == 72.0)
        #expect(points[0].unit == "bpm")
        #expect(points[0].startDate == start)
        #expect(points[0].endDate == end)
        #expect(points[0].sleepStage == nil)
    }

    @Test("Fetch step count returns correct data points")
    func fetchStepCount() async throws {
        let sample = makeQuantitySample(type: .stepCount, value: 1500.0, unit: .count())
        mockStore.queryResults[HKQuantityType(.stepCount)] = AnchoredQueryResult(
            samples: [sample],
            deletedObjects: [],
            newAnchor: HKQueryAnchor(fromValue: 1)
        )

        let points = try await service.fetchData(for: .stepCount)

        #expect(points.count == 1)
        #expect(points[0].value == 1500.0)
        #expect(points[0].unit == "count")
    }

    @Test("Fetch body mass returns correct data points")
    func fetchBodyMass() async throws {
        let sample = makeQuantitySample(type: .bodyMass, value: 75.5, unit: .gramUnit(with: .kilo))
        mockStore.queryResults[HKQuantityType(.bodyMass)] = AnchoredQueryResult(
            samples: [sample],
            deletedObjects: [],
            newAnchor: HKQueryAnchor(fromValue: 1)
        )

        let points = try await service.fetchData(for: .bodyMass)

        #expect(points.count == 1)
        #expect(points[0].value == 75.5)
        #expect(points[0].unit == "kg")
    }

    @Test("Fetch active energy returns correct data points")
    func fetchActiveEnergy() async throws {
        let sample = makeQuantitySample(type: .activeEnergyBurned, value: 350.0, unit: .kilocalorie())
        mockStore.queryResults[HKQuantityType(.activeEnergyBurned)] = AnchoredQueryResult(
            samples: [sample],
            deletedObjects: [],
            newAnchor: HKQueryAnchor(fromValue: 1)
        )

        let points = try await service.fetchData(for: .activeEnergyBurned)

        #expect(points.count == 1)
        #expect(points[0].value == 350.0)
        #expect(points[0].unit == "kcal")
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
            deletedObjects: [],
            newAnchor: HKQueryAnchor(fromValue: 5)
        )

        let points = try await service.fetchData(for: .sleepAnalysis)

        #expect(points.count == 5)
        #expect(points[0].sleepStage == .inBed)
        #expect(points[1].sleepStage == .asleepCore)
        #expect(points[2].sleepStage == .asleepDeep)
        #expect(points[3].sleepStage == .asleepREM)
        #expect(points[4].sleepStage == .awake)
        #expect(points[0].unit == "category")
    }

    @Test("Anchor is saved after successful query")
    func anchorSaved() async throws {
        let anchor = HKQueryAnchor(fromValue: 42)
        mockStore.queryResults[HKQuantityType(.heartRate)] = AnchoredQueryResult(
            samples: [],
            deletedObjects: [],
            newAnchor: anchor
        )

        _ = try await service.fetchData(for: .heartRate)

        let record = anchorStore.anchor(for: .heartRate, deviceIdentifier: "test-device")
        #expect(record != nil)
        #expect(record?.lastSyncDate != nil)
    }

    @Test("Incremental query uses existing anchor")
    func incrementalQuery() async throws {
        let initialAnchor = HKQueryAnchor(fromValue: 10)
        let anchorData = try NSKeyedArchiver.archivedData(
            withRootObject: initialAnchor,
            requiringSecureCoding: true
        )
        let record = AnchorRecord(anchorData: anchorData, lastSyncDate: Date())
        anchorStore.setAnchor(record, for: .stepCount, deviceIdentifier: "test-device")

        mockStore.queryResults[HKQuantityType(.stepCount)] = AnchoredQueryResult(
            samples: [makeQuantitySample(type: .stepCount, value: 500.0, unit: .count())],
            deletedObjects: [],
            newAnchor: HKQueryAnchor(fromValue: 11)
        )

        let points = try await service.fetchData(for: .stepCount)

        #expect(points.count == 1)
        #expect(points[0].value == 500.0)
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
                    deletedObjects: [],
                    newAnchor: HKQueryAnchor(fromValue: 1)
                )
            } else {
                let identifier: HKQuantityTypeIdentifier = switch sampleType {
                case .heartRate: .heartRate
                case .stepCount: .stepCount
                case .bodyMass: .bodyMass
                case .activeEnergyBurned: .activeEnergyBurned
                case .sleepAnalysis: .heartRate
                }
                mockStore.queryResults[hkType] = AnchoredQueryResult(
                    samples: [makeQuantitySample(type: identifier, value: 1.0, unit: sampleType.hkUnit)],
                    deletedObjects: [],
                    newAnchor: HKQueryAnchor(fromValue: 1)
                )
            }
        }

        let results = try await service.fetchAllData()

        #expect(results.count == 5)
        for sampleType in HealthSampleType.allCases {
            #expect(results[sampleType]?.isEmpty == false)
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
            deletedObjects: [],
            newAnchor: HKQueryAnchor(fromValue: 0)
        )

        let points = try await service.fetchData(for: .heartRate)
        #expect(points.isEmpty)
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
