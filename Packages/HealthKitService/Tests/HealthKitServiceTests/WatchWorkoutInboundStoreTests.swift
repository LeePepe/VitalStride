import Testing
import Foundation
@testable import HealthKitService

// MARK: - WatchWorkoutInboundStore (MY-1288)
//
// Watch-side inbound stream tests. Exercised platform-neutrally so we can
// verify decode + fan-out + latest-wins semantics without a real WCSession.

// MARK: Fixtures

private enum Fixture {
    static func snapshot(setCount: Int = 2, completed: Int = 0) -> WorkoutStateSnapshot {
        let sets = (0..<setCount).map { i in
            WorkoutStateSnapshot.PlannedSet(
                id: UUID(),
                index: i,
                targetReps: 8,
                targetWeightKg: 20,
                isCompleted: i < completed
            )
        }
        return WorkoutStateSnapshot(
            workoutID: UUID(),
            currentExerciseID: UUID(),
            currentExerciseName: "Bench Press",
            sets: sets,
            elapsedSeconds: 120,
            progress: .init(completedSetCount: completed, totalSetCount: setCount),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    static func config(preset: WatchScreenConfig.Preset = .hrFocus) -> WatchScreenConfig {
        WatchScreenConfig(
            preset: preset,
            enabledModules: [.clock, .elapsed, .heartRate, .primaryAction],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
    }

    static func hr(_ bpm: Double) -> LiveHeartRatePayload {
        LiveHeartRatePayload(
            bpm: bpm,
            timestamp: Date(timeIntervalSince1970: 1_700_000_200),
            sourceName: "Apple Watch"
        )
    }

    static func firstValue<T: Sendable>(
        _ stream: AsyncStream<T>,
        timeout: Duration = .seconds(1)
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                return await iterator.next()
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }
            let result = try await group.next()!
            group.cancelAll()
            guard let value = result else {
                throw TimeoutError()
            }
            return value
        }
    }

    struct TimeoutError: Error {}
}

// MARK: - Config default emission

@Suite("WatchWorkoutInboundStore.config", .serialized)
struct WatchWorkoutInboundStoreConfigTests {

    @Test("New subscriber sees defaultConfig immediately (spec §7 fallback)")
    func configEmitsDefaultOnSubscribe() async throws {
        let store = WatchWorkoutInboundStore()
        let stream = await store.observeInboundWatchScreenConfig()
        let first = try await Fixture.firstValue(stream)

        #expect(first.preset == .fullInfo)
        #expect(first == WatchScreenConfig.defaultConfig())
        // Locked-on invariant survives default emission.
        #expect(first.enabledModules.isSuperset(of: WatchScreenConfig.lockedOnModules))
    }

    @Test("apply(.watchScreenConfig) replaces default with latest")
    func configLatestWins() async throws {
        let store = WatchWorkoutInboundStore()
        let stream = await store.observeInboundWatchScreenConfig()
        var iterator = stream.makeAsyncIterator()

        // 1) default
        let first = await iterator.next()
        #expect(first?.preset == .fullInfo)

        // 2) real config pushed
        let pushed = Fixture.config(preset: .hrFocus)
        await store.apply(.watchScreenConfig(pushed))

        let second = await iterator.next()
        #expect(second?.preset == .hrFocus)
    }

    @Test("Late subscriber sees latest applied config, not default")
    func lateSubscriberSeesLatestConfig() async throws {
        let store = WatchWorkoutInboundStore()
        let pushed = Fixture.config(preset: .list)
        await store.apply(.watchScreenConfig(pushed))

        let stream = await store.observeInboundWatchScreenConfig()
        let first = try await Fixture.firstValue(stream)
        #expect(first.preset == .list)
    }
}

// MARK: - State stream

@Suite("WatchWorkoutInboundStore.state", .serialized)
struct WatchWorkoutInboundStoreStateTests {

