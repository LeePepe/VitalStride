import Foundation

/// In-package value type describing a single routing decision + its runtime
/// telemetry. Emitted best-effort by `AIRouter.execute` after every completed
/// request; consumed by an injected `RoutingSignalSink` (typically an app-target
/// component that writes `RoutingSignalEntry` into the local SwiftData store on
/// the `.none` partition — spec 019, `RoutingSignalEntry` lives in `VitalModels`).
///
/// **Carries no health data.** Every field here is routing metadata (which
/// provider, how fast, did the schema parse). Raw prompt/response text — which
/// may embed HealthKit-derived values — does not exist anywhere in this layer:
/// the router never captures it and no type here can carry it. That is what
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
/// contain no health data, and the routing layer has no other channel that
/// could hand PHI to a conformer.
public protocol RoutingSignalSink: Sendable {
    func record(_ signal: RoutingSignal) async throws
}

/// No-op sink used as the default when the app hasn't injected a real sink
/// (unit tests, headless configurations, early boot). Keeps the `AIRouter`
/// storage non-optional so hot paths avoid an optional check per call.
struct NoOpRoutingSignalSink: RoutingSignalSink {
    func record(_ signal: RoutingSignal) async throws {}
}
