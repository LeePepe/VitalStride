import Aptabase
import TelemetryKit

/// The real `Aptabase` SDK sink — a thin, `internal` bridge from an
/// `AnalyticsSignal` to `Aptabase.shared.trackEvent(_:with:)`.
///
/// Keeping this `internal` (and only reachable via `AptabaseAdapter`) preserves
/// the typed-event contract: outside callers cannot send an arbitrary free-form
/// signal — they can only obtain an `any TelemetryProvider` whose surface is
/// the closed `TelemetryEvent` / `TelemetryDiagnostic` set.
///
/// The `dispatch` closure is an `internal` seam so a unit test can substitute a
/// capture-only closure without touching the real SDK; production callers use
/// the default parameter which forwards to the real SDK.
struct AptabaseSDKSink: AnalyticsSignalSink {
    let dispatch: @Sendable (String, [String: String]) -> Void

    init(
        dispatch: @escaping @Sendable (String, [String: String]) -> Void = { name, parameters in
            Aptabase.shared.trackEvent(name, with: parameters)
        }
    ) {
        self.dispatch = dispatch
    }

    func send(_ signal: AnalyticsSignal) {
        dispatch(signal.name, signal.parameters)
    }
}
