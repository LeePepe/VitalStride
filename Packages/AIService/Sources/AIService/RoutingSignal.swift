import Foundation

/// In-package value type describing a single routing decision + its runtime
/// telemetry. Emitted best-effort by `AIRouter.execute` after every completed
/// request; consumed by an injected `RoutingSignalSink` (typically an app-target
/// component that writes `RoutingSignalEntry` into the local SwiftData store on
/// the `.none` partition — spec 019, `RoutingSignalEntry` lives in `VitalModels`).
///
/// **Carries no health data.** Every field here is routing metadata (which
/// provider, how fast, did the schema parse). Raw prompt/response text — which
/// may embed HealthKit-derived values — deliberately does NOT live on this type;
/// see `RawDebugPayload` + `LocalOnlyRawDebugSink` below. That split is what
/// keeps the general-purpose sink boundary safe for any conformer.
///
/// AIService intentionally does NOT depend on VitalModels here — the sink
/// protocol keeps the storage boundary out of the routing layer (constitution V:
/// packages stay decoupled, chain order not reversed).
public struct RoutingSignal: Sendable {
    public let kind: AITaskKind
    public let provider: String
    public let deviceTier: DeviceTier
    public let latencyMs: Int
    public let schemaValid: Bool
    public let accepted: Bool?
    public let timestamp: Date

    public init(
        kind: AITaskKind,
        provider: String,
        deviceTier: DeviceTier,
        latencyMs: Int,
        schemaValid: Bool,
        accepted: Bool? = nil,
        timestamp: Date = Date()
    ) {
        self.kind = kind
        self.provider = provider
        self.deviceTier = deviceTier
        self.latencyMs = latencyMs
        self.schemaValid = schemaValid
        self.accepted = accepted
        self.timestamp = timestamp
    }
}

/// Consumer of `RoutingSignal` values emitted by `AIRouter`. Implementations
/// MUST NOT throw or block the router — the router only ever calls `record`
/// through a detached fire-and-forget `Task` wrapped in `try?`.
///
/// This protocol is safe to conform to from anywhere: the values it receives
/// contain no health data. Anything PHI-bearing goes through
/// `LocalOnlyRawDebugSink` instead, which carries a much stricter contract.
public protocol RoutingSignalSink: Sendable {
    func record(_ signal: RoutingSignal) async throws
}

/// No-op sink used as the default when the app hasn't injected a real sink
/// (unit tests, headless configurations, early boot). Keeps the `AIRouter`
/// storage non-optional so hot paths avoid an optional check per call.
struct NoOpRoutingSignalSink: RoutingSignalSink {
    func record(_ signal: RoutingSignal) async throws {}
}

// MARK: - TEMP-PRELAUNCH controlled exception

/// TEMP-PRELAUNCH: 上架前移除——原始健康值仅供发布前单用户调试（宪法 I）
///
/// Raw prompt/response text for a single routing call. This text MAY embed
/// HealthKit-derived values verbatim, so it is deliberately kept OFF
/// `RoutingSignal` and off the general `RoutingSignalSink` boundary: a type
/// only ever sees this payload by explicitly conforming to
/// `LocalOnlyRawDebugSink`, which is a documented, auditable opt-in rather than
/// an incidental consequence of consuming routing telemetry.
///
/// FR-017 removal is then a three-line delete: this type, the protocol below,
/// and `AIRouter.rawDebugSink`. `RoutingSignal` needs no change — its permanent
/// shape is already raw-free (plan.md: 永久态 **无** raw 字段).
public struct RawDebugPayload: Sendable {
    public let prompt: String
    public let response: String

    public init(prompt: String, response: String) {
        self.prompt = prompt
        self.response = response
    }
}

/// TEMP-PRELAUNCH: 上架前移除——原始健康值仅供发布前单用户调试（宪法 I）
///
/// The ONLY channel through which `AIRouter` will hand out raw, potentially
/// health-bearing prompt/response text.
///
/// FR-018 (spec 019) — conforming to this protocol is an assertion by the
/// conformer that it writes the payload **only** into the device-local SwiftData
/// store configured with `cloudKitDatabase: .none`, and nowhere else. A
/// conformer MUST NOT `print` it, emit it via `os_log` / `Logger`, upload it to
/// Aptabase or GlitchTip, sync it through CloudKit, or otherwise let it leave
/// the device.
///
/// The router does not inject a default: when no `LocalOnlyRawDebugSink` is
/// supplied, the raw text is **never materialized at all** (see
/// `AIRouter.execute`) — not captured, not held, not passed. The exception is
/// opt-in at the composition root, not on by default.
public protocol LocalOnlyRawDebugSink: Sendable {
    func recordRawDebug(_ payload: RawDebugPayload, for signal: RoutingSignal) async throws
}
