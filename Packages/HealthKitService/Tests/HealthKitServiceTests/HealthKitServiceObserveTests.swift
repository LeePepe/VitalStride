import Testing
import Foundation
import HealthKit
@testable import HealthKitService

// MARK: - MockHealthStore

final class MockHealthStore: HealthStoreProviding, @unchecked Sendable {
    nonisolated(unsafe) static var isHealthDataAvailable: Bool = true

    var authorizationRequestStatus: HKAuthorizationRequestStatus = .unnecessary
    var authorizationError: (any Error)?
    var anchoredQueryResult: AnchoredQueryResult = AnchoredQueryResult(
        samples: [], deletedObjectUUIDs: [], newAnchor: nil
    )
    private let lock = NSLock()
    private var _observerStreamContinuation: AsyncStream<AnchoredQueryResult>.Continuation?
    private var _stopQueryCallCount = 0

    var stopQueryCallCount: Int {
        lock.withLock { _stopQueryCallCount }
    }

    func requestAuthorization(
        toShare typesToShare: Set<HKSampleType>,
        read typesToRead: Set<HKObjectType>
    ) async throws {}

    func statusForAuthorizationRequest(
        toShare typesToShare: Set<HKSampleType>,
        read typesToRead: Set<HKObjectType>
    ) async throws -> HKAuthorizationRequestStatus {
        if let error = authorizationError {
            throw error
        }
        return authorizationRequestStatus
    }

    func executeAnchoredQuery(
        type: HKSampleType,
        predicate: NSPredicate?,
        anchor: HKQueryAnchor?,
        limit: Int
    ) async throws -> AnchoredQueryResult {
        anchoredQueryResult
    }

    func executeObserverAnchoredQuery(
        type: HKSampleType,
        predicate: NSPredicate?,
        anchor: HKQueryAnchor?,
        limit: Int
    ) -> AsyncStream<AnchoredQueryResult> {
        AsyncStream { continuation in
            lock.withLock {
                self._observerStreamContinuation = continuation
            }
        }
    }

    func stopQuery(_ query: HKQuery) {
        lock.withLock { _stopQueryCallCount += 1 }
    }

    func yieldSamples(_ result: AnchoredQueryResult) {
        lock.withLock {
            _ = _observerStreamContinuation?.yield(result)
        }
    }

    func finishObserverStream() {
        lock.withLock {
            _observerStreamContinuation?.finish()
            _observerStreamContinuation = nil
        }
    }
}

// MARK: - Helpers

private func makeService(
    healthStore: MockHealthStore = MockHealthStore()
) -> (HealthKitService, MockHealthStore) {
    let service = HealthKitService(
        healthStore: healthStore,
        deviceIdentifier: "test-device"
    )
    return (service, healthStore)
}

private func makeHeartRateSample(
    value: Double = 72.0,
    date: Date = Date()
) -> HKQuantitySample {
    let unit = HKUnit.count().unitDivided(by: .minute())
    let quantity = HKQuantity(unit: unit, doubleValue: value)
    return HKQuantitySample(
        type: HKQuantityType(.heartRate),
        quantity: quantity,
        start: date,
        end: date.addingTimeInterval(1)
    )
}

// MARK: - Tests

@Suite("HealthKitService.observeHeartRate")
struct HealthKitServiceObserveTests {

    @Test("Stream yields heart rate data points from observer query")
    func observeYieldsDataPoints() async throws {
        let mock = MockHealthStore()
        let (service, _) = makeService(healthStore: mock)

        let stream = service.observeHeartRate()

        let consumeTask = Task { () -> [HealthDataPoint] in
            var result: [HealthDataPoint] = []
            for await dataPoint in stream {
                result.append(dataPoint)
                if result.count >= 3 { break }
            }
            return result
        }

        try await Task.sleep(for: .milliseconds(50))

        let sample1 = makeHeartRateSample(value: 70.0)
        let sample2 = makeHeartRateSample(value: 75.0)
        mock.yieldSamples(AnchoredQueryResult(
            samples: [sample1, sample2], deletedObjectUUIDs: [], newAnchor: nil
        ))

        try await Task.sleep(for: .milliseconds(50))

        let sample3 = makeHeartRateSample(value: 80.0)
        mock.yieldSamples(AnchoredQueryResult(
            samples: [sample3], deletedObjectUUIDs: [], newAnchor: nil
        ))

        let collected = await consumeTask.value

        #expect(collected.count == 3)
        #expect(collected[0].sampleType == .heartRate)
        #expect(collected[0].value == 70.0)
        #expect(collected[0].unit == "bpm")
        #expect(collected[1].value == 75.0)
        #expect(collected[2].value == 80.0)
    }

