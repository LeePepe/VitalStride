import Foundation
import HealthKit
import Testing
@testable import HealthKitService

private final class MockWorkoutQueryHealthStore: HealthStoreProviding, @unchecked Sendable {
    static let isHealthDataAvailable = true

    var samples: [HKSample]
    var newAnchor: HKQueryAnchor?
    var receivedAnchors: [HKQueryAnchor?] = []

    init(samples: [HKSample], newAnchor: HKQueryAnchor? = nil) {
        self.samples = samples
        self.newAnchor = newAnchor
    }

    func requestAuthorization(
        toShare typesToShare: Set<HKSampleType>,
        read typesToRead: Set<HKObjectType>
    ) async throws {}

    func statusForAuthorizationRequest(
        toShare typesToShare: Set<HKSampleType>,
        read typesToRead: Set<HKObjectType>
    ) async throws -> HKAuthorizationRequestStatus {
        .unnecessary
    }

    func executeAnchoredQuery(
        type: HKSampleType,
        predicate: NSPredicate?,
        anchor: HKQueryAnchor?,
        limit: Int
    ) async throws -> AnchoredQueryResult {
        receivedAnchors.append(anchor)
        return AnchoredQueryResult(
            samples: samples,
            deletedObjectUUIDs: [],
            newAnchor: newAnchor
        )
    }

    func executeObserverAnchoredQuery(
        type: HKSampleType,
        predicate: NSPredicate?,
        anchor: HKQueryAnchor?,
        limit: Int
    ) -> AsyncStream<AnchoredQueryResult> {
        AsyncStream { _ in }
    }

    func stopQuery(_ query: HKQuery) {}

    func executeSampleQuery(
        type: HKSampleType,
        predicate: NSPredicate?,
        limit: Int
    ) async throws -> [HKSample] {
        []
    }

    func delete(_ objects: [HKObject]) async throws {}

    func executeAverageQuantityQuery(
        quantityType: HKQuantityType,
        predicate: NSPredicate
    ) async -> HKQuantity? {
        nil
    }
}

private func makeWorkout(start: Date = Date(), duration: TimeInterval = 30 * 60) -> HKWorkout {
    HKWorkout(
        activityType: .running,
        start: start,
        end: start.addingTimeInterval(duration),
        workoutEvents: nil,
        totalEnergyBurned: nil,
        totalDistance: nil,
        device: nil,
        metadata: nil
    )
}

private func encodedAnchor(_ anchor: HKQueryAnchor) throws -> Data {
    try NSKeyedArchiver.archivedData(
        withRootObject: anchor,
        requiringSecureCoding: true
    )
}

@Suite("HealthWorkoutQueryContract")
struct HealthWorkoutQueryContractTests {

    @Test("fetchWorkouts remains anchor-free snapshot and never advances the default workout anchor")
    func fetchWorkoutsRemainsAnchorFreeSnapshot() async throws {
        let suiteName = "workout-contract-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return
        }
        let anchorStore = HealthKitAnchorStore(defaults: defaults, keyPrefix: "contract")
        let persistedAnchor = HKQueryAnchor(fromValue: 99)
        let persistedRecord = AnchorRecord(
            anchorData: try encodedAnchor(persistedAnchor),
            lastSyncDate: Date()
        )
        anchorStore.setWorkoutAnchor(persistedRecord, for: "device")

        let healthStore = MockWorkoutQueryHealthStore(
            samples: [makeWorkout()],
            newAnchor: HKQueryAnchor(fromValue: 101)
        )
        let service = HealthKitService(
            healthStore: healthStore,
            anchorStore: anchorStore,
            deviceIdentifier: "device"
        )

        let before = anchorStore.workoutAnchor(for: "device")
        let result = try await service.fetchWorkouts(dateRange: nil)

        #expect(result.workouts.count == 1)
        #expect(healthStore.receivedAnchors.allSatisfy { $0 == nil })
        #expect(anchorStore.workoutAnchor(for: "device")?.anchorData == before?.anchorData)
        #expect(anchorStore.workoutAnchor(for: "device")?.lastSyncDate == before?.lastSyncDate)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("prepareWorkoutSnapshot creates a pending checkpoint without persisting it until acceptance")
    func prepareWorkoutSnapshotCreatesPendingCheckpoint() async throws {
        let suiteName = "workout-contract-snapshot-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return
        }
        let anchorStore = HealthKitAnchorStore(defaults: defaults, keyPrefix: "contract")
        let healthStore = MockWorkoutQueryHealthStore(
            samples: [makeWorkout()],
            newAnchor: HKQueryAnchor(fromValue: 202)
        )
        let service = HealthKitService(
            healthStore: healthStore,
            anchorStore: anchorStore,
            deviceIdentifier: "device"
        )

        let prepared = try await service.prepareWorkoutSnapshot(dateRange: nil)

        #expect(prepared.source == .baselineSnapshot)
        #expect(prepared.checkpoint != nil)
        #expect(anchorStore.workoutAnchor(for: "device") == nil)

        service.acceptPreparedWorkoutFetch(prepared)
        #expect(anchorStore.workoutAnchor(for: "device") != nil)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("prepareWorkoutChanges reads the persisted workout anchor but does not persist during preparation")
    func prepareWorkoutChangesUsesPersistedAnchor() async throws {
        let suiteName = "workout-contract-anchored-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return
        }
        let anchorStore = HealthKitAnchorStore(defaults: defaults, keyPrefix: "contract")
        let baseAnchor = HKQueryAnchor(fromValue: 42)
        let record = AnchorRecord(
            anchorData: try encodedAnchor(baseAnchor),
            lastSyncDate: Date()
        )
        anchorStore.setWorkoutAnchor(record, for: "device")

        let healthStore = MockWorkoutQueryHealthStore(
            samples: [makeWorkout()],
            newAnchor: HKQueryAnchor(fromValue: 77)
        )
        let service = HealthKitService(
            healthStore: healthStore,
            anchorStore: anchorStore,
            deviceIdentifier: "device"
        )

        let prepared = try await service.prepareWorkoutChanges(anchor: nil)

        #expect(prepared.source == .anchoredChanges)
        #expect(prepared.checkpoint != nil)
        #expect(healthStore.receivedAnchors.last != nil)
        #expect(anchorStore.workoutAnchor(for: "device") != nil)

        service.rejectPreparedWorkoutFetch(prepared)
        #expect(anchorStore.workoutAnchor(for: "device") != nil)

        defaults.removePersistentDomain(forName: suiteName)
    }
}