    @Test("apply(.workoutState) delivers to subscribers")
    func stateFanOut() async throws {
        let store = WatchWorkoutInboundStore()
        let stream = await store.observeInboundWorkoutState()

        let snap = Fixture.snapshot(setCount: 3, completed: 1)
        await store.apply(.workoutState(snap))

        let first = try await Fixture.firstValue(stream)
        #expect(first.sets.count == 3)
        #expect(first.progress.completedSetCount == 1)
    }

    @Test("Latest-wins: slow subscriber only sees newest snapshot")
    func stateLatestWins() async throws {
        let store = WatchWorkoutInboundStore()
        let a = Fixture.snapshot(setCount: 2, completed: 0)
        let b = Fixture.snapshot(setCount: 2, completed: 1)
        let c = Fixture.snapshot(setCount: 2, completed: 2)
        await store.apply(.workoutState(a))
        await store.apply(.workoutState(b))
        await store.apply(.workoutState(c))

        let stream = await store.observeInboundWorkoutState()
        let first = try await Fixture.firstValue(stream)
        #expect(first.progress.completedSetCount == 2)
    }

    @Test("Late subscriber replays latest cached state")
    func stateLateReplay() async throws {
        let store = WatchWorkoutInboundStore()
        let snap = Fixture.snapshot(setCount: 4, completed: 3)
        await store.apply(.workoutState(snap))
        let stream = await store.observeInboundWorkoutState()
        let first = try await Fixture.firstValue(stream)
        #expect(first.progress.totalSetCount == 4)
    }
}

// MARK: - Local HR broadcast

@Suite("WatchWorkoutInboundStore.localHR", .serialized)
struct WatchWorkoutInboundStoreHRTests {

    @Test("broadcastLocalHR delivers plausible sample")
    func hrBroadcast() async throws {
        let store = WatchWorkoutInboundStore()
        let stream = await store.observeLocalHeartRate()

        let payload = Fixture.hr(88)
        await store.broadcastLocalHR(payload)

        let first = try await Fixture.firstValue(stream)
        #expect(first.bpm == 88)
        #expect(first.sampleType == .heartRate)
    }

    @Test("broadcastLocalHR rejects out-of-range without crashing")
    func hrRejectsOutOfRange() async {
        let store = WatchWorkoutInboundStore()
        await store.broadcastLocalHR(Fixture.hr(-1))
        await store.broadcastLocalHR(Fixture.hr(0))
        await store.broadcastLocalHR(Fixture.hr(500))
        await store.broadcastLocalHR(Fixture.hr(.infinity))
        // No subscribers before this point → nothing to observe. This test
        // just asserts the actor did not crash on any of the invalid inputs.
    }
}

// MARK: - Malformed payload / reverse-direction

@Suite("WatchWorkoutInboundStore.malformed", .serialized)
struct WatchWorkoutInboundStoreMalformedTests {

    @Test("inboundDidReceiveApplicationContext ignores malformed dict without crash")
    func malformedApplicationContextIgnored() async throws {
        let store = WatchWorkoutInboundStore()
        // No `envelope` key → codec throws malformedEnvelope; store must
        // swallow and not deliver to state / config streams.
        store.inboundDidReceiveApplicationContext(["garbage": 42])
        store.inboundDidReceiveApplicationContext(["envelope": "not-data"])
        // Give the actor-hop a chance (though nothing should be delivered).
        try await Task.sleep(for: .milliseconds(50))

        // Now subscribe to state — should have no cached state (only config
        // has a default). Fetch first value with a short timeout: expect
        // TimeoutError because there is no state to emit.
        let stateStream = await store.observeInboundWorkoutState()
        await #expect(throws: Fixture.TimeoutError.self) {
            _ = try await Fixture.firstValue(stateStream, timeout: .milliseconds(100))
        }
    }

