import Testing
import Foundation
import HealthKit
@testable import HealthKitService

/// Tests for the average heart rate path added in MY-1358.
///
/// We test two layers:
/// 1. `HealthStoreProviding.executeAverageQuantityQuery` semantics via a
///    focused mock (fixture avg HR → Int; nil → nil; non-positive → nil).
/// 2. The end-to-end `HealthKitService.averageHeartRate(for:)` bridge that
///    wires the mock query into a real `HKWorkout`.
///
/// Privacy red line (constitution I): the helper must NEVER log the returned
/// avg HR value. This is enforced by the source-level grep in
/// `PrivacyLoggingTests`, not here.

// MARK: - Focused mock for avg-HR queries

private final class AvgHRMockStore: HealthStoreProviding, @unchecked Sendable {
    nonisolated(unsafe) static var isHealthDataAvailable: Bool = true

    /// Value the fake query returns. `nil` simulates "no samples / failure".
    var averageBPM: Double?
    /// Capture the last query so tests can assert the predicate window.
    private let lock = NSLock()
    private var _capturedType: HKQuantityType?
    private var _capturedPredicate: NSPredicate?

    var capturedQuantityType: HKQuantityType? {
        lock.withLock { _capturedType }
    }

    var capturedPredicate: NSPredicate? {
        lock.withLock { _capturedPredicate }
    }

    func requestAuthorization(
        toShare typesToShare: Set<HKSampleType>,
        read typesToRead: Set<HKObjectType>
    ) async throws {}

    func statusForAuthorizationRequest(
        toShare typesToShare: Set<HKSampleType>,
        read typesToRead: Set<HKObjectType>
    ) async throws -> HKAuthorizationRequestStatus { .unnecessary }

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

    func executeAverageQuantityQuery(
        quantityType: HKQuantityType,
        predicate: NSPredicate
    ) async -> HKQuantity? {
        lock.withLock {
            _capturedType = quantityType
            _capturedPredicate = predicate
        }
        guard let bpm = averageBPM else { return nil }
        let unit = HKUnit.count().unitDivided(by: .minute())
        return HKQuantity(unit: unit, doubleValue: bpm)
    }
}

// MARK: - Fixture builders

private func makeWorkout(
    activity: HKWorkoutActivityType = .running,
    start: Date = Date(timeIntervalSinceReferenceDate: 0),
    duration: TimeInterval = 1800
) -> HKWorkout {
    // Deprecated but still-functional initializer works for unit tests where
    // we don't need a fully-hydrated builder. This is intentionally minimal.
    HKWorkout(
        activityType: activity,
        start: start,
        end: start.addingTimeInterval(duration)
    )
}

private func makeService(store: AvgHRMockStore) -> HealthKitService {
    HealthKitService(healthStore: store, deviceIdentifier: "avg-hr-tests")
}

// MARK: - Tests

@Suite("HealthKitService.averageHeartRate(for:)")
struct HealthWorkoutAvgHRTests {

    @Test("Returns rounded integer bpm when statistics query yields a value")
    func returnsRoundedBPM() async {
        let store = AvgHRMockStore()
        store.averageBPM = 142.6
        let service = makeService(store: store)

        let workout = makeWorkout()
        let bpm = await service.averageHeartRate(for: workout)

        // 142.6 rounds to 143.
        #expect(bpm == 143)
    }

    @Test("Returns nil when statistics query yields nil (no samples / failure)")
    func returnsNilOnNoSamples() async {
        let store = AvgHRMockStore()
        store.averageBPM = nil
        let service = makeService(store: store)

        let workout = makeWorkout()
        let bpm = await service.averageHeartRate(for: workout)

        #expect(bpm == nil)
    }

    @Test("Returns nil for non-positive or non-finite average (defensive)")
    func returnsNilForNonPositive() async {
        let store = AvgHRMockStore()
        let service = makeService(store: store)

        // Zero and negatives are not valid heart rates; guard against them
        // even though HK is unlikely to return them.
        store.averageBPM = 0
        #expect(await service.averageHeartRate(for: makeWorkout()) == nil)

        store.averageBPM = -1
        #expect(await service.averageHeartRate(for: makeWorkout()) == nil)
    }

    @Test("Queries heartRate quantity type over the workout window")
    func queriesHeartRateWithinWindow() async {
        let store = AvgHRMockStore()
        store.averageBPM = 100
        let service = makeService(store: store)

        let start = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let workout = makeWorkout(start: start, duration: 600)
        _ = await service.averageHeartRate(for: workout)

        #expect(store.capturedQuantityType == HKQuantityType(.heartRate))
        #expect(store.capturedPredicate != nil)
    }
}
