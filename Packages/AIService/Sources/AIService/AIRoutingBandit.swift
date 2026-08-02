import Foundation

/// Value-type bandit that picks the primary `AIProvider` name to try for a
/// given `(kind, deviceTier)`. Pure function decision — no stored mutable
/// state; the arm-count/reward accumulator lives on the caller's side
/// (`BanditArmStateRepository`).
///
/// **Algorithm — ε-greedy with a Bayesian-smoothed empirical mean.**
///
/// For each available provider `p`:
/// ```
/// count      = arm(kind, tier, p).count      (0 if never observed)
/// rewardSum  = arm(kind, tier, p).rewardSum  (0 if never observed)
/// priorMean  = staticPrior[kind][tier][p]    (0 if absent)
/// posterior  = (priorStrength * priorMean + rewardSum) / (priorStrength + Double(count))
/// ```
///
/// Selection:
/// 1. **Day-1 gate** — if `sum(count) == 0` across every arm considered,
///    return `argmax priorMean` (tie-break: input order in
///    `availableProviders`). No sampler call. This is what makes SC-006's
///    KL ≈ 0 assertion hold exactly at zero — ε-greedy exploration would
///    otherwise leak uniform noise onto the Day-1 distribution.
/// 2. **Warm ε-greedy** — otherwise, with probability `explorationEpsilon`
///    sample uniformly from `availableProviders`; else return
///    `argmax posterior` (same tie-break as above).
///
/// **Reward — bounded scalar in `[0, 1]`.** No health values ever touch
/// this function; the caller pre-reduces the raw signal to booleans + an
/// optional offline score.
///
/// Constitution / spec anchors:
/// - FR-013: static prior initialized to the Stage 1 static strategy →
///   Day-1 route distribution matches Stage 1.
/// - FR-012: incapable on-device arm is filtered by the CALLER before
///   `availableProviders` reaches the bandit — the bandit itself only
///   picks from names in that list, so on-device probability = 0 on
///   `cloudOnly` follows automatically.
/// - Constitution I: `reward = f(Bool, Bool?, Double?)` — no HealthKit
///   values as inputs, none as outputs.
/// - Constitution V: bandit is an in-package value type; no third-party
///   AI SDK, no chain replacement — see `AIRouter` for how the chain is
///   still delegated to.
public struct AIRoutingBandit: Sendable {

    /// `staticPrior[kind][tier][providerName] = priorWeight`. Higher =
    /// more preferred a-priori. Missing entries default to 0.
    public typealias StaticPrior = [AITaskKind: [DeviceTier: [String: Double]]]

    // MARK: - State (all value-typed / captured)

    public let explorationEpsilon: Double
    public let staticPrior: StaticPrior
    /// Virtual sample count assigned to the prior when blending with the
    /// empirical mean. `1.0` = "one virtual sample of prior evidence"; a
    /// single real observation with reward > prior would move the score
    /// toward the empirical mean by ~50%. Small so real data dominates
    /// after ~10 observations; nonzero so `count = 0` doesn't divide-by-0.
    public let priorStrength: Double
    private let sampler: any DeterministicSampler

    // MARK: - Init

    /// - Parameters:
    ///   - explorationEpsilon: Probability of a uniform-random pick from
    ///     `availableProviders` in the warm regime. `0.0` = pure exploit,
    ///     `1.0` = pure explore. Clamped to `[0, 1]`. Bandit doc target
    ///     is `≤ 0.1`.
    ///   - staticPrior: Argmax over this map on Day-1 MUST equal the
    ///     Stage 1 static routing decision — that's the guarantee that
    ///     ensures SC-006 zero regression.
    ///   - deterministicSampler: Injected seeded RNG. `AIRoutingBandit`
    ///     never touches `Math.random` or the system clock; every stochastic
    ///     branch flows through this sampler so tests can drive it.
    ///   - priorStrength: Virtual sample count for the prior; defaults
    ///     to `1.0`. Passing a larger value (e.g. `10`) makes the bandit
    ///     converge more slowly.
    public init(
        explorationEpsilon: Double,
        staticPrior: StaticPrior,
        deterministicSampler: any DeterministicSampler,
        priorStrength: Double = 1.0
    ) {
        self.explorationEpsilon = max(0, min(1, explorationEpsilon))
        self.staticPrior = staticPrior
        self.sampler = deterministicSampler
        self.priorStrength = max(1e-9, priorStrength)
    }

