/// Pure assembly of a ``TelemetryDiagnostic`` from already-extracted MetricKit
/// primitives (ADR-0012). MetricKit's `MXDiagnostic` / `MXCallStackTree` types
/// only exist on device and are not available to this cross-platform package,
/// so the app-side collector extracts raw primitive values (a metadata dict and
/// a list of raw frame descriptions) and hands them here. This keeps the
/// privacy-critical assembly — where sanitization is enforced — unit-testable
/// without MetricKit.
///
/// Every field is funnelled through ``DiagnosticSanitizer`` so no unsanitized
/// value can reach a ``TelemetryDiagnostic`` (and thus the transport).
public enum DiagnosticBuilder {

    /// Assemble a sanitized diagnostic. Returns `nil` when, after sanitization,
    /// there are no usable frames — an empty stack is not worth transporting and
    /// most likely means the raw input was malformed.
    ///
    /// - Parameters:
    ///   - kind: crash or hang (the collector only forwards these two).
    ///   - rawOSVersion: e.g. MetricKit's `metaData.osVersion`.
    ///   - rawAppBuild: e.g. MetricKit's `applicationVersion` / `CFBundleVersion`.
    ///   - rawFrames: raw per-frame description strings, top-of-stack first.
    ///   - rawTerminationReason: crash exception token, or nil for hangs.
    public static func make(
        kind: TelemetryDiagnostic.Kind,
        rawOSVersion: String,
        rawAppBuild: String,
        rawFrames: [String],
        rawTerminationReason: String? = nil
    ) -> TelemetryDiagnostic? {
        let frames = DiagnosticSanitizer.sanitizeFrames(rawFrames)
        guard !frames.isEmpty else { return nil }

        return TelemetryDiagnostic(
            kind: kind,
            osVersion: DiagnosticSanitizer.sanitizeVersion(rawOSVersion),
            appBuild: DiagnosticSanitizer.sanitizeVersion(rawAppBuild),
            frames: frames,
            terminationReason: DiagnosticSanitizer.sanitizeTerminationReason(rawTerminationReason)
        )
    }
}
