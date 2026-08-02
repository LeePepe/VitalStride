import Foundation

/// In-package value type mirroring a single bandit arm's persistent state.
///
/// `AIService` does NOT depend on `VitalModels` directly — the concrete
/// storage-backed implementation of `BanditArmStateRepository` lives at
/// composition (app target or a dedicated adapter layer) and is responsible
/// for translating its own `@Model` entity to/from this value.
///
/// **Carries no health data.** Every field here is routing metadata + a
/// scalar reward (spec 019 FR-018 permanent state). Raw prompt/response
/// text — which may embed HealthKit-derived values — deliberately never
/// lives on any bandit type.
public struct BanditArmState: Sendable, Equatable {
    public let kind: AITaskKind
    public let deviceTier: DeviceTier
    public let provider: String
    public let count: Int
    public let rewardSum: Double
    public let updatedAt: Date

    public init(
        kind: AITaskKind,
        deviceTier: DeviceTier,
        provider: String,
        count: Int,
        rewardSum: Double,
        updatedAt: Date
    ) {
        self.kind = kind
        self.deviceTier = deviceTier
        self.provider = provider
        self.count = count
        self.rewardSum = rewardSum
        self.updatedAt = updatedAt
    }
}

/// Read/write boundary for `BanditArmState`. The routing layer talks only
/// to this protocol; the concrete impl (SwiftData-backed
/// `BanditArmStateEntry`, in-memory fake for tests, etc.) is wired in by
/// the composition root.
///
/// Constraints (mirror `RoutingSignalSink`, spec 019 FR-008):
/// - `upsert` MAY throw. `AIRouter` calls it through a detached
///   fire-and-forget `Task` wrapped in `try?`, so slow or failing writes
///   never affect the user-facing AI response or its latency. The
///   throwing signature is what lets a real conformer (SwiftData
///   `ModelContext.save()` throws) participate without an internal
///   swallow — and lets tests use a throwing double to actually exercise
///   the fire-and-forget path.
/// - `loadAll` is called on the AI hot path; concrete impls should keep
///   the returned set bounded (a few dozen rows — `AITaskKind` × `DeviceTier`
///   × provider).
public protocol BanditArmStateRepository: Sendable {
    func loadAll() async -> [BanditArmState]
    func upsert(
        kind: AITaskKind,
        deviceTier: DeviceTier,
        provider: String,
        deltaCount: Int,
        deltaReward: Double
    ) async throws
}

/// Deterministic uniform-in-[0,1) sampler. Injected into `AIRoutingBandit`
/// so tests can drive ε-greedy branches with a seeded stream — `Math.random`
/// / system-clock randomness would make bandit behavior untestable.
///
/// A conforming production implementation (`SystemDeterministicSampler`) is
/// provided below for the composition root; tests inject their own seeded
/// impl.
public protocol DeterministicSampler: Sendable {
    /// Returns a uniformly-distributed value in the half-open interval `[0, 1)`.
    /// MUST be safe to call concurrently.
    func nextDouble() -> Double
}

/// Production sampler backed by `SystemRandomNumberGenerator` — reseeds the
/// generator on every call so there is no shared mutable state. Trades a
/// tiny per-call cost for `Sendable` safety without `@unchecked`.
public struct SystemDeterministicSampler: DeterministicSampler {
    public init() {}

    public func nextDouble() -> Double {
        var rng = SystemRandomNumberGenerator()
        return Double.random(in: 0..<1, using: &rng)
    }
}

/// In-memory no-op repository. Used as the safe default when a router is
/// constructed without a bandit-backed store (unit tests, early boot, etc.)
/// so the router itself can keep the repo storage non-optional. `loadAll`
/// returns an empty snapshot and `upsert` drops writes on the floor —
/// bandit degrades gracefully to prior-only behavior.
public struct NoOpBanditArmStateRepository: BanditArmStateRepository {
    public init() {}
    public func loadAll() async -> [BanditArmState] { [] }
    public func upsert(
        kind: AITaskKind,
        deviceTier: DeviceTier,
        provider: String,
        deltaCount: Int,
        deltaReward: Double
    ) async throws {}
}
