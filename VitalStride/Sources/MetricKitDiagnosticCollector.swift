#if canImport(MetricKit) && !os(watchOS)
import Foundation
import MetricKit
import os
import TelemetryKit

/// Subscribes to MetricKit and forwards its two payload streams down two
/// deliberately separate channels:
///
/// - **Diagnostics** (`MXDiagnosticPayload`: crash + hang) → the telemetry
///   diagnostics channel via `DiagnosticBuilder` (ADR-0012 / ADR-0013). In
///   Release this is owned by sentry-cocoa (see `emit(...)`).
/// - **Performance metrics** (`MXMetricPayload`: launch / hang / memory / CPU)
///   → the product-analytics channel (Aptabase, ADR-0015 §perf) via the
///   unit-tested `MetricPayloadParser`.
///
/// MetricKit delivers payloads on the launch AFTER the event occurred. For the
/// diagnostics path this collector extracts each diagnostic's call-stack into
/// raw frame strings and hands them to the package-side, unit-tested
/// `DiagnosticBuilder`, which enforces sanitization.
///
/// The collector itself is deliberately thin: framework subscription + JSON
/// hand-off only. All privacy-critical assembly and fragile parsing live in
/// TelemetryKit (`DiagnosticBuilder` / `DiagnosticSanitizer` /
/// `MetricPayloadParser`), which are tested without MetricKit.
///
/// Not available on watchOS (MetricKit diagnostics are iOS/macOS).
final class MetricKitDiagnosticCollector: NSObject, MXMetricManagerSubscriber {

    private static let logger = Logger(subsystem: "com.vitalstride", category: "MetricKit")

    /// Start receiving diagnostic payloads. Call once at app launch.
    func start() {
        MXMetricManager.shared.add(self)
    }

    func stop() {
        MXMetricManager.shared.remove(self)
    }

    // MARK: MXMetricManagerSubscriber

    func didReceive(_ payloads: [MXMetricPayload]) {
        // ADR-0015 §perf (阶段 4): performance metrics (launch / hang / memory /
        // CPU) travel through the **analytics** channel (Aptabase), a channel
        // entirely separate from the crash/hang **diagnostics** channel below
        // (sentry-cocoa / GlitchTip, ADR-0013). All parsing + unit conversion +
        // histogram aggregation lives in the unit-tested, MetricKit-free
        // `MetricPayloadParser`; this seam stays thin.
        for payload in payloads {
            let events = MetricPayloadParser.events(fromPayloadJSON: payload.jsonRepresentation())
            for event in events {
                #if DEBUG
                // §Decision.4 / SDK TrackingMode: DEBUG does not transport.
                Self.logger.debug(
                    "MetricKit perf \(event.eventName, privacy: .public) captured — not sent in DEBUG"
                )
                #else
                TelemetryService.shared.trackNonisolated(event)
                #endif
            }
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            handle(payload)
        }
    }

    // MARK: - Payload handling

    private func handle(_ payload: MXDiagnosticPayload) {
        for crash in payload.crashDiagnostics ?? [] {
            let frames = Self.flattenFrames(from: crash.callStackTree)
            let reason = crash.exceptionType.map { "EXC_\($0.intValue)" }
                ?? crash.signal.map { "SIG_\($0.intValue)" }
            emit(kind: .crash,
                 osVersion: crash.metaData.osVersion,
                 appBuild: crash.metaData.applicationBuildVersion,
                 frames: frames, reason: reason)
        }

        for hang in payload.hangDiagnostics ?? [] {
            let frames = Self.flattenFrames(from: hang.callStackTree)
            emit(kind: .hang,
                 osVersion: hang.metaData.osVersion,
                 appBuild: hang.metaData.applicationBuildVersion,
                 frames: frames, reason: nil)
        }
    }

    private func emit(
        kind: TelemetryDiagnostic.Kind,
        osVersion: String,
        appBuild: String,
        frames: [String],
        reason: String?
    ) {
        guard let diagnostic = DiagnosticBuilder.make(
            kind: kind,
            rawOSVersion: osVersion,
            rawAppBuild: appBuild,
            rawFrames: frames,
            rawTerminationReason: reason
        ) else {
            Self.logger.debug("Dropped \(kind.rawValue, privacy: .public) diagnostic: no usable frames")
            return
        }

        #if DEBUG
        // ADR-0012 §Decision.4: DEBUG does not transport. Log locally instead.
        Self.logger.debug(
            "MetricKit \(kind.rawValue, privacy: .public) diagnostic captured (\(diagnostic.frames.count, privacy: .public) frames) — not sent in DEBUG"
        )
        #else
        // spec 015-glitchtip-crash-reporting (MY-1311/T002): sentry-cocoa
        // subscribes to the same `MXDiagnosticPayload` stream via
        // `options.enableMetricKit = true`, so forwarding the diagnostic
        // through the telemetry channel here would double-report every
        // crash / hang. Keep the collector's `start()` / `stop()` /
        // `didReceive(_:)` seam intact so tests can still exercise the
        // flattening logic; only the Release-branch business transport is
        // removed. The `diagnostic` variable is intentionally unused below.
        _ = diagnostic
        #endif
    }

    // MARK: - Call-stack flattening (pure; testable via jsonRepresentation)

    /// Flatten an `MXCallStackTree` into raw per-frame strings, top-of-stack
    /// first. MetricKit only exposes the tree as JSON, so this parses the
    /// documented `callStackTree` → `callStacks[].callStackRootFrames[]`
    /// structure, walking each frame's `subFrames` chain. Raw output is
    /// intentionally unsanitized here — `DiagnosticBuilder` sanitizes.
    static func flattenFrames(from tree: MXCallStackTree) -> [String] {
        let data = tree.jsonRepresentation()
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let stacks = root["callStacks"] as? [[String: Any]]
        else {
            return []
        }

        var frames: [String] = []
        for stack in stacks {
            guard let roots = stack["callStackRootFrames"] as? [[String: Any]] else { continue }
            for rootFrame in roots {
                appendFrames(from: rootFrame, into: &frames)
            }
        }
        return frames
    }

    /// Depth-first walk of a frame and its `subFrames`, emitting a
    /// `"<binary> <symbol-or-address> +<offset>"` string per frame.
    private static func appendFrames(from frame: [String: Any], into frames: inout [String]) {
        let binary = (frame["binaryName"] as? String) ?? "?"
        let offset = (frame["offsetIntoBinaryTextSegment"] as? NSNumber)?.intValue ?? 0
        // MetricKit does not pre-symbolicate; `address` is what we resolve later
        // against the dSYM. A symbol name may be present on symbolicated OSes.
        let symbol = (frame["symbolName"] as? String)
            ?? (frame["address"] as? NSNumber).map { "0x\(String($0.uintValue, radix: 16))" }
            ?? "?"
        frames.append("\(binary) \(symbol) +\(offset)")

        if let subFrames = frame["subFrames"] as? [[String: Any]] {
            for sub in subFrames {
                appendFrames(from: sub, into: &frames)
            }
        }
    }
}
#endif
