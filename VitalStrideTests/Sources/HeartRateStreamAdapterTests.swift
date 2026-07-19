import Foundation
import HealthKitService
import Testing

@testable import VitalStride

/// Production-path regression coverage for the two MY-1283 P0 findings.
///
/// Unlike `HeartRateStateResolverTests` (which unit-tests the pure
/// resolver by feeding it already-cleared inputs), these tests exercise
/// the EXACT code called by `ActiveWorkoutView.observeHeartRate()` and
/// `ActiveWorkoutView.observeHeartRateConnection()`:
///
/// * The view methods delegate every per-item mutation to
///   `HeartRateStreamAdapter.consumeLiveHeartRate` and
///   `HeartRateStreamAdapter.consumeConnectionState`.
/// * These tests feed real `AsyncStream`s into those two consumers and
///   assert the captured @State transitions match the invariants.
///
/// A regression that (a) re-introduces receipt-time `Date()` stamping in
/// the live-HR path, or (b) drops the on-disconnect clear in the
/// connection path, breaks these tests deterministically because the
/// adapter is the single code path shared by view and tests.
@Suite("HeartRateStreamAdapter (MY-1283 production-path regressions)")
@MainActor
struct HeartRateStreamAdapterTests {

    /// Tiny holder that mirrors the two @State fields the view writes.
    /// Serves both as the destination sink for the adapter and as the
    /// assertion surface for the tests.
    final class CapturedState {
        var connection: WatchConnectionState = .unsupported
        var value: Double?
        var timestamp: Date?

        /// Snapshot appended on every write so tests can inspect the
        /// exact transition order (mirrors what SwiftUI would render
        /// per animation frame).
        var connectionHistory: [WatchConnectionState] = []
        var valueHistory: [Double?] = []
        var timestampHistory: [Date?] = []
    }

    // MARK: - Blocker 1: production connection adapter clears held BPM on disconnect

