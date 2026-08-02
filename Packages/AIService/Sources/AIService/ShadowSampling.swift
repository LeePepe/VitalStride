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

/// Deterministic per-kind ratio sampler.
///
/// Semantics: for a configured rate `p` on some kind, the sampler fires
/// approximately `p` fraction of the time over the long run. Concretely it uses
/// an accumulator per kind: each call adds `p`; when the accumulator crosses 1
/// it fires and subtracts 1. Over 100 calls at `p=0.2` this hits exactly 20,
/// well inside the ±2% SC-005 tolerance — and unlike RNG-based sampling it
/// stays deterministic under test.
///
/// Kinds without an entry (or with rate `0`) never fire. Rate is clamped to
/// `[0, 1]` at construction — an out-of-range rate is a config bug, not a
/// runtime one, so the clamp is silent by design (no crash, no log).
public final class RatioShadowSampler: ShadowSampler, @unchecked Sendable {
    private let rates: [AITaskKind: Double]
    private let lock = NSLock()
    private var accumulators: [AITaskKind: Double] = [:]

    public init(rates: [AITaskKind: Double]) {
        var clamped: [AITaskKind: Double] = [:]
        for (kind, rate) in rates {
            clamped[kind] = min(max(rate, 0), 1)
        }
        self.rates = clamped
    }

    public func shouldSample(kind: AITaskKind) -> Bool {
        guard let rate = rates[kind], rate > 0 else { return false }

        lock.lock()
        defer { lock.unlock() }

        let current = (accumulators[kind] ?? 0) + rate
        if current >= 1 {
            accumulators[kind] = current - 1
            return true
        } else {
            accumulators[kind] = current
            return false
        }
    }
}

// MARK: - ShadowSignal

/// Bypass telemetry for one shadow dual-run. Emitted best-effort by
/// `AIRouter.execute` after the candidate provider finishes (whether it
/// succeeded or failed). Carries only routing metadata — no health data,
/// no raw prompt/response text. That split mirrors `RoutingSignal`.
///
/// `candidateSucceeded == false` is the `shadowFailed` signal called out in
/// the spec's edge case: candidate errors do not affect the already-returned
/// main result; the router just records one of these.
public struct ShadowSignal: Sendable {
    public let kind: AITaskKind
    public let mainProvider: String
    public let candidateProvider: String
    public let deviceTier: DeviceTier
    public let mainLatencyMs: Int
    /// `nil` when the candidate failed before producing a response.
    public let candidateLatencyMs: Int?
    public let candidateSucceeded: Bool
    /// Coarse category (`networkError` / `httpError(...)` / `unknown`, matching
    /// `AIProviderChain.errorCategory`) when `candidateSucceeded == false`;
    /// `nil` on success.
    public let candidateErrorCategory: String?
    public let timestamp: Date

    public init(
        kind: AITaskKind,
        mainProvider: String,
        candidateProvider: String,
        deviceTier: DeviceTier,
        mainLatencyMs: Int,
        candidateLatencyMs: Int?,
        candidateSucceeded: Bool,
        candidateErrorCategory: String?,
        timestamp: Date = Date()
    ) {
        self.kind = kind
        self.mainProvider = mainProvider
        self.candidateProvider = candidateProvider
        self.deviceTier = deviceTier
        self.mainLatencyMs = mainLatencyMs
        self.candidateLatencyMs = candidateLatencyMs
        self.candidateSucceeded = candidateSucceeded
        self.candidateErrorCategory = candidateErrorCategory
        self.timestamp = timestamp
    }
}

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
