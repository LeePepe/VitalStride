import Foundation

/// In-package value type describing a single routing decision + its runtime
/// telemetry. Emitted best-effort by `AIRouter.execute` after every completed
/// request; consumed by an injected `RoutingSignalSink` (typically an app-target
/// component that writes `RoutingSignalEntry` into the local SwiftData store on
/// the `.none` partition — spec 019, `RoutingSignalEntry` lives in `VitalModels`).
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

    // TEMP-PRELAUNCH: 上架前移除——原始健康值仅供发布前单用户调试（宪法 I）
    public let rawPromptDebug: String?
    // TEMP-PRELAUNCH: 上架前移除——原始健康值仅供发布前单用户调试（宪法 I）
    public let rawResponseDebug: String?

    public init(
        kind: AITaskKind,
        provider: String,
        deviceTier: DeviceTier,
        latencyMs: Int,
        schemaValid: Bool,
        accepted: Bool? = nil,
        timestamp: Date = Date(),
        rawPromptDebug: String? = nil,
        rawResponseDebug: String? = nil
    ) {
        self.kind = kind
        self.provider = provider
        self.deviceTier = deviceTier
        self.latencyMs = latencyMs
        self.schemaValid = schemaValid
        self.accepted = accepted
        self.timestamp = timestamp
        self.rawPromptDebug = rawPromptDebug
        self.rawResponseDebug = rawResponseDebug
    }
}

/// Consumer of `RoutingSignal` values emitted by `AIRouter`. Implementations
/// MUST NOT throw or block the router — the router only ever calls `record`
/// through a detached fire-and-forget `Task` wrapped in `try?`.
///
/// FR-018 (spec 019): raw health-carrying debug fields MAY be forwarded ONLY
/// to a `RoutingSignalSink` that writes into the local, cloud-off SwiftData
/// store. They MUST NOT be printed, sent to unified log, uploaded to Aptabase
/// or GlitchTip, or otherwise leave the device.
public protocol RoutingSignalSink: Sendable {
    func record(_ signal: RoutingSignal) async throws
}

/// No-op sink used as the default when the app hasn't injected a real sink
/// (unit tests, headless configurations, early boot). Keeps the `AIRouter`
/// storage non-optional so hot paths avoid an optional check per call.
struct NoOpRoutingSignalSink: RoutingSignalSink {
    func record(_ signal: RoutingSignal) async throws {}
}
