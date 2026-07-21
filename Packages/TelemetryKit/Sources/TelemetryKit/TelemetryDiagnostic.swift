/// A structured, privacy-bounded crash / hang diagnostic captured by
/// MetricKit and routed through the telemetry channel (ADR-0012).
///
/// This is a **closed type**, deliberately NOT a `TelemetryEvent`: crash and
/// hang call-stacks are inherently free-form and cannot travel as a
/// `TelemetryEvent` parameter (ADR-0011 "typed-event-only"). ADR-0012 narrows
/// that rule to admit exactly this one structured shape — a diagnostic kind,
/// coarse OS/app metadata, and a list of **already-sanitized** symbol frames.
///
/// Construction never accepts free-form call-site strings: `frames` must be
/// produced by ``DiagnosticSanitizer`` from an `MXCallStackTree`, which keeps
/// only symbol names + binary offsets and drops everything else. HealthKit
/// values and PII are structurally absent (Constitution §I applies in full).
public struct TelemetryDiagnostic: Sendable, Equatable {
    /// What MetricKit reported. Only crash and hang are in scope (ADR-0012);
    /// other `MXDiagnostic` subclasses are ignored by the collector.
    public enum Kind: String, Sendable, Equatable, CaseIterable {
        case crash
        case hang
    }

    public let kind: Kind
    /// OS version string as reported by MetricKit metadata, e.g. `"26.5.2"`.
    /// Coarse device/OS metadata only — never a device identifier.
    public let osVersion: String
    /// App build version (`CFBundleVersion`) the diagnostic was captured on,
    /// e.g. `"5"`. Needed to pick the right dSYM for local symbolication.
    public let appBuild: String
    /// Sanitized crashing/stalled call stack: one string per frame, symbol +
    /// offset only. Produced exclusively by ``DiagnosticSanitizer``.
    public let frames: [String]
    /// Optional termination reason / exception code for crashes (e.g.
    /// `"EXC_BAD_ACCESS"`). Canonical short token only; nil for hangs.
    public let terminationReason: String?

    public init(
        kind: Kind,
        osVersion: String,
        appBuild: String,
        frames: [String],
        terminationReason: String? = nil
    ) {
        self.kind = kind
        self.osVersion = osVersion
        self.appBuild = appBuild
        self.frames = frames
        self.terminationReason = terminationReason
    }
}
