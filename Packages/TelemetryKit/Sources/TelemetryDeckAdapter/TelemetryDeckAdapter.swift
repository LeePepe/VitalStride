import TelemetryDeck
import TelemetryKit

/// Adapter facade that wires the real `TelemetryDeck` SDK behind the
/// architecture-neutral `TelemetryProvider` protocol.
///
/// The facade is the **only** public surface of the `TelemetryDeckAdapter`
/// product. The internal seam overload (`makeProvider(appID:sink:)`) exists so
/// facade round-trip tests (P1-I) can inject a fake sink; it stays `internal`
/// so external callers cannot bypass the typed-event contract by handing in a
/// raw sink that accepts free-form signals (Constitution §I / §V — ADR-0011).
public enum TelemetryDeckAdapter {
    /// Production entry point.
    ///
    /// Initializes the TelemetryDeck SDK with the supplied application id and
    /// returns a `TelemetryProvider` backed by the real SDK sink. Callers get
    /// back an `any TelemetryProvider` so the only telemetry they can emit is
    /// the closed `TelemetryEvent` / `TelemetryDiagnostic` set.
    public static func makeProvider(appID: String) -> any TelemetryProvider {
        TelemetryDeck.initialize(config: .init(appID: appID))
        return makeProvider(appID: appID, sink: TelemetryDeckSDKSink())
    }

    /// Internal seam used by facade round-trip tests to inject a fake sink.
    ///
    /// Not part of the product's public API — Constitution §I hinges on the
    /// fact that external callers cannot supply their own sink and therefore
    /// cannot smuggle raw values through it.
    static func makeProvider(appID _: String, sink: any TelemetryDeckSignalSink) -> any TelemetryProvider {
        TelemetryDeckProvider(sink: sink)
    }
}
