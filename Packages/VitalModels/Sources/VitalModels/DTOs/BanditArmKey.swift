import Foundation

/// Sendable, value-type identity of a bandit arm.
///
/// `BanditArmKey` is the cross-actor boundary for referring to a bandit arm without
/// touching the `@Model` `BanditArmStateEntry`. `BanditArmStateEntry` is a SwiftData
/// managed object and is inherently bound to its `ModelContext`; passing it across
/// actor boundaries is unsafe. Consumers (e.g. `AIRouter` in AIService) work with
/// `BanditArmKey` + `BanditArmStateSnapshot` values instead.
///
/// Fields are raw `String` values on purpose: VitalModels does not depend on AIService
/// (layer boundary — spec 019 depends_on: VitalModels ⟵ AIService, not the reverse),
/// so the domain enums (`AITaskKind`, `DeviceTier`) live in AIService and callers map
/// `rawValue` ↔ `String` at the boundary.
public struct BanditArmKey: Hashable, Sendable, Codable {
    public let kind: String
    public let deviceTier: String
    public let provider: String

    public init(kind: String, deviceTier: String, provider: String) {
        self.kind = kind
        self.deviceTier = deviceTier
        self.provider = provider
    }
}
