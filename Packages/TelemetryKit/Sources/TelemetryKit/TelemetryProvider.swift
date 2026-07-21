public protocol TelemetryProvider: Sendable {
    func track(_ event: TelemetryEvent)

    /// Sink for MetricKit crash / hang diagnostics (ADR-0012). Distinct from
    /// ``track(_:)`` because a diagnostic is a closed ``TelemetryDiagnostic``
    /// value, not a `TelemetryEvent`. Providers that do not transport
    /// diagnostics inherit the default no-op, so adding this sink does not
    /// disturb existing providers (e.g. `ConsoleTelemetryProvider`).
    func record(_ diagnostic: TelemetryDiagnostic)
}

public extension TelemetryProvider {
    func record(_ diagnostic: TelemetryDiagnostic) {}
}
