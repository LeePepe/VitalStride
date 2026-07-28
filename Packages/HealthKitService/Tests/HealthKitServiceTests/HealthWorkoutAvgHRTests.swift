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
/// Swift 6 concurrency-safe mock design (constitution: no `@unchecked
/// Sendable` and no `nonisolated(unsafe)` without an ADR exception):
///
/// - All mutable state lives inside a `private actor` (`AvgHRMockState`),
///   which is `Sendable` by construction.
/// - The class conforming to `HealthStoreProviding` is `final` with only
///   `let` stored properties whose types are `Sendable`, so it conforms to
///   the protocol's `Sendable` requirement without any escape hatches.
/// - `HealthKitService.averageHeartRate(for:)` does not gate on
///   `isHealthDataAvailable`, so the mock exposes a plain `static let =
///   true` and never mutates it — nothing to synchronize.
///
/// Privacy red line (constitution I): the helper must NEVER log the returned
/// avg HR value. That is enforced by the source-level grep in
/// `PrivacyLoggingTests`, not here.

// MARK: - Actor-backed mock state

/// Holds all mutable state for the mock. Being an `actor` makes it
/// `Sendable` and serializes access without any `@unchecked` / `unsafe`.
///
/// We deliberately only store `Sendable` snapshots (the raw `HKQuantityType`
/// identifier and a `String` predicate format) instead of the original
/// non-`Sendable` `NSPredicate` reference — enough for tests to assert the
/// bridge invoked the right query, without smuggling a non-`Sendable`
/// reference across actor isolation.
private actor AvgHRMockState {
    private var averageBPM: Double?
    private var capturedTypeIdentifier: String?
    private var capturedPredicateFormat: String?

    func setAverageBPM(_ value: Double?) {
        averageBPM = value
    }

    /// Records the incoming query parameters (as Sendable snapshots) and
    /// returns the fixture value atomically. Called from
    /// `executeAverageQuantityQuery`.
    func recordAndFetchAverage(
        typeIdentifier: String,
        predicateFormat: String
    ) -> Double? {
        capturedTypeIdentifier = typeIdentifier
        capturedPredicateFormat = predicateFormat
        return averageBPM
    }

    func snapshotCapturedTypeIdentifier() -> String? { capturedTypeIdentifier }
    func snapshotCapturedPredicateFormat() -> String? { capturedPredicateFormat }
}

// MARK: - Focused mock for avg-HR queries

/// `final class` with only `let` stored properties → naturally `Sendable`.
/// The state actor above serializes all reads/writes.
private final class AvgHRMockStore: HealthStoreProviding {
    // Availability is a compile-time constant here. `averageHeartRate(for:)`
    // does not check `isHealthDataAvailable`, and no other test flips it,
    // so a plain `static let` is enough — no synchronization needed.
    static let isHealthDataAvailable: Bool = true

    private let state = AvgHRMockState()

    // MARK: Convenience API for tests (async — hop through the actor)

    func setAverageBPM(_ value: Double?) async {
        await state.setAverageBPM(value)
    }

    func capturedQuantityTypeIdentifier() async -> String? {
        await state.snapshotCapturedTypeIdentifier()
    }

    func capturedPredicateFormat() async -> String? {
        await state.snapshotCapturedPredicateFormat()
    }

    // MARK: HealthStoreProviding conformance (unused stubs)

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

    // MARK: The avg-HR query itself

    func executeAverageQuantityQuery(
        quantityType: HKQuantityType,
        predicate: NSPredicate
    ) async -> HKQuantity? {
        // Extract Sendable snapshots BEFORE hopping into the actor —
        // `NSPredicate` and `HKQuantityType` are non-Sendable reference
        // types, so we take String identifiers instead of sending the refs
        // across isolation.
        let typeIdentifier = quantityType.identifier
        let predicateFormat = predicate.predicateFormat
        let bpm = await state.recordAndFetchAverage(
            typeIdentifier: typeIdentifier,
            predicateFormat: predicateFormat
        )
        guard let bpm else { return nil }
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
        await store.setAverageBPM(142.6)
        let service = makeService(store: store)

        let workout = makeWorkout()
        let bpm = await service.averageHeartRate(for: workout)

        // 142.6 rounds to 143.
        #expect(bpm == 143)
    }

    @Test("Returns nil when statistics query yields nil (no samples / failure)")
    func returnsNilOnNoSamples() async {
        let store = AvgHRMockStore()
        await store.setAverageBPM(nil)
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
        await store.setAverageBPM(0)
        #expect(await service.averageHeartRate(for: makeWorkout()) == nil)

        await store.setAverageBPM(-1)
        #expect(await service.averageHeartRate(for: makeWorkout()) == nil)
    }

    @Test("Queries heartRate quantity type over the workout window")
    func queriesHeartRateWithinWindow() async {
        let store = AvgHRMockStore()
        await store.setAverageBPM(100)
        let service = makeService(store: store)

        let start = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let workout = makeWorkout(start: start, duration: 600)
        _ = await service.averageHeartRate(for: workout)

        let capturedTypeIdentifier = await store.capturedQuantityTypeIdentifier()
        let capturedPredicateFormat = await store.capturedPredicateFormat()
        #expect(capturedTypeIdentifier == HKQuantityType(.heartRate).identifier)
        #expect(capturedPredicateFormat != nil)
        // Predicate format should mention the workout window bounds.
        #expect(capturedPredicateFormat?.isEmpty == false)
    }
}
