import Foundation

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
