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

/// `TelemetryProvider` that forwards VitalStride's typed telemetry to
/// TelemetryDeck (ADR-0011 for events, ADR-0012 for diagnostics).
///
/// It performs only the pure mapping to ``TelemetryDeckSignal`` and delegates
/// transport to an injected ``TelemetryDeckSignalSink``. Both product events and
/// MetricKit diagnostics ride the same single third-party channel — no second
/// SDK (ADR-0012 §Decision.5).
public struct TelemetryDeckProvider: TelemetryProvider {
    private let sink: any TelemetryDeckSignalSink

    public init(sink: any TelemetryDeckSignalSink) {
        self.sink = sink
    }

    public func track(_ event: TelemetryEvent) {
        sink.send(TelemetryDeckSignal(event: event))
    }

    public func record(_ diagnostic: TelemetryDiagnostic) {
        sink.send(TelemetryDeckSignal(diagnostic: diagnostic))
    }
}