    @Test("Wrong-envelope Data payload does not crash")
    func malformedEnvelopeDataIgnored() async throws {
        let store = WatchWorkoutInboundStore()
        store.inboundDidReceiveApplicationContext(["envelope": Data([0xFF, 0xFE, 0x00])])
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test("Reverse-direction payloads (watch→phone kinds) are dropped, not fanned out")
    func reverseDirectionPayloadsDropped() async throws {
        let store = WatchWorkoutInboundStore()
        // liveHeartRate + setCompleted on the WATCH side are reverse-
        // direction: watch is the SENDER. Applying them must not surface
        // via any inbound stream (there is no watch-side inbound HR stream
        // either — HR-inbound is the phone).
        await store.apply(.liveHeartRate(Fixture.hr(80)))
        await store.apply(.setCompleted(SetCompletedEvent(
            workoutID: UUID(),
            setID: UUID(),
            actualReps: 8,
            completedAt: Date(timeIntervalSince1970: 1_700_000_500)
        )))

        // State and config streams should have their normal semantics:
        // state has nothing (no snapshot applied), config emits default.
        let stateStream = await store.observeInboundWorkoutState()
        await #expect(throws: Fixture.TimeoutError.self) {
            _ = try await Fixture.firstValue(stateStream, timeout: .milliseconds(100))
        }
        let configStream = await store.observeInboundWatchScreenConfig()
        let cfg = try await Fixture.firstValue(configStream)
        #expect(cfg == WatchScreenConfig.defaultConfig())
    }
}

// MARK: - Round-trip via WC codec (real dict → store)

@Suite("WatchWorkoutInboundStore.roundTrip", .serialized)
struct WatchWorkoutInboundStoreRoundTripTests {

    @Test("Encoded state dict from codec is decoded + delivered")
    func stateRoundTrip() async throws {
        let store = WatchWorkoutInboundStore()
        let snap = Fixture.snapshot(setCount: 5, completed: 2)
        let dict = try WatchConnectivityCodec.encodeDictionary(.workoutState(snap))

        store.inboundDidReceiveApplicationContext(dict)

        // Poll with a bounded retry — actor hop is quick but not synchronous.
        let stream = await store.observeInboundWorkoutState()
        let first = try await Fixture.firstValue(stream, timeout: .seconds(1))
        #expect(first.sets.count == 5)
        #expect(first.progress.completedSetCount == 2)
    }

    @Test("Encoded config dict is decoded + delivered (overrides default)")
    func configRoundTrip() async throws {
        let store = WatchWorkoutInboundStore()
        let cfg = Fixture.config(preset: .nextFocus)
        let dict = try WatchConnectivityCodec.encodeDictionary(.watchScreenConfig(cfg))

        store.inboundDidReceiveApplicationContext(dict)

        let stream = await store.observeInboundWatchScreenConfig()
        // Iterate up to two values: default → real config (or just real if
        // the actor hop landed before subscription — accept either).
        var iterator = stream.makeAsyncIterator()
        let firstValue = await iterator.next()
        guard let firstValue else {
            Issue.record("stream ended before first value")
            return
        }
        if firstValue.preset == .nextFocus {
            // Real config already applied by time we subscribed.
        } else {
            // Default came first — next value must be the applied config.
            let second = await iterator.next()
            #expect(second?.preset == .nextFocus)
        }
    }
}

// MARK: - Stream termination

@Suite("WatchWorkoutInboundStore.termination", .serialized)
struct WatchWorkoutInboundStoreTerminationTests {

    @Test("finishAllStreams terminates active subscribers")
    func finishAllTerminates() async throws {
        let store = WatchWorkoutInboundStore()
        let stateStream = await store.observeInboundWorkoutState()
        let configStream = await store.observeInboundWatchScreenConfig()
        let hrStream = await store.observeLocalHeartRate()

        // Drain the config default emission so the iterator is positioned
        // at "waiting for next value".
        var configIterator = configStream.makeAsyncIterator()
        _ = await configIterator.next()

        await store.finishAllStreams()

        // All three iterators should now terminate (return nil).
        var stateIterator = stateStream.makeAsyncIterator()
        var hrIterator = hrStream.makeAsyncIterator()

        let stateEnd = await stateIterator.next()
        let configEnd = await configIterator.next()
        let hrEnd = await hrIterator.next()

        #expect(stateEnd == nil)
        #expect(configEnd == nil)
        #expect(hrEnd == nil)
    }
}
