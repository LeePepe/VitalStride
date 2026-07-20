import Foundation
import HealthKitService
import Testing

@testable import VitalStride

/// Regression coverage for the two MY-1283 ship blockers Team Lead flagged
/// on PR #296:
///
/// - **Blocker 1**: on unreachable/disconnected the view must clear the
///   last held BPM+timestamp so a reconnect enters `.awaiting` until a
///   fresh sample arrives (never re-renders the pre-drop value).
/// - **Blocker 2**: freshness must be stamped from
///   `LiveHeartRatePayload.timestamp`, not receipt-time. A delayed payload
///   whose sample time is older than the freshness window must NOT render
///   as `.value`.
///
/// The `HeartRateStateResolver` is a pure function so both invariants are
/// exercised without SwiftUI @State or real WCSession transport.
@Suite("HeartRateStateResolver (MY-1283 regressions)")
struct HeartRateStateResolverTests {

    // MARK: - Base three-state behavior

    @Test("Non-reachable connection always resolves to .disconnected, even with a held value")
    func nonReachableAlwaysDisconnected() {
        let now = Date()
        let recent = now.addingTimeInterval(-1)
        for state in [WatchConnectionState.unsupported, .notPaired, .notInstalled, .unreachable] {
            let resolved = HeartRateStateResolver.resolve(
                connection: state,
                lastValue: 142,
                lastTimestamp: recent,
                now: now
            )
            #expect(resolved == .disconnected, "state=\(state) must resolve to .disconnected")
        }
    }

    @Test("Reachable but no sample yet resolves to .awaiting")
    func reachableWithoutSampleIsAwaiting() {
        let resolved = HeartRateStateResolver.resolve(
            connection: .reachable,
            lastValue: nil,
            lastTimestamp: nil,
            now: Date()
        )
        #expect(resolved == .awaiting)
    }

    @Test("Reachable + fresh sample resolves to .value")
    func reachableWithFreshSampleIsValue() {
        let now = Date()
        let resolved = HeartRateStateResolver.resolve(
            connection: .reachable,
            lastValue: 128,
            lastTimestamp: now.addingTimeInterval(-2),
            now: now
        )
        #expect(resolved == .value(128))
    }

    // MARK: - Blocker 1: disconnect → reconnect within 20s

    @Test("After a link drop the view clears the held sample so reconnect within 20s enters .awaiting")
    func reconnectWithin20SecondsEntersAwaiting() {
        let now = Date()
        // 1. Reachable + fresh sample at t0.
        let t0 = now
        var lastValue: Double? = 142
        var lastTimestamp: Date? = t0
        let midStream = HeartRateStateResolver.resolve(
            connection: .reachable,
            lastValue: lastValue,
            lastTimestamp: lastTimestamp,
            now: t0
        )
        #expect(midStream == .value(142), "sanity: fresh sample renders as value")

        // 2. Link drops (unreachable). ActiveWorkoutView's
        //    `observeHeartRateConnection` clears the two @State fields on
        //    any non-.reachable transition. Model the clear here.
        lastValue = nil
        lastTimestamp = nil

        let dropped = HeartRateStateResolver.resolve(
            connection: .unreachable,
            lastValue: lastValue,
            lastTimestamp: lastTimestamp,
            now: t0.addingTimeInterval(1)
        )
        #expect(dropped == .disconnected, "unreachable link must render as disconnected")

        // 3. Reconnect 5s later, still well inside the 20s freshness window
        //    of the pre-drop sample. Because the view cleared the held
        //    value, the resolver must NOT re-render 142 as fresh — it
        //    must resolve to .awaiting until a new sample arrives.
        let reconnectAt = t0.addingTimeInterval(5)
        let reconnected = HeartRateStateResolver.resolve(
            connection: .reachable,
            lastValue: lastValue,
            lastTimestamp: lastTimestamp,
            now: reconnectAt
        )
        #expect(reconnected == .awaiting,
                "reconnect within pre-drop freshness window must NOT show stale BPM")

