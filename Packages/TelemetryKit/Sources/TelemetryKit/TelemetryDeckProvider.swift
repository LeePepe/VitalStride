/// The one-method seam the real TelemetryDeck SDK adapter implements. Keeping
/// the SDK behind this protocol means the entire mapping + provider logic is
/// unit-testable with a fake sink, and the real `import TelemetryDeck` is a
/// single thin file added last (ADR-0012 path B).
///
/// Implementations must be safe to call from any isolation domain (the SDK's
/// `TelemetryDeck.signal(_:parameters:)` is itself thread-safe).
public protocol TelemetryDeckSignalSink: Sendable {
    func send(_ signal: TelemetryDeckSignal)
}

/// `TelemetryProvider` that forwards VitalStride's typed **product-analytics**
/// events to TelemetryDeck (ADR-0011 §V narrow exception).
///
/// It performs only the pure mapping of `TelemetryEvent` to
/// ``TelemetryDeckSignal`` and delegates transport to an injected
/// ``TelemetryDeckSignalSink``.
///
/// **Crash/hang diagnostics do NOT travel through this provider.** ADR-0013
/// makes the self-hosted GlitchTip / sentry-cocoa channel the **exclusive**
/// transport for MetricKit crash + hang payloads (§Decision.2 replaces the
/// ADR-0012 hand-rolled path; §Decision.5 keeps product analytics off this
/// crash-reporting channel). To make that architectural separation
/// non-bypassable at the source, this provider **does not override**
/// `record(_ diagnostic:)` and therefore inherits the protocol's default
/// no-op. Registering the TelemetryDeck provider into `TelemetryService`
/// cannot leak `TelemetryDiagnostic` into the product-analytics backend even
/// if a caller (e.g. `MetricKitDiagnosticCollector`) still fans a diagnostic
/// out to every registered provider.
public struct TelemetryDeckProvider: TelemetryProvider {
    private let sink: any TelemetryDeckSignalSink

    public init(sink: any TelemetryDeckSignalSink) {
        self.sink = sink
    }

    public func track(_ event: TelemetryEvent) {
        sink.send(TelemetryDeckSignal(event: event))
    }

    // `record(_:)` intentionally omitted — inherits protocol default no-op.
    // See doc-comment above and ADR-0013 §Decision.2 / §Decision.5.
}
