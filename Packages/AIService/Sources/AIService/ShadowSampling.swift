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
/// This sink is safe for any conformer: `ShadowSignal` contains no health data.
/// Anything raw-content-bearing goes through `LocalOnlyShadowPairSink`.
public protocol ShadowSignalSink: Sendable {
    func recordShadow(_ signal: ShadowSignal) async throws
}

/// No-op default so `AIRouter` storage stays non-optional on the hot path.
struct NoOpShadowSignalSink: ShadowSignalSink {
    func recordShadow(_ signal: ShadowSignal) async throws {}
}

// MARK: - TEMP-PRELAUNCH shadow-pair raw sink

/// TEMP-PRELAUNCH: 上架前移除——原始健康值仅供发布前单用户调试（宪法 I）
///
/// A single `(main, candidate)` output pair from a shadow run. This is what
/// Apple Evaluations (US3 T023) grades offline. The response text may embed
/// HealthKit-derived values verbatim, so this payload is kept OFF
/// `ShadowSignal` and off the general `ShadowSignalSink` boundary — a type
/// only ever sees it by explicitly conforming to `LocalOnlyShadowPairSink`.
public struct ShadowPairPayload: Sendable {
    public let mainResponse: String
    public let candidateResponse: String

    public init(mainResponse: String, candidateResponse: String) {
        self.mainResponse = mainResponse
        self.candidateResponse = candidateResponse
    }
}

/// TEMP-PRELAUNCH: 上架前移除——原始健康值仅供发布前单用户调试（宪法 I）
///
/// The ONLY channel through which `AIRouter` will hand out raw shadow-pair
/// output text. Same contract as `LocalOnlyRawDebugSink`: conforming asserts
/// the payload lands only in the device-local SwiftData store configured with
/// `cloudKitDatabase: .none`.
///
/// When no sink is injected, the router never even builds these strings for
/// the candidate — the raw pair is not captured. This is opt-in at the
/// composition root only.
public protocol LocalOnlyShadowPairSink: Sendable {
    func recordShadowPair(_ payload: ShadowPairPayload, for signal: ShadowSignal) async throws
}
