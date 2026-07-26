import Aptabase
import TelemetryKit

/// Adapter facade that wires the real `Aptabase` SDK behind the
/// architecture-neutral `TelemetryProvider` protocol (ADR-0015: self-hosted
/// Aptabase replaces TelemetryDeck as the production analytics provider).
///
/// The facade is the **only** public surface of the `AptabaseAdapter` product.
/// The internal seam overload (`makeProvider(appKey:sink:)`) exists so facade
/// round-trip tests can inject a fake sink; it stays `internal` so external
/// callers cannot bypass the typed-event contract by handing in a raw sink
/// that accepts free-form signals (Constitution §I / §V — ADR-0015).
public enum AptabaseAdapter {
    /// Production entry point.
    ///
    /// Initializes the Aptabase SDK with the supplied self-hosted app key and
    /// host URL, then returns a `TelemetryProvider` backed by the real SDK
    /// sink. Callers get back an `any TelemetryProvider` so the only telemetry
    /// they can emit is the closed `TelemetryEvent` / `TelemetryDiagnostic`
    /// set.
    ///
    /// - Parameters:
    ///   - appKey: The Aptabase application key. For self-hosted instances this
    ///     carries the `SH-` region prefix.
    ///   - host: The self-hosted Aptabase base URL (required when `appKey` is a
    ///     `SH-` key; the SDK disables tracking otherwise).
    public static func makeProvider(appKey: String, host: String) -> any TelemetryProvider {
        Aptabase.shared.initialize(appKey: appKey, with: InitOptions(host: host))
        return makeProvider(appKey: appKey, sink: AptabaseSDKSink())
    }

    /// Internal seam used by facade round-trip tests to inject a fake sink.
    ///
    /// Not part of the product's public API — Constitution §I hinges on the
    /// fact that external callers cannot supply their own sink and therefore
    /// cannot smuggle raw values through it.
    static func makeProvider(appKey _: String, sink: any AnalyticsSignalSink) -> any TelemetryProvider {
        AnalyticsProvider(sink: sink)
    }
}
