/// A backend-neutral representation of one analytics signal.
///
/// This value type is the seam between VitalStride's typed telemetry
/// (`TelemetryEvent`) and whichever analytics SDK is wired in (currently the
/// self-hosted Aptabase adapter — ADR-0015). The mapping (event → signal) is
/// pure and unit-testable; the actual SDK call is isolated behind
/// ``AnalyticsSignalSink`` so the real `import Aptabase` lives in one thin
/// adapter (architecture first, SDK last).
///
/// `name` and `parameters` are already-canonical ASCII (events carry
/// `TelemetryIdentifier`s), so this type introduces no new free-form or
/// health-value surface — Constitution §I holds by construction.
///
/// Crash/hang diagnostics do NOT map to an analytics signal: ADR-0013 routes
/// them exclusively through the self-hosted GlitchTip / sentry-cocoa channel,
/// so this type intentionally has no `init(diagnostic:)`.
public struct AnalyticsSignal: Sendable, Equatable {
    /// Analytics event name, e.g. `"workout_started"`.
    public let name: String
    /// Flat string parameters. Keys and values are canonical ASCII.
    public let parameters: [String: String]

    public init(name: String, parameters: [String: String] = [:]) {
        self.name = name
        self.parameters = parameters
    }
}

// MARK: - Mapping from typed telemetry to signals

public extension AnalyticsSignal {
    /// Map a product-analytics event to a signal. Reuses the event's own
    /// `eventName` / `parameters` (already ASCII, already §I-safe).
    init(event: TelemetryEvent) {
        var params: [String: String] = [:]
        for pair in event.parameters {
            params[pair.key] = pair.value
        }
        self.init(name: event.eventName, parameters: params)
    }
}
