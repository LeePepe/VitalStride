/// A backend-neutral representation of one signal to send to TelemetryDeck.
///
/// This value type is the seam between VitalStride's typed telemetry
/// (`TelemetryEvent` / `TelemetryDiagnostic`) and the TelemetryDeck SDK. The
/// mapping (event → signal) is pure and unit-testable; the actual SDK call is
/// isolated behind ``TelemetryDeckSignalSink`` so the real `import TelemetryDeck`
/// lives in one thin adapter (ADR-0012 path B: architecture first, SDK last).
///
/// `signalType` and `parameters` are already-canonical ASCII (events carry
/// `TelemetryIdentifier`s; diagnostics are sanitized upstream by
/// ``DiagnosticSanitizer``), so this type introduces no new free-form or
/// health-value surface — Constitution §I holds by construction.
public struct TelemetryDeckSignal: Sendable, Equatable {
    /// TelemetryDeck signal name, e.g. `"workout_started"` or
    /// `"diagnostic_hang"`.
    public let signalType: String
    /// Flat string parameters. Keys and values are canonical ASCII.
    public let parameters: [String: String]

    public init(signalType: String, parameters: [String: String] = [:]) {
        self.signalType = signalType
        self.parameters = parameters
    }
}

// MARK: - Mapping from typed telemetry to signals

public extension TelemetryDeckSignal {
    /// Map a product-analytics event to a signal. Reuses the event's own
    /// `eventName` / `parameters` (already ASCII, already §I-safe).
    init(event: TelemetryEvent) {
        var params: [String: String] = [:]
        for pair in event.parameters {
            params[pair.key] = pair.value
        }
        self.init(signalType: event.eventName, parameters: params)
    }

    /// Map a MetricKit diagnostic to a signal. The call stack is joined into a
    /// single newline-delimited parameter so the whole symbolication-ready
    /// stack rides one signal; every frame was sanitized upstream.
    init(diagnostic: TelemetryDiagnostic) {
        var params: [String: String] = [
            "kind": diagnostic.kind.rawValue,
            "os_version": diagnostic.osVersion,
            "app_build": diagnostic.appBuild,
            "frame_count": "\(diagnostic.frames.count)",
        ]
        if let reason = diagnostic.terminationReason {
            params["termination_reason"] = reason
        }
        // Frames joined with a literal "\n" separator — TelemetryDeck stores the
        // value verbatim; downstream symbolication splits on newline.
        params["frames"] = diagnostic.frames.joined(separator: "\n")
        self.init(signalType: "diagnostic_\(diagnostic.kind.rawValue)", parameters: params)
    }
}