    @Test("Stream finishes when Task is cancelled")
    func observeStopsOnTaskCancel() async throws {
        let mock = MockHealthStore()
        let (service, _) = makeService(healthStore: mock)

        let stream = service.observeHeartRate()

        let consumeTask = Task { () -> [HealthDataPoint] in
            var result: [HealthDataPoint] = []
            for await dataPoint in stream {
                result.append(dataPoint)
            }
            return result
        }

        try await Task.sleep(for: .milliseconds(50))

        let sample = makeHeartRateSample(value: 72.0)
        mock.yieldSamples(AnchoredQueryResult(
            samples: [sample], deletedObjectUUIDs: [], newAnchor: nil
        ))

        try await Task.sleep(for: .milliseconds(50))

        consumeTask.cancel()
        let collected = await consumeTask.value

        #expect(collected.count == 1)
    }

    @Test("Stream finishes immediately when HealthKit is unavailable")
    func observeFinishesWhenUnavailable() async throws {
        let mock = MockHealthStore()
        MockHealthStore.isHealthDataAvailable = false
        defer { MockHealthStore.isHealthDataAvailable = true }

        let (service, _) = makeService(healthStore: mock)
        let stream = service.observeHeartRate()

        var collected: [HealthDataPoint] = []
        for await dataPoint in stream {
            collected.append(dataPoint)
        }

        #expect(collected.isEmpty)
    }

    @Test("Stream finishes immediately when authorization not granted")
    func observeFinishesWhenNotAuthorized() async throws {
        let mock = MockHealthStore()
        mock.authorizationRequestStatus = .shouldRequest
        let (service, _) = makeService(healthStore: mock)

        let stream = service.observeHeartRate()

        var collected: [HealthDataPoint] = []
        for await dataPoint in stream {
            collected.append(dataPoint)
        }

        #expect(collected.isEmpty)
    }

    @Test("Stream finishes when authorization check throws")
    func observeFinishesOnAuthorizationError() async throws {
        let mock = MockHealthStore()
        mock.authorizationError = HealthKitServiceError.healthDataNotAvailable
        let (service, _) = makeService(healthStore: mock)

        let stream = service.observeHeartRate()

        var collected: [HealthDataPoint] = []
        for await dataPoint in stream {
            collected.append(dataPoint)
        }

        #expect(collected.isEmpty)
    }

    @Test("Stream finishes when observer stream ends naturally")
    func observeFinishesOnStreamEnd() async throws {
        let mock = MockHealthStore()
        let (service, _) = makeService(healthStore: mock)

        let stream = service.observeHeartRate()

        let consumeTask = Task { () -> [HealthDataPoint] in
            var result: [HealthDataPoint] = []
            for await dataPoint in stream {
                result.append(dataPoint)
            }
            return result
        }

        try await Task.sleep(for: .milliseconds(50))

        let sample = makeHeartRateSample(value: 72.0)
        mock.yieldSamples(AnchoredQueryResult(
            samples: [sample], deletedObjectUUIDs: [], newAnchor: nil
        ))

        try await Task.sleep(for: .milliseconds(50))
        mock.finishObserverStream()

        let collected = await consumeTask.value

        #expect(collected.count == 1)
        #expect(collected[0].value == 72.0)
    }

    @Test("Empty sample batches do not yield data points")
    func observeSkipsEmptyBatches() async throws {
        let mock = MockHealthStore()
        let (service, _) = makeService(healthStore: mock)

        let stream = service.observeHeartRate()

        let consumeTask = Task { () -> [HealthDataPoint] in
            var result: [HealthDataPoint] = []
            for await dataPoint in stream {
                result.append(dataPoint)
            }
            return result
        }

        try await Task.sleep(for: .milliseconds(50))

        mock.yieldSamples(AnchoredQueryResult(
            samples: [], deletedObjectUUIDs: [], newAnchor: nil
        ))

        try await Task.sleep(for: .milliseconds(50))

        let sample = makeHeartRateSample(value: 72.0)
        mock.yieldSamples(AnchoredQueryResult(
            samples: [sample], deletedObjectUUIDs: [], newAnchor: nil
        ))

        try await Task.sleep(for: .milliseconds(50))
        mock.finishObserverStream()

        let collected = await consumeTask.value

        #expect(collected.count == 1)
        #expect(collected[0].value == 72.0)
    }
}
