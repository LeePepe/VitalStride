import Foundation
import HealthKit
import Testing
@testable import HealthKitService

private actor MockWorkoutQueryHealthStoreState {
    private let samples: [HKSample]
    private let newAnchorData: Data?
    private var receivedAnchors: [Data?]

    init(samples: [HKSample], newAnchor: HKQueryAnchor? = nil) {
        self.samples = samples
        self.newAnchorData = newAnchor.flatMap { try? encodedAnchor($0) }
        self.receivedAnchors = []
    }

    func record(anchor: HKQueryAnchor?) -> [HKSample] {
        receivedAnchors.append(anchor.flatMap { try? encodedAnchor($0) })
        return samples
    }

    func allReceivedAnchors() -> [HKQueryAnchor?] {
        receivedAnchors.map { data in
            data.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0) }
        }
    }

    func lastReceivedAnchor() -> HKQueryAnchor? {
        receivedAnchors.last.flatMap {
            data in
            data.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0) }
        }
    }

    func currentNewAnchor() -> HKQueryAnchor? {
        newAnchorData.flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
        }
    }
}

private final class MockWorkoutQueryHealthStore: HealthStoreProviding {
    static let isHealthDataAvailable = true

    private let state: MockWorkoutQueryHealthStoreState

    init(samples: [HKSample], newAnchor: HKQueryAnchor? = nil) {
        self.state = MockWorkoutQueryHealthStoreState(samples: samples, newAnchor: newAnchor)
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
        let samples = await state.record(anchor: anchor)
        return AnchoredQueryResult(
            samples: samples,
            deletedObjectUUIDs: [],
            newAnchor: await state.currentNewAnchor()
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

    func lastReceivedAnchor() async -> HKQueryAnchor? {
        await state.lastReceivedAnchor()
    }

    func allReceivedAnchors() async -> [HKQueryAnchor?] {
        await state.allReceivedAnchors()
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

    @Test("checkpoint round-trips without exposing the raw HKQueryAnchor")
    func workoutAnchorCheckpointRoundTrips() throws {
        let anchor = HKQueryAnchor(fromValue: 42)
        let now = Date()
        let checkpoint = WorkoutAnchorCheckpoint(
            source: .baselineSnapshot,
            anchor: anchor,
            lastSyncDate: now
        )
        let expectedAnchorData = try encodedAnchor(anchor)

        let encoded = try JSONEncoder().encode(checkpoint)
        let decoded = try JSONDecoder().decode(WorkoutAnchorCheckpoint.self, from: encoded)

        #expect(decoded.source == checkpoint.source)
        #expect(decoded.lastSyncDate == checkpoint.lastSyncDate)
        #expect(decoded.anchorData == checkpoint.anchorData)
        #expect(decoded.anchorData == expectedAnchorData)
        #expect(decoded.anchor != nil)
    }

    @Test("fetchWorkouts remains anchor-free snapshot and never advances the default workout anchor")
    func fetchWorkoutsRemainsAnchorFreeSnapshot() async throws {
        let suiteName = "workout-contract-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return
        }
        let anchorStore = HealthKitAnchorStore(defaults: defaults, keyPrefix: "contract")
        let persistedAnchor = HKQueryAnchor(fromValue: 99)
        let beforeRecord = AnchorRecord(anchorData: try encodedAnchor(persistedAnchor), lastSyncDate: Date())
        anchorStore.setWorkoutAnchor(beforeRecord, for: "device")

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
        let receivedAnchors = await healthStore.allReceivedAnchors()

        #expect(result.workouts.count == 1)
        #expect(receivedAnchors.allSatisfy { $0 == nil })
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
        let beforePersist = anchorStore.workoutAnchor(for: "device")
        let expectedAnchorData = try encodedAnchor(HKQueryAnchor(fromValue: 202))

        #expect(prepared.source == .baselineSnapshot)
        #expect(prepared.coverage != nil)
        #expect(prepared.checkpoint != nil)
        #expect(prepared.checkpoint?.anchorData == expectedAnchorData)
        #expect(beforePersist == nil)

        service.acceptPreparedWorkoutFetch(prepared)
        let persisted = anchorStore.workoutAnchor(for: "device")
        #expect(persisted != nil)
        #expect(persisted?.anchorData == expectedAnchorData)
        #expect(persisted?.anchorData == prepared.checkpoint?.anchorData)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("prepareWorkoutChanges persists only after explicit acceptance and keeps the prior anchor unchanged on reject")
    func prepareWorkoutChangesPersistsOnlyAfterAcceptance() async throws {
        let suiteName = "workout-contract-anchored-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return
        }
        let anchorStore = HealthKitAnchorStore(defaults: defaults, keyPrefix: "contract")
        let persistedAnchor = HKQueryAnchor(fromValue: 42)
        let existingRecord = AnchorRecord(anchorData: try encodedAnchor(persistedAnchor), lastSyncDate: Date())
        anchorStore.setWorkoutAnchor(existingRecord, for: "device")

        let healthStore = MockWorkoutQueryHealthStore(
            samples: [makeWorkout()],
            newAnchor: HKQueryAnchor(fromValue: 77)
        )
        let service = HealthKitService(
            healthStore: healthStore,
            anchorStore: anchorStore,
            deviceIdentifier: "device"
        )

        let beforePrepare = anchorStore.workoutAnchor(for: "device")
        let prepared = try await service.prepareWorkoutChanges(anchor: nil)
        let lastAnchor = await healthStore.lastReceivedAnchor()
        let expectedAnchorData = try encodedAnchor(HKQueryAnchor(fromValue: 77))

        #expect(prepared.source == .anchoredChanges)
        #expect(prepared.checkpoint != nil)
        #expect(prepared.checkpoint?.anchorData == expectedAnchorData)
        #expect(lastAnchor != nil)
        #expect(anchorStore.workoutAnchor(for: "device")?.anchorData == beforePrepare?.anchorData)
        #expect(anchorStore.workoutAnchor(for: "device")?.lastSyncDate == beforePrepare?.lastSyncDate)

        service.rejectPreparedWorkoutFetch(prepared)
        #expect(anchorStore.workoutAnchor(for: "device")?.anchorData == beforePrepare?.anchorData)
        #expect(anchorStore.workoutAnchor(for: "device")?.lastSyncDate == beforePrepare?.lastSyncDate)

        service.acceptPreparedWorkoutFetch(prepared)
        let accepted = anchorStore.workoutAnchor(for: "device")
        #expect(accepted != nil)
        #expect(accepted?.anchorData == expectedAnchorData)
        #expect(accepted?.lastSyncDate != nil)

        let persisted = anchorStore.workoutAnchor(for: "device")
        #expect(persisted?.anchorData == expectedAnchorData)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("explicit-range snapshots do not create a default checkpoint or advance the stored default anchor")
    func explicitRangeSnapshotDoesNotAdvanceDefaultAnchor() async throws {
        let suiteName = "workout-contract-explicit-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return
        }
        let anchorStore = HealthKitAnchorStore(defaults: defaults, keyPrefix: "contract")
        let persistedAnchor = HKQueryAnchor(fromValue: 14)
        let priorRecord = AnchorRecord(anchorData: try encodedAnchor(persistedAnchor), lastSyncDate: Date())
        anchorStore.setWorkoutAnchor(priorRecord, for: "device")

        let healthStore = MockWorkoutQueryHealthStore(
            samples: [makeWorkout()],
            newAnchor: HKQueryAnchor(fromValue: 77)
        )
        let service = HealthKitService(
            healthStore: healthStore,
            anchorStore: anchorStore,
            deviceIdentifier: "device"
        )

        let range = DateInterval(
            start: Date().addingTimeInterval(-3 * 24 * 60 * 60),
            end: Date().addingTimeInterval(-1 * 60)
        )

        let prepared = try await service.prepareWorkoutSnapshot(dateRange: range)
        let receivedAnchors = await healthStore.allReceivedAnchors()

        #expect(prepared.source == .explicitRangeSnapshot)
        #expect(prepared.coverage == range)
        #expect(prepared.checkpoint == nil)
        #expect(receivedAnchors.allSatisfy { $0 == nil })
        #expect(anchorStore.workoutAnchor(for: "device")?.anchorData == priorRecord.anchorData)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("prepareWorkoutChanges falls back to baseline when there is no persisted anchor")
    func prepareWorkoutChangesWithoutPersistedAnchorFallsBackToBaselineSnapshot() async throws {
        let suiteName = "workout-contract-no-anchor-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return
        }
        let anchorStore = HealthKitAnchorStore(defaults: defaults, keyPrefix: "contract")
        let healthStore = await MockWorkoutQueryHealthStore(
            samples: [makeWorkout()],
            newAnchor: HKQueryAnchor(fromValue: 13)
        )
        let service = HealthKitService(
            healthStore: healthStore,
            anchorStore: anchorStore,
            deviceIdentifier: "device"
        )

        let prepared = try await service.prepareWorkoutChanges(anchor: nil)

        #expect(prepared.source == .baselineSnapshot)
        #expect(prepared.checkpoint != nil)
        #expect(anchorStore.workoutAnchor(for: "device") == nil)

        defaults.removePersistentDomain(forName: suiteName)
    }
}
