import TelemetryDeck
import TelemetryKit

/// The real `TelemetryDeck` SDK sink — a thin, `internal` bridge from a
/// `TelemetryDeckSignal` to `TelemetryDeck.signal(_:parameters:)`.
///
/// Keeping this `internal` (and only reachable via `TelemetryDeckAdapter`)
/// preserves the typed-event contract: outside callers cannot send an
/// arbitrary free-form signal — they can only obtain an `any TelemetryProvider`
/// whose surface is the closed `TelemetryEvent` / `TelemetryDiagnostic` set.
///
/// The `dispatch` closure is an `internal` seam so a unit test can substitute
/// a capture-only closure without touching the real SDK; production callers
/// use the default parameter which forwards to the real SDK.
struct TelemetryDeckSDKSink: TelemetryDeckSignalSink {
    let dispatch: @Sendable (String, [String: String]) -> Void

    init(
        dispatch: @escaping @Sendable (String, [String: String]) -> Void = { signalType, parameters in
            TelemetryDeck.signal(signalType, parameters: parameters)
        }
    ) {
        self.dispatch = dispatch
    }

    func send(_ signal: TelemetryDeckSignal) {
        dispatch(signal.signalType, signal.parameters)
    }
}
