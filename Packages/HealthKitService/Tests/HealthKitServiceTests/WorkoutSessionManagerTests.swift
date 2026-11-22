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

    func startSession() async throws {
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
    func noopStartIsNoop() async throws {
        let noop = NoopWorkoutSessionManager()
        try await noop.startSession()
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
    func mockTracksStart() async throws {
        let mock = MockWorkoutSessionManager()
        #expect(mock.startCallCount == 0)

        try await mock.startSession()
        #expect(mock.startCallCount == 1)

        try await mock.startSession()
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
    func multipleEndCallsTracked() async throws {
        let mock = MockWorkoutSessionManager()
        try await mock.startSession()

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

    func executeSampleQuery(
        type: HKSampleType,
        predicate: NSPredicate?,
        limit: Int
    ) async throws -> [HKSample] { [] }

    func delete(_ objects: [HKObject]) async throws {}
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

@Suite("HealthKitService.saveStrengthWorkout & startWatchApp")
struct SaveStrengthWorkoutTests {

    @Test("saveStrengthWorkout returns saved workout UUID when authorized")
    func saveStrengthWorkoutSuccess() async {
        let mock = SaveWorkoutMockStore(
            authStatus: .sharingAuthorized,
            stubbedUUID: "SAVED-HK-UUID-999"
        )
        let service = HealthKitService(
            healthStore: mock,
            deviceIdentifier: "test-device"
        )
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(1800)

        let uuid = await service.saveStrengthWorkout(startDate: start, endDate: end)

        #expect(uuid == "SAVED-HK-UUID-999")
        #expect(mock.savedStartDate == start)
        #expect(mock.savedEndDate == end)
    }

    @Test("saveStrengthWorkout requests authorization when status is notDetermined and succeeds after grant")
    func saveStrengthWorkoutRequestsAuthWhenNotDetermined() async {
        let mock = SaveWorkoutMockStore(
            authStatus: .notDetermined,
            authStatusAfterRequest: .sharingAuthorized,
            stubbedUUID: "AFTER-AUTH-UUID"
        )
        let service = HealthKitService(
            healthStore: mock,
            deviceIdentifier: "test-device"
        )
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(600)

        let uuid = await service.saveStrengthWorkout(startDate: start, endDate: end)

        #expect(uuid == "AFTER-AUTH-UUID")
        #expect(mock.requestAuthCalled == true)
    }

    @Test("saveStrengthWorkout returns nil when sharingDenied without calling builder")
    func saveStrengthWorkoutDeniedReturnsNil() async {
        let mock = SaveWorkoutMockStore(
            authStatus: .sharingDenied,
            stubbedUUID: "SHOULD-NOT-SAVE"
        )
        let service = HealthKitService(
            healthStore: mock,
            deviceIdentifier: "test-device"
        )
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(600)

        let uuid = await service.saveStrengthWorkout(startDate: start, endDate: end)

        #expect(uuid == nil)
        #expect(mock.savedStartDate == nil)
    }

    @Test("saveStrengthWorkout clamps endDate when endDate < startDate")
    func saveStrengthWorkoutClampsInvertedDates() async {
        let mock = SaveWorkoutMockStore(
            authStatus: .sharingAuthorized,
            stubbedUUID: "CLAMPED-UUID"
        )
        let service = HealthKitService(
            healthStore: mock,
            deviceIdentifier: "test-device"
        )
        let start = Date(timeIntervalSince1970: 1_700_000_500)
        let end = Date(timeIntervalSince1970: 1_700_000_100)

        let uuid = await service.saveStrengthWorkout(startDate: start, endDate: end)

        #expect(uuid == "CLAMPED-UUID")
        #expect(mock.savedStartDate == start)
        #expect(mock.savedEndDate == start)
    }

    @Test("startWatchAppForStrengthWorkout invokes store with traditionalStrengthTraining")
    func startWatchAppInvokesStore() async {
        let mock = SaveWorkoutMockStore(
            authStatus: .sharingAuthorized,
            stubbedUUID: nil
        )
        let service = HealthKitService(
            healthStore: mock,
            deviceIdentifier: "test-device"
        )

        await service.startWatchAppForStrengthWorkout()

        #expect(mock.startedWatchActivityType == .traditionalStrengthTraining)
    }

    @Test("WorkoutSessionManaging default watchToPhoneSender is NoopWatchToPhoneSender")
    func defaultWatchToPhoneSenderIsNoop() {
        let noop = NoopWorkoutSessionManager()
        #expect(noop.watchToPhoneSender is NoopWatchToPhoneSender)
    }
}

private final class SaveWorkoutMockStore: HealthStoreProviding, @unchecked Sendable {
    nonisolated(unsafe) static var isHealthDataAvailable: Bool = true
    private let lock = NSLock()
    private var _authStatus: HKAuthorizationStatus
    private let _authStatusAfterRequest: HKAuthorizationStatus?
    private let _stubbedUUID: String?
    private var _requestAuthCalled = false
    private var _savedStartDate: Date?
    private var _savedEndDate: Date?
    private var _startedWatchActivityType: HKWorkoutActivityType?

    init(
        authStatus: HKAuthorizationStatus,
        authStatusAfterRequest: HKAuthorizationStatus? = nil,
        stubbedUUID: String?
    ) {
        self._authStatus = authStatus
        self._authStatusAfterRequest = authStatusAfterRequest
        self._stubbedUUID = stubbedUUID
    }

    var requestAuthCalled: Bool { lock.withLock { _requestAuthCalled } }
    var savedStartDate: Date? { lock.withLock { _savedStartDate } }
    var savedEndDate: Date? { lock.withLock { _savedEndDate } }
    var startedWatchActivityType: HKWorkoutActivityType? { lock.withLock { _startedWatchActivityType } }

    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
        lock.withLock { _authStatus }
    }

    func requestAuthorization(
        toShare typesToShare: Set<HKSampleType>,
        read typesToRead: Set<HKObjectType>
    ) async throws {
        lock.withLock {
            _requestAuthCalled = true
            if let next = _authStatusAfterRequest {
                _authStatus = next
            }
        }
    }

    func statusForAuthorizationRequest(
        toShare typesToShare: Set<HKSampleType>,
        read typesToRead: Set<HKObjectType>
    ) async throws -> HKAuthorizationRequestStatus {
        .unnecessary
    }

    func saveStrengthWorkout(startDate: Date, endDate: Date) async throws -> String? {
        lock.withLock {
            _savedStartDate = startDate
            _savedEndDate = endDate
            return _stubbedUUID
        }
    }

    func startWatchApp(with workoutConfiguration: HKWorkoutConfiguration) async throws {
        lock.withLock {
            _startedWatchActivityType = workoutConfiguration.activityType
        }
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

    func executeSampleQuery(
        type: HKSampleType,
        predicate: NSPredicate?,
        limit: Int
    ) async throws -> [HKSample] { [] }

    func delete(_ objects: [HKObject]) async throws {}
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

    func executeSampleQuery(
        type: HKSampleType,
        predicate: NSPredicate?,
        limit: Int
    ) async throws -> [HKSample] { [] }

    func delete(_ objects: [HKObject]) async throws {}
}