    @Test("consumeConnectionState clears held BPM+timestamp on every non-.reachable transition, then reconnect stays cleared until a fresh sample")
    func consumeConnectionState_clearsHeldBPMOnDisconnect() async {
        let captured = CapturedState()

        // Seed a pre-drop fresh sample as if a previous HR stream had
        // already delivered one. This is the exact scenario a reconnect
        // would face if the adapter forgot to clear.
        let preDrop = Date(timeIntervalSinceReferenceDate: 100)
        captured.value = 142
        captured.timestamp = preDrop
        captured.connection = .reachable

        let (stream, continuation) = AsyncStream<WatchConnectionState>.makeStream()

        // Feed the full sequence, finish the stream, then await the
        // consumer task to completion — that's the only reliable way to
        // observe all interleaved writes when both producer and consumer
        // are on MainActor (Task.yield() alone doesn't drain them).
        continuation.yield(.unreachable)
        continuation.yield(.reachable)
        continuation.finish()

        await HeartRateStreamAdapter.consumeConnectionState(
            stream,
            setConnection: {
                captured.connection = $0
                captured.connectionHistory.append($0)
            },
            setValue: {
                captured.value = $0
                captured.valueHistory.append($0)
            },
            setTimestamp: {
                captured.timestamp = $0
                captured.timestampHistory.append($0)
            }
        )

        // History reveals the exact per-transition writes.
        #expect(captured.connectionHistory == [.unreachable, .reachable])

        // 1. On .unreachable the adapter must have cleared both fields.
        //    valueHistory[0] and timestampHistory[0] correspond to that
        //    write (the only writes triggered by non-.reachable states).
        #expect(captured.valueHistory == [nil],
                "P0 REGRESSION: unreachable transition must write nil to value exactly once")
        #expect(captured.timestampHistory == [nil],
                "P0 REGRESSION: unreachable transition must write nil to timestamp exactly once")

        // 2. Post-reconnect state: value + timestamp remain nil because
        //    .reachable itself performs no clear (only non-.reachable
        //    variants do). A future fresh sample would set them via the
        //    live-HR adapter, not this stream.
        #expect(captured.connection == .reachable)
        #expect(captured.value == nil,
                "P0 REGRESSION: reconnect must not re-inherit pre-drop BPM")
        #expect(captured.timestamp == nil,
                "P0 REGRESSION: reconnect must not re-inherit pre-drop timestamp")

        // 3. Resolver observing captured state at this moment must be
        //    .awaiting (not .value(142)) — proves the reconnect UX
        //    contract holds end-to-end.
        let resolved = HeartRateStateResolver.resolve(
            connection: captured.connection,
            lastValue: captured.value,
            lastTimestamp: captured.timestamp,
            now: preDrop.addingTimeInterval(5) // still inside 20s window
        )
        #expect(resolved == .awaiting,
                "P0 REGRESSION: production adapter path must land in .awaiting after reconnect within freshness window")
    }

    @Test("consumeConnectionState clears BPM on each non-.reachable variant (unsupported / notPaired / notInstalled / unreachable)")
    func consumeConnectionState_clearsOnEveryNonReachableVariant() async {
        for variant: WatchConnectionState in [.unsupported, .notPaired, .notInstalled, .unreachable] {
            let captured = CapturedState()
            captured.value = 130
            captured.timestamp = Date(timeIntervalSinceReferenceDate: 200)
            captured.connection = .reachable

            let (stream, continuation) = AsyncStream<WatchConnectionState>.makeStream()
            continuation.yield(variant)
            continuation.finish()

            await HeartRateStreamAdapter.consumeConnectionState(
                stream,
                setConnection: { captured.connection = $0 },
                setValue: { captured.value = $0 },
                setTimestamp: { captured.timestamp = $0 }
            )

            #expect(captured.connection == variant, "variant=\(variant)")
            #expect(captured.value == nil,
                    "P0 REGRESSION: variant=\(variant) must clear held BPM")
            #expect(captured.timestamp == nil,
                    "P0 REGRESSION: variant=\(variant) must clear held timestamp")
        }
    }

    @Test(".reachable → .reachable transition does NOT clear held BPM (only disconnects clear)")
    func consumeConnectionState_reachableToReachableDoesNotClear() async {
        let captured = CapturedState()
        let sampledAt = Date(timeIntervalSinceReferenceDate: 300)
        captured.value = 125
        captured.timestamp = sampledAt
        captured.connection = .reachable

        let (stream, continuation) = AsyncStream<WatchConnectionState>.makeStream()
        continuation.yield(.reachable)
        continuation.finish()

        await HeartRateStreamAdapter.consumeConnectionState(
            stream,
            setConnection: { captured.connection = $0 },
            setValue: { captured.value = $0 },
            setTimestamp: { captured.timestamp = $0 }
        )

        #expect(captured.value == 125, "reachable→reachable must not clear held BPM")
        #expect(captured.timestamp == sampledAt)
    }

    // MARK: - Blocker 2: production live-HR adapter stamps from payload.timestamp

    @Test("consumeLiveHeartRate stamps freshness from payload.timestamp, not receipt-time Date()")
    func consumeLiveHeartRate_stampsFromPayloadTimestamp() async {
        let captured = CapturedState()

        // Payload sampled 45s in the past. If the production adapter
        // ever regresses to `heartRateReceivedAt = Date()`, `captured.timestamp`
        // will land within a fraction of a second of "now" and the
        // assertion below (must be the exact 45s-old sampledAt) fails.
        let receiptWindowStart = Date()
        let sampledAt = receiptWindowStart.addingTimeInterval(-45)
        let payload = LiveHeartRatePayload(
            sampleType: .heartRate,
            bpm: 142,
            timestamp: sampledAt,
            sourceName: "Apple Watch"
        )

        let (stream, continuation) = AsyncStream<LiveHeartRatePayload>.makeStream()
        continuation.yield(payload)
        continuation.finish()

        await HeartRateStreamAdapter.consumeLiveHeartRate(
            stream,
            setValue: { captured.value = $0 },
            setTimestamp: { captured.timestamp = $0 }
        )

        #expect(captured.value == 142)
        #expect(captured.timestamp == sampledAt,
                "P0 REGRESSION: heartRateReceivedAt must be payload.timestamp, not receipt-time Date()")

        // Sanity: had this been Date() at receipt, the timestamp would
        // be within 5s of `receiptWindowStart`. Detect that regression
        // shape explicitly so a future refactor can't sneak it past.
        if let captured = captured.timestamp {
            let ageAtReceipt = captured.timeIntervalSince(receiptWindowStart)
            #expect(ageAtReceipt < -30,
                    "P0 REGRESSION: captured timestamp within 30s of receipt-time — production adapter regressed to Date() stamping")
        }

        // Downstream resolver — a payload this stale must render as
        // .awaiting even though it just arrived, proving the end-to-end
        // production behavior.
        let resolved = HeartRateStateResolver.resolve(
            connection: .reachable,
            lastValue: captured.value,
            lastTimestamp: captured.timestamp,
            now: receiptWindowStart
        )
        #expect(resolved == .awaiting,
                "P0 REGRESSION: delayed payload must resolve to .awaiting via production path")
    }

    @Test("consumeLiveHeartRate delivers a sequence of payloads in order, each stamped from its own timestamp")
    func consumeLiveHeartRate_ordersAndStampsAllPayloads() async {
        let captured = CapturedState()
        let t0 = Date(timeIntervalSinceReferenceDate: 500)
        let payloads = [
            LiveHeartRatePayload(bpm: 120, timestamp: t0, sourceName: "Watch"),
            LiveHeartRatePayload(bpm: 128, timestamp: t0.addingTimeInterval(1), sourceName: "Watch"),
            LiveHeartRatePayload(bpm: 135, timestamp: t0.addingTimeInterval(2), sourceName: "Watch")
        ]

        let (stream, continuation) = AsyncStream<LiveHeartRatePayload>.makeStream()
        for payload in payloads {
            continuation.yield(payload)
        }
        continuation.finish()

        await HeartRateStreamAdapter.consumeLiveHeartRate(
            stream,
            setValue: {
                captured.value = $0
                captured.valueHistory.append($0)
            },
            setTimestamp: {
                captured.timestamp = $0
                captured.timestampHistory.append($0)
            }
        )

        #expect(captured.valueHistory == [120, 128, 135])
        #expect(captured.timestampHistory == payloads.map(\.timestamp),
                "Every write must use payload.timestamp, in order")
    }

    // MARK: - Static per-item helpers (compile-time contract)

    @Test("applyLivePayload writes payload.bpm + payload.timestamp exactly (never Date())")
    func applyLivePayload_writesPayloadFieldsExactly() {
        var value: Double?
        var timestamp: Date?
        let sampledAt = Date(timeIntervalSinceReferenceDate: 42)
        let payload = LiveHeartRatePayload(
            bpm: 99,
            timestamp: sampledAt,
            sourceName: nil
        )

        HeartRateStreamAdapter.applyLivePayload(
            payload,
            setValue: { value = $0 },
            setTimestamp: { timestamp = $0 }
        )

        #expect(value == 99)
        #expect(timestamp == sampledAt)
    }

    @Test("applyConnectionState clears on non-.reachable, preserves on .reachable")
    func applyConnectionState_clearsOnlyOnNonReachable() {
        // Non-reachable → must clear both
        for state: WatchConnectionState in [.unsupported, .notPaired, .notInstalled, .unreachable] {
            var conn: WatchConnectionState = .reachable
            var value: Double? = 130
            var timestamp: Date? = Date()
            HeartRateStreamAdapter.applyConnectionState(
                state,
                setConnection: { conn = $0 },
                setValue: { value = $0 },
                setTimestamp: { timestamp = $0 }
            )
            #expect(conn == state)
            #expect(value == nil, "state=\(state) must clear value")
            #expect(timestamp == nil, "state=\(state) must clear timestamp")
        }

        // Reachable → must NOT clear
        var conn: WatchConnectionState = .unsupported
        var value: Double? = 145
        let stamp = Date(timeIntervalSinceReferenceDate: 999)
        var timestamp: Date? = stamp
        HeartRateStreamAdapter.applyConnectionState(
            .reachable,
            setConnection: { conn = $0 },
            setValue: { value = $0 },
            setTimestamp: { timestamp = $0 }
        )
        #expect(conn == .reachable)
        #expect(value == 145, ".reachable transition must not clear held BPM")
        #expect(timestamp == stamp)
    }
}