        // 4. First fresh post-reconnect sample flows in — resolver flips
        //    back to .value on that specific sample.
        let firstPostReconnect = reconnectAt.addingTimeInterval(1)
        lastValue = 150
        lastTimestamp = firstPostReconnect
        let afterFresh = HeartRateStateResolver.resolve(
            connection: .reachable,
            lastValue: lastValue,
            lastTimestamp: lastTimestamp,
            now: firstPostReconnect
        )
        #expect(afterFresh == .value(150))
    }

    @Test("Guard-clause: resolver still short-circuits to .disconnected if caller forgets to clear")
    func nonReachableGuardClauseShortCircuits() {
        // Defence-in-depth: even if a future caller regression forgets to
        // clear the held value on a non-reachable transition, the resolver
        // itself must never leak a stale BPM into a disconnected display.
        let now = Date()
        let resolved = HeartRateStateResolver.resolve(
            connection: .unreachable,
            lastValue: 142,               // stale value survived caller clear
            lastTimestamp: now.addingTimeInterval(-1),
            now: now
        )
        #expect(resolved == .disconnected)
    }

    // MARK: - Blocker 2: freshness stamped from payload.timestamp

    @Test("Delayed payload (sample-time older than freshness window) resolves to .awaiting")
    func delayedPayloadCannotRenderAsFresh() {
        let now = Date()
        // Payload was sampled 45s ago but only just delivered. If freshness
        // were stamped from receipt-time (`Date()`) it would render as
        // .value(142) here. Because callers now stamp from
        // `payload.timestamp`, resolver correctly sees a 45s-old sample
        // and downgrades to .awaiting.
        let sampledAt = now.addingTimeInterval(-45)
        let resolved = HeartRateStateResolver.resolve(
            connection: .reachable,
            lastValue: 142,
            lastTimestamp: sampledAt,
            now: now
        )
        #expect(resolved == .awaiting,
                "delayed payload older than freshness window must NOT render as fresh")
    }

    @Test("Sample exactly at freshness boundary is treated as fresh")
    func sampleAtBoundaryIsFresh() {
        let now = Date()
        let atBoundary = now.addingTimeInterval(-HeartRateStateResolver.defaultFreshnessLimit)
        let resolved = HeartRateStateResolver.resolve(
            connection: .reachable,
            lastValue: 100,
            lastTimestamp: atBoundary,
            now: now
        )
        #expect(resolved == .value(100),
                "boundary-age sample must still render (<= freshnessLimit)")
    }

    @Test("Sample one tick past the freshness boundary falls to .awaiting")
    func sampleJustPastBoundaryIsAwaiting() {
        let now = Date()
        let justPast = now.addingTimeInterval(-HeartRateStateResolver.defaultFreshnessLimit - 0.001)
        let resolved = HeartRateStateResolver.resolve(
            connection: .reachable,
            lastValue: 100,
            lastTimestamp: justPast,
            now: now
        )
        #expect(resolved == .awaiting)
    }

    @Test("Future-dated timestamp (clock skew) is treated as fresh, not stale")
    func futureDatedTimestampRendersAsFresh() {
        // If the Watch's clock is slightly ahead of the phone the payload's
        // timestamp can be a fraction of a second in the future. That's
        // clock skew, not staleness — must still render.
        let now = Date()
        let slightlyFuture = now.addingTimeInterval(0.5)
        let resolved = HeartRateStateResolver.resolve(
            connection: .reachable,
            lastValue: 133,
            lastTimestamp: slightlyFuture,
            now: now
        )
        #expect(resolved == .value(133))
    }

    // MARK: - Injectable freshness limit

    @Test("Custom freshness limit is honored")
    func customFreshnessLimit() {
        let now = Date()
        let sampledAt = now.addingTimeInterval(-10)
        // With default 20s limit → fresh.
        let defaultLimit = HeartRateStateResolver.resolve(
            connection: .reachable,
            lastValue: 88,
            lastTimestamp: sampledAt,
            now: now
        )
        #expect(defaultLimit == .value(88))
        // With a tighter 5s limit → same sample now stale.
        let tightLimit = HeartRateStateResolver.resolve(
            connection: .reachable,
            lastValue: 88,
            lastTimestamp: sampledAt,
            now: now,
            freshnessLimit: 5
        )
        #expect(tightLimit == .awaiting)
    }
}
