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
    private let terminationLock = NSLock()
    private var _observerStreamContinuation: AsyncStream<AnchoredQueryResult>.Continuation?
    private var _stopQueryCallCount = 0
    private var _observerStreamTerminationCount = 0
    private var _lastObserverPredicate: NSPredicate?

    var stopQueryCallCount: Int {
        lock.withLock { _stopQueryCallCount }
    }

    var observerStreamTerminationCount: Int {
        terminationLock.withLock { _observerStreamTerminationCount }
    }

    var lastObserverPredicate: NSPredicate? {
        lock.withLock { _lastObserverPredicate }
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
        lock.withLock { _lastObserverPredicate = predicate }
        return AsyncStream { continuation in
            lock.withLock {
                self._observerStreamContinuation = continuation
            }
            continuation.onTermination = { [weak self] _ in
                self?.terminationLock.withLock { self?._observerStreamTerminationCount += 1 }
            }
        }
    }

    func stopQuery(_ query: HKQuery) {
        lock.withLock { _stopQueryCallCount += 1 }
    }

    func executeSampleQuery(
        type: HKSampleType,
        predicate: NSPredicate?,
        limit: Int
    ) async throws -> [HKSample] {
        []
    }

    func delete(_ objects: [HKObject]) async throws {}

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

    func waitForObserverStreamReady() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline {
            if lock.withLock({ _observerStreamContinuation != nil }) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Observer stream continuation was not set within timeout")
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

@Suite("HealthKitService.observeHeartRate", .serialized)
struct HealthKitServiceObserveTests {

    @Test("Stream yields only the latest heart rate per batch")
    func observeYieldsLatestPerBatch() async throws {
        let mock = MockHealthStore()
        let (service, _) = makeService(healthStore: mock)

        let stream = service.observeHeartRate()

        let consumeTask = Task { () -> [HealthDataPoint] in
            var result: [HealthDataPoint] = []
            for await dataPoint in stream {
                result.append(dataPoint)
                if result.count >= 2 { break }
            }
            return result
        }

        try await mock.waitForObserverStreamReady()

        let now = Date()
        let sample1 = makeHeartRateSample(value: 70.0, date: now.addingTimeInterval(-10))
        let sample2 = makeHeartRateSample(value: 75.0, date: now)
        mock.yieldSamples(AnchoredQueryResult(
            samples: [sample1, sample2], deletedObjectUUIDs: [], newAnchor: nil
        ))

        let sample3 = makeHeartRateSample(value: 80.0, date: now.addingTimeInterval(1))
        mock.yieldSamples(AnchoredQueryResult(
            samples: [sample3], deletedObjectUUIDs: [], newAnchor: nil
        ))

        let collected = await consumeTask.value

        #expect(collected.count == 2)
        #expect(collected[0].sampleType == .heartRate)
        #expect(collected[0].value == 75.0)
        #expect(collected[0].unit == "bpm")
        #expect(collected[1].value == 80.0)
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

        try await mock.waitForObserverStreamReady()

        let sample = makeHeartRateSample(value: 72.0)
        mock.yieldSamples(AnchoredQueryResult(
            samples: [sample], deletedObjectUUIDs: [], newAnchor: nil
        ))

        try await Task.sleep(for: .milliseconds(50))

        consumeTask.cancel()
        let collected = await consumeTask.value

        #expect(collected.count == 1)

        try await Task.sleep(for: .milliseconds(100))
        #expect(mock.observerStreamTerminationCount == 1)
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

        try await mock.waitForObserverStreamReady()

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

        try await mock.waitForObserverStreamReady()

        mock.yieldSamples(AnchoredQueryResult(
            samples: [], deletedObjectUUIDs: [], newAnchor: nil
        ))

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

    @Test("Observer query uses a time predicate that filters old samples")
    func observeUsesTimePredicate() async throws {
        let mock = MockHealthStore()
        let (service, _) = makeService(healthStore: mock)

        let stream = service.observeHeartRate()

        let consumeTask = Task {
            for await _ in stream { break }
        }

        try await mock.waitForObserverStreamReady()

        let predicate = mock.lastObserverPredicate
        #expect(predicate != nil)

        let recentSample = makeHeartRateSample(value: 72.0, date: Date().addingTimeInterval(-60))
        let oldSample = makeHeartRateSample(value: 72.0, date: Date().addingTimeInterval(-600))
        #expect(predicate!.evaluate(with: recentSample) == true)
        #expect(predicate!.evaluate(with: oldSample) == false)

        mock.finishObserverStream()
        await consumeTask.value
    }

    @Test("Batch with mixed timestamps yields only the latest sample")
    func observeYieldsLatestFromMixedBatch() async throws {
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

        try await mock.waitForObserverStreamReady()

        let now = Date()
        let old = makeHeartRateSample(value: 60.0, date: now.addingTimeInterval(-30))
        let mid = makeHeartRateSample(value: 70.0, date: now.addingTimeInterval(-10))
        let recent = makeHeartRateSample(value: 85.0, date: now)
        mock.yieldSamples(AnchoredQueryResult(
            samples: [old, mid, recent], deletedObjectUUIDs: [], newAnchor: nil
        ))

        try await Task.sleep(for: .milliseconds(50))
        mock.finishObserverStream()

        let collected = await consumeTask.value

        #expect(collected.count == 1)
        #expect(collected[0].value == 85.0)
    }
}

@Suite("HealthKitService.probeReadAccess", .serialized)
struct HealthKitServiceProbeReadAccessTests {

    @Test("Successful empty query still indicates read access")
    func successfulEmptyQueryIndicatesReadAccess() async {
        let mock = MockHealthStore()
        mock.anchoredQueryResult = AnchoredQueryResult(samples: [], deletedObjectUUIDs: [], newAnchor: nil)
        let (service, _) = makeService(healthStore: mock)

        let hasAccess = await service.probeReadAccess(for: [.stepCount])

        #expect(hasAccess == true)
    }
}
