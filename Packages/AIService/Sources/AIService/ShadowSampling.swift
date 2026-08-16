import Foundation

// MARK: - ShadowSampler

/// Decides whether a given `AITaskKind` call should trigger a shadow dual-run
/// this time. Injected into `AIRouter` so tests get deterministic samplers and
/// production gets a real ratio-based one.
///
/// Constitution/spec anchors:
/// - FR-010: sampling rate is configured per kind; main provider result MUST
///   return first; candidate MUST be fire-and-forget.
/// - SC-005: at ratio N%, 100 draws hit ~N% ±2%.
///
/// The router calls `shouldSample` exactly once per `execute` invocation, so an
/// implementer can rely on that call frequency for ratio arithmetic.
public protocol ShadowSampler: Sendable {
    func shouldSample(kind: AITaskKind) -> Bool
}

/// Convenience samplers used in tests and to spell out common cases at
/// composition sites without redeclaring a protocol conformer.
public struct AlwaysShadowSampler: ShadowSampler {
    public init() {}
    public func shouldSample(kind: AITaskKind) -> Bool { true }
}

public struct NeverShadowSampler: ShadowSampler {
    public init() {}
    public func shouldSample(kind: AITaskKind) -> Bool { false }
}

// MARK: - ShadowSignalSink

/// Consumer of `ShadowSignal` values. Same fire-and-forget contract as
/// `RoutingSignalSink`: the router only calls `recordShadow` through a detached
/// `Task` wrapped in `try?`. Implementers MUST NOT block or throw in a way that
/// would matter to the router.
///
/// This sink is safe for any conformer: `ShadowSignal` contains no health
/// data, and the router captures no raw output text to hand anywhere else.
public protocol ShadowSignalSink: Sendable {
    func recordShadow(_ signal: ShadowSignal) async throws
}

/// No-op default so `AIRouter` storage stays non-optional on the hot path.
struct NoOpShadowSignalSink: ShadowSignalSink {
    func recordShadow(_ signal: ShadowSignal) async throws {}
}
