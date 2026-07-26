/// The one-method seam the real analytics SDK adapter implements. Keeping the
/// SDK behind this protocol means the entire mapping + provider logic is
/// unit-testable with a fake sink, and the real `import Aptabase` is a single
/// thin file (the `AptabaseAdapter` product).
///
/// Implementations must be safe to call from any isolation domain (the SDK's
/// track call is itself thread-safe).
public protocol AnalyticsSignalSink: Sendable {
    func send(_ signal: AnalyticsSignal)
}

/// `TelemetryProvider` that forwards VitalStride's typed **product-analytics**
/// events to the analytics backend (self-hosted Aptabase — ADR-0015 §V narrow
/// exception).
///
/// It performs only the pure mapping of `TelemetryEvent` to ``AnalyticsSignal``
/// and delegates transport to an injected ``AnalyticsSignalSink``.
///
/// **Crash/hang diagnostics do NOT travel through this provider.** ADR-0013
/// makes the self-hosted GlitchTip / sentry-cocoa channel the **exclusive**
/// transport for MetricKit crash + hang payloads. To make that architectural
/// separation non-bypassable at the source, this provider **does not override**
/// `record(_ diagnostic:)` and therefore inherits the protocol's default no-op.
/// Registering this provider into `TelemetryService` cannot leak
/// `TelemetryDiagnostic` into the product-analytics backend even if a caller
/// (e.g. `MetricKitDiagnosticCollector`) still fans a diagnostic out to every
/// registered provider.
public struct AnalyticsProvider: TelemetryProvider {
    private let sink: any AnalyticsSignalSink

    public init(sink: any AnalyticsSignalSink) {
        self.sink = sink
    }

    public func track(_ event: TelemetryEvent) {
        sink.send(AnalyticsSignal(event: event))
    }

    // `record(_:)` intentionally omitted — inherits protocol default no-op.
    // See doc-comment above and ADR-0013 §Decision.2 / §Decision.5.
}