    // MARK: - Public API

    /// Picks the primary provider name from `availableProviders` for the
    /// current `(kind, deviceTier)`, given the observed `arms`.
    ///
    /// Contract:
    /// - `availableProviders` MUST reflect the caller's already-filtered
    ///   set — on `cloudOnly` tiers the caller MUST drop the on-device
    ///   arm before calling (FR-012/013 is enforced there, not here).
    /// - Returns the first element of `availableProviders` as a safe
    ///   default if the input is empty or malformed — the caller is
    ///   expected to have made sure the list is non-empty before
    ///   dispatching to the bandit, but this keeps the return type
    ///   non-optional so hot paths avoid unwrap noise.
    public func selectProvider(
        kind: AITaskKind,
        deviceTier: DeviceTier,
        arms: [BanditArmState],
        availableProviders: [String]
    ) -> String {
        guard let first = availableProviders.first else { return "" }
        if availableProviders.count == 1 { return first }

        let priorMap = staticPrior[kind]?[deviceTier] ?? [:]

        // Snapshot per-arm state for the requested (kind, tier). Single
        // pass so we don't rescan `arms` per provider.
        struct Scored {
            let name: String
            let count: Int
            let rewardSum: Double
            let priorMean: Double
        }
        let scored: [Scored] = availableProviders.map { name in
            let arm = arms.first {
                $0.kind == kind && $0.deviceTier == deviceTier && $0.provider == name
            }
            return Scored(
                name: name,
                count: arm?.count ?? 0,
                rewardSum: arm?.rewardSum ?? 0,
                priorMean: priorMap[name] ?? 0
            )
        }

        let totalCount = scored.reduce(0) { $0 + $1.count }

        // Day-1: pure prior, deterministic. No sampler call — SC-006
        // relies on this staying exactly deterministic when the bandit
        // has no observations.
        if totalCount == 0 {
            return Self.argmax(scored, name: { $0.name }, score: { $0.priorMean }) ?? first
        }

        // Warm regime: ε-greedy explore.
        let explore = sampler.nextDouble()
        if explore < explorationEpsilon {
            let r = sampler.nextDouble()
            // Clamp defensively so a sampler returning exactly 1.0
            // (protocol says `[0,1)` but be paranoid) does not read past
            // the end.
            let idx = min(availableProviders.count - 1, max(0, Int(r * Double(availableProviders.count))))
            return availableProviders[idx]
        }

        // Exploit: posterior argmax.
        let strength = priorStrength
        return Self.argmax(scored, name: { $0.name }, score: { s in
            (strength * s.priorMean + s.rewardSum) / (strength + Double(s.count))
        }) ?? first
    }

    /// Compresses the routing signal to a scalar reward in `[0, 1]`.
    ///
    /// Weights (sum to 1.0):
    /// - `schemaValid` → 0.4 (structural correctness — hard requirement
    ///   for structured JSON kinds; a "parse failed" response is worthless).
    /// - `accepted`    → 0.4 (implicit user acceptance — Stage 3c signal;
    ///   `nil` treated as 0, NOT as 0.5, since "no feedback yet" is safer
    ///   modeled as no positive reward than as noise centered on 0.5).
    /// - `offlineScore` → 0.2, clamped to `[0, 1]`; `nil` treated as 0.
    ///
    /// The function is a pure reducer over Bool + Bool? + Double? — no
    /// prompt/response text, no health values, no timestamps. Anything
    /// health-derived would put the bandit state on the wrong side of
    /// FR-018 / constitution I. This is enforced by type; the router
    /// never hands anything else in.
    public func computeReward(
        schemaValid: Bool,
        accepted: Bool?,
        offlineScore: Double?
    ) -> Double {
        let s = schemaValid ? 0.4 : 0.0
        let a = (accepted == true) ? 0.4 : 0.0
        let o = min(1.0, max(0.0, offlineScore ?? 0.0)) * 0.2
        return s + a + o
    }

