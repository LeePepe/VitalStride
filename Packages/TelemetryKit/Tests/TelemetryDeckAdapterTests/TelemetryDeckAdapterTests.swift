@testable import TelemetryDeckAdapter
import os
import TelemetryKit
import XCTest

/// Facade round-trip + dispatch-seam tests for `TelemetryDeckAdapter`.
///
/// - A-T1 / A-T2 satisfy Constitution P1-I (new public API needs a
///   round-trip test) — they drive the real facade through the internal
///   seam overload so that a fake sink observes the exact signals emitted.
/// - A-T3 covers the dispatch seam of `TelemetryDeckSDKSink`, proving the
///   default init forwards to whatever closure it was constructed with.
/// - A-T4 exercises the production facade end-to-end (real SDK sink) to
///   catch a `track(_:)` crash after SDK initialization.
///
/// Concurrency: all mutable test doubles wrap their state in
/// `OSAllocatedUnfairLock`, which is `Sendable` by construction — no
/// unchecked-Sendable escapes needed (Constitution §II).
final class TelemetryDeckAdapterTests: XCTestCase {
    // MARK: - Fake sink

    /// Test fake — captures every signal the provider hands us.
    ///
    /// `OSAllocatedUnfairLock` is a value type that owns and gates access to
    /// the underlying storage; it's `Sendable`, so wrapping it in a `struct`
    /// gives us a fully concurrency-safe sink with no unchecked escape.
    struct FakeSink: TelemetryDeckSignalSink {
        private let storage = OSAllocatedUnfairLock<[TelemetryDeckSignal]>(initialState: [])

        var signals: [TelemetryDeckSignal] {
            storage.withLock { $0 }
        }

        func send(_ signal: TelemetryDeckSignal) {
            storage.withLock { $0.append(signal) }
        }
    }

    // MARK: - A-T1 facade round-trip

    func test_facadeRoundTrip_workoutStarted_emitsExpectedSignal() {
        let fake = FakeSink()
        let provider = TelemetryDeckAdapter.makeProvider(appID: "test", sink: fake)

        provider.track(.workoutStarted(source: "test"))

        XCTAssertEqual(
            fake.signals,
            [TelemetryDeckSignal(signalType: "workout_started", parameters: ["source": "test"])]
        )
    }

    // MARK: - A-T2 facade round-trip (parameterised)

    func test_facadeRoundTrip_aiInsightGenerated_emitsExpectedSignal() {
        let fake = FakeSink()
        let provider = TelemetryDeckAdapter.makeProvider(appID: "test", sink: fake)

        provider.track(.aiInsightGenerated(durationMs: 42, cardCount: 3))

        XCTAssertEqual(
            fake.signals,
            [
                TelemetryDeckSignal(
                    signalType: "ai_insight_generated",
                    parameters: ["duration_ms": "42", "cards": "3"]
                ),
            ]
        )
    }

    // MARK: - A-T3 dispatch seam

    func test_sdkSink_dispatchSeam_forwardsSignalTypeAndParameters() {
        let capture = OSAllocatedUnfairLock<(String, [String: String])?>(initialState: nil)

        let sink = TelemetryDeckSDKSink { signalType, parameters in
            capture.withLock { $0 = (signalType, parameters) }
        }

        sink.send(TelemetryDeckSignal(signalType: "workout_started", parameters: ["source": "unit"]))

        let captured = capture.withLock { $0 }
        XCTAssertEqual(captured?.0, "workout_started")
        XCTAssertEqual(captured?.1, ["source": "unit"])
    }

    // MARK: - A-T4 public production overload smoke

    func test_publicProductionFacade_smoke_doesNotCrash() {
        let provider: any TelemetryProvider = TelemetryDeckAdapter.makeProvider(appID: "test")
        provider.track(.workoutDiscarded)
    }
}
