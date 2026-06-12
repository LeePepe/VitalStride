import Testing
import Foundation
@testable import HealthKitService

// MARK: - MockWorkoutSessionManager

final class MockWorkoutSessionManager: WorkoutSessionManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var _startCallCount = 0
    private var _endCalls: [(save: Bool, date: Date)] = []
    var startShouldDelay: Duration?
    var stubbedUUID: String? = "MOCK-UUID-1234"

    var startCallCount: Int {
        lock.withLock { _startCallCount }
    }

    var endCallCount: Int {
        lock.withLock { _endCalls.count }
    }

    var lastEndSaveValue: Bool? {
        lock.withLock { _endCalls.last?.save }
    }

    func startSession() async {
        if let delay = startShouldDelay {
            try? await Task.sleep(for: delay)
        }
        lock.withLock { _startCallCount += 1 }
    }

    func endSession(save: Bool) async -> String? {
        lock.withLock { _endCalls.append((save: save, date: Date())) }
        return save ? stubbedUUID : nil
    }
}

// MARK: - Tests

@Suite("WorkoutSessionManaging protocol", .serialized)
struct WorkoutSessionManagingTests {

    @Test("NoopWorkoutSessionManager start does nothing")
    func noopStartIsNoop() async {
        let noop = NoopWorkoutSessionManager()
        await noop.startSession()
    }

    @Test("NoopWorkoutSessionManager end does nothing")
    func noopEndIsNoop() async {
        let noop = NoopWorkoutSessionManager()
        let uuid1 = await noop.endSession(save: true)
        let uuid2 = await noop.endSession(save: false)
        #expect(uuid1 == nil)
        #expect(uuid2 == nil)
    }

    @Test("MockWorkoutSessionManager tracks start calls")
    func mockTracksStart() async {
        let mock = MockWorkoutSessionManager()
        #expect(mock.startCallCount == 0)

        await mock.startSession()
        #expect(mock.startCallCount == 1)

        await mock.startSession()
        #expect(mock.startCallCount == 2)
    }

    @Test("MockWorkoutSessionManager tracks end calls with save flag")
    func mockTracksEnd() async {
        let mock = MockWorkoutSessionManager()
        #expect(mock.endCallCount == 0)

        await mock.endSession(save: true)
        #expect(mock.endCallCount == 1)
        #expect(mock.lastEndSaveValue == true)

        await mock.endSession(save: false)
        #expect(mock.endCallCount == 2)
        #expect(mock.lastEndSaveValue == false)
    }

    @Test("End without start is safe")
    func endWithoutStartIsSafe() async {
        let mock = MockWorkoutSessionManager()
        await mock.endSession(save: true)
        #expect(mock.endCallCount == 1)
    }

    @Test("Multiple rapid end calls are all tracked")
    func multipleEndCallsTracked() async {
        let mock = MockWorkoutSessionManager()
        await mock.startSession()

        await mock.endSession(save: true)
        await mock.endSession(save: false)
        await mock.endSession(save: true)

        #expect(mock.endCallCount == 3)
    }

    @Test("endSession(save: true) returns UUID")
    func endSessionSaveReturnsUUID() async {
        let mock = MockWorkoutSessionManager()
        let uuid = await mock.endSession(save: true)
        #expect(uuid == "MOCK-UUID-1234")
    }

    @Test("endSession(save: false) returns nil")
    func endSessionDiscardReturnsNil() async {
        let mock = MockWorkoutSessionManager()
        let uuid = await mock.endSession(save: false)
        #expect(uuid == nil)
    }
}

@Suite("HealthKitService.makeWorkoutSessionManager")
struct WorkoutSessionFactoryTests {

    @Test("Factory returns NoopWorkoutSessionManager for mock health store")
    func factoryReturnsNoopForMock() {
        let mockStore = MockFactoryHealthStore()
        let service = HealthKitService(
            healthStore: mockStore,
            deviceIdentifier: "test-device"
        )

        let manager = service.makeWorkoutSessionManager()
        #expect(manager is NoopWorkoutSessionManager)
    }
}

// MARK: - Minimal mock for factory test

private final class MockFactoryHealthStore: HealthStoreProviding, @unchecked Sendable {
    nonisolated(unsafe) static var isHealthDataAvailable: Bool = true

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
        AnchoredQueryResult(samples: [], deletedObjectUUIDs: [], newAnchor: nil)
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

import HealthKit

@Suite("HealthKitService.requestAuthorization includes write types")
struct AuthorizationWriteTypeTests {

    @Test("requestAuthorization passes writeTypes to toShare")
    func authIncludesWriteTypes() async throws {
        let mock = AuthCaptureMockStore()
        let service = HealthKitService(
            healthStore: mock,
            deviceIdentifier: "test-device"
        )

        try await service.requestAuthorization()

        let captured = mock.capturedShareTypes
        #expect(captured.contains(HKWorkoutType.workoutType()))
    }

    @Test("authorizationStatus passes writeTypes to toShare")
    func statusIncludesWriteTypes() async throws {
        let mock = AuthCaptureMockStore()
        let service = HealthKitService(
            healthStore: mock,
            deviceIdentifier: "test-device"
        )

        _ = try await service.authorizationStatus()

        let captured = mock.capturedStatusShareTypes
        #expect(captured.contains(HKWorkoutType.workoutType()))
    }
}

private final class AuthCaptureMockStore: HealthStoreProviding, @unchecked Sendable {
    nonisolated(unsafe) static var isHealthDataAvailable: Bool = true
    private let lock = NSLock()
    private var _capturedShareTypes: Set<HKSampleType> = []
    private var _capturedStatusShareTypes: Set<HKSampleType> = []

    var capturedShareTypes: Set<HKSampleType> {
        lock.withLock { _capturedShareTypes }
    }

    var capturedStatusShareTypes: Set<HKSampleType> {
        lock.withLock { _capturedStatusShareTypes }
    }

    func requestAuthorization(
        toShare typesToShare: Set<HKSampleType>,
        read typesToRead: Set<HKObjectType>
    ) async throws {
        lock.withLock { _capturedShareTypes = typesToShare }
    }

    func statusForAuthorizationRequest(
        toShare typesToShare: Set<HKSampleType>,
        read typesToRead: Set<HKObjectType>
    ) async throws -> HKAuthorizationRequestStatus {
        lock.withLock { _capturedStatusShareTypes = typesToShare }
        return .unnecessary
    }

    func executeAnchoredQuery(
        type: HKSampleType,
        predicate: NSPredicate?,
        anchor: HKQueryAnchor?,
        limit: Int
    ) async throws -> AnchoredQueryResult {
        AnchoredQueryResult(samples: [], deletedObjectUUIDs: [], newAnchor: nil)
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