    // MARK: - Prior construction helper

    /// Builds a `StaticPrior` from a set of provider metadata + the router
    /// policy such that `argmax priorMean` on any `(kind, tier)` equals
    /// the Stage 1 static routing decision. Callers pass this into the
    /// bandit init to guarantee Day-1 zero regression.
    ///
    /// Weight scheme:
    /// - Providers pruned by `AIRouter.orderedProviders` for `(kind, tier)`
    ///   get weight `0.0` — documentary, since they're also filtered out
    ///   of `availableProviders` before the bandit sees them.
    /// - Surviving providers get monotonically decreasing weights matching
    ///   the Stage 1 sort: on-device-first when eligible, then registration
    ///   order. That gives argmax = Stage 1's first pick.
    public static func staticPriorFromRouterDefaults(
        providers: [RegisteredProviderMeta],
        policy: [AITaskKind: TaskRequirements] = AIRouter.defaultPolicy
    ) -> StaticPrior {
        var prior: StaticPrior = [:]
        for kind in AITaskKind.allCases {
            let requirements = policy[kind] ?? AIRouter.safeDefaultRequirements
            var byTier: [DeviceTier: [String: Double]] = [:]
            for tier in DeviceTier.allCases {
                let tierFiltered: [RegisteredProviderMeta]
                switch tier {
                case .cloudOnly:
                    tierFiltered = providers.filter { !$0.isOnDevice }
                case .appleIntelligenceCapable:
                    tierFiltered = providers
                }
                let capable = tierFiltered.filter { $0.maxQuality >= requirements.quality }
                let indexed = capable.enumerated().map { (offset: $0.offset, provider: $0.element) }
                let sorted = indexed.sorted { lhs, rhs in
                    if lhs.provider.isOnDevice != rhs.provider.isOnDevice {
                        return lhs.provider.isOnDevice && !rhs.provider.isOnDevice
                    }
                    return lhs.offset < rhs.offset
                }
                var byProvider: [String: Double] = [:]
                // All pruned providers documented at 0.0.
                for meta in providers where !capable.contains(where: { $0.name == meta.name }) {
                    byProvider[meta.name] = 0.0
                }
                // Descending among survivors: 1.0, 0.75, 0.5, ..., floor at 0.1.
                for (rank, entry) in sorted.enumerated() {
                    let weight = max(0.1, 1.0 - Double(rank) * 0.25)
                    byProvider[entry.provider.name] = weight
                }
                byTier[tier] = byProvider
            }
            prior[kind] = byTier
        }
        return prior
    }

    // MARK: - Internals

    /// Deterministic argmax: highest score wins; tie-break by input order.
    private static func argmax<T>(_ items: [T], name: (T) -> String, score: (T) -> Double) -> String? {
        var best: (name: String, score: Double)?
        for item in items {
            let s = score(item)
            if let current = best {
                if s > current.score {
                    best = (name(item), s)
                }
            } else {
                best = (name(item), s)
            }
        }
        return best?.name
    }
}

// MARK: - Prior helper types

/// Minimal projection of `AIRouter.RegisteredProvider` used only for
/// building the static prior. Kept separate so callers can build a prior
/// without pinning `AIProvider` instances (e.g. from a config struct).
public struct RegisteredProviderMeta: Sendable {
    public let name: String
    public let isOnDevice: Bool
    public let maxQuality: QualityClass

    public init(name: String, isOnDevice: Bool, maxQuality: QualityClass) {
        self.name = name
        self.isOnDevice = isOnDevice
        self.maxQuality = maxQuality
    }
}
