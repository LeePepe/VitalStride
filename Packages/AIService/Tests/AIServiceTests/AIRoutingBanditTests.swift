import Foundation
import Synchronization
import Testing
@testable import AIService

// MARK: - Test helpers

/// Deterministic sampler backed by a fixed sequence. Consumes one Double
/// per `nextDouble()` call. Loops if the caller drains it — makes long
/// simulations succinct.
///
/// Concurrency: state is protected by Swift 6 `Mutex` from the
/// `Synchronization` module. No `@unchecked Sendable` — the compiler
/// enforces Sendable safety (Constitution II / Quality Bar C).
private final class ScriptedSampler: DeterministicSampler {
    private let values: [Double]
    private let idx: Mutex<Int>

    init(_ values: [Double]) {
        self.values = values
        self.idx = Mutex(0)
    }

    func nextDouble() -> Double {
        guard !values.isEmpty else { return 0.0 }
        return idx.withLock { current in
            let v = values[current % values.count]
            current += 1
            return v
        }
    }
}

/// A tiny LCG so tests can drive the ε-greedy branch deterministically
/// across thousands of samples without hand-listing every value.
///
/// Concurrency: state is protected by Swift 6 `Mutex` from the
/// `Synchronization` module. No `@unchecked Sendable` — the compiler
/// enforces Sendable safety (Constitution II / Quality Bar C).
private final class LCGSampler: DeterministicSampler {
    private let state: Mutex<UInt64>

    init(seed: UInt64 = 0xDEADBEEF) {
        self.state = Mutex(seed)
    }

    func nextDouble() -> Double {
        state.withLock { s in
            // Numerical Recipes LCG parameters — cheap, deterministic, good enough.
            s = s &* 6364136223846793005 &+ 1442695040888963407
            // Take top 53 bits → [0, 1).
            let top = s >> 11
            return Double(top) / Double(1 << 53)
        }
    }
}

/// Deterministic prior matching the Stage 1 static routing on the two-arm
/// default provider set — used across every SC-006 assertion.
private func makeStage1Prior() -> AIRoutingBandit.StaticPrior {
    let metas = [
        RegisteredProviderMeta(name: "apple_intelligence", isOnDevice: true, maxQuality: .medium),
        RegisteredProviderMeta(name: "zhipu", isOnDevice: false, maxQuality: .high),
    ]
    return AIRoutingBandit.staticPriorFromRouterDefaults(providers: metas)
}

// MARK: - Tests

@Suite("AIRoutingBandit Tests", .serialized)
struct AIRoutingBanditTests {

    // MARK: - SC-006: Day-1 zero regression

    @Test("SC-006 Day-1: empty arms + full prior → distribution matches Stage 1 (KL ≈ 0)")
    func day1MatchesStage1Distribution() {
        // With no arm observations, the bandit MUST be deterministic and
        // pick the prior's argmax — the sampler is not consulted. This
        // makes the KL divergence to Stage 1 exactly zero, not just small.
        let prior = makeStage1Prior()
        // Sampler is scripted with obvious "would break exploration" values;
        // if the Day-1 branch ever consults it, one of these lands in the
        // ε-greedy path and the test breaks.
        let neverSampler = ScriptedSampler([0.999, 0.001])
        let bandit = AIRoutingBandit(
            explorationEpsilon: 0.5,
            staticPrior: prior,
            deterministicSampler: neverSampler
        )

        // For each (kind, tier) the Stage 1 ordering was defined by
        // AIRouter.orderedProviders — build the same table here so this
        // test is an independent restatement of what Stage 1 SHOULD pick,
        // not a rephrasing of the bandit's own math.
        let expected: [(AITaskKind, DeviceTier, [String], String)] = [
            (.substitute, .appleIntelligenceCapable, ["apple_intelligence", "zhipu"], "apple_intelligence"),
            (.chat, .appleIntelligenceCapable, ["zhipu"], "zhipu"),
            (.overviewInsights, .appleIntelligenceCapable, ["zhipu"], "zhipu"),
            (.trainingAdvice, .appleIntelligenceCapable, ["zhipu"], "zhipu"),
            (.dataTrend, .appleIntelligenceCapable, ["zhipu"], "zhipu"),

            (.substitute, .cloudOnly, ["zhipu"], "zhipu"),
            (.chat, .cloudOnly, ["zhipu"], "zhipu"),
            (.overviewInsights, .cloudOnly, ["zhipu"], "zhipu"),
            (.trainingAdvice, .cloudOnly, ["zhipu"], "zhipu"),
            (.dataTrend, .cloudOnly, ["zhipu"], "zhipu"),
        ]

        // 1000 draws per row — the branch is deterministic on empty arms so
        // 100 % of draws must equal the Stage 1 winner, i.e. KL = 0.
        for (kind, tier, available, want) in expected {
            var hits = 0
            for _ in 0..<1000 {
                let pick = bandit.selectProvider(
                    kind: kind,
                    deviceTier: tier,
                    arms: [],
                    availableProviders: available
                )
                if pick == want { hits += 1 }
            }
            #expect(hits == 1000,
                    "kind=\(kind.rawValue) tier=\(tier.rawValue): expected 1000/1000 = \(want), got \(hits)")
        }
    }

    // MARK: - Monotonic high-reward lift

    @Test("high-reward arm's selection frequency does not decrease across windows")
    func highRewardLiftIsMonotonic() {
        // Seed the bandit with a strong (kind, tier, provider="zhipu") arm.
        // As it accumulates more reward the posterior gap over
        // apple_intelligence widens; observed selection frequency in the
        // exploit branch should stay pinned to zhipu, and ε-greedy noise
        // should not push the window-averaged frequency down.
        let prior = makeStage1Prior()
        let sampler = LCGSampler(seed: 0xC0FFEE)
        let bandit = AIRoutingBandit(
            explorationEpsilon: 0.1,
            staticPrior: prior,
            deterministicSampler: sampler
        )
        let available = ["apple_intelligence", "zhipu"]
        // Simulate a scenario where the on-device arm has 0 reward and
        // the cloud arm accumulates strong reward as we go.
        let kind = AITaskKind.substitute
        let tier = DeviceTier.appleIntelligenceCapable

        // Build 5 escalating snapshots. Each represents "arm state at
        // window boundary k"; the count/rewardSum grows monotonically for
        // zhipu, stays at zero for apple.
        let snapshots: [[BanditArmState]] = (1...5).map { k in
            [
                BanditArmState(
                    kind: kind, deviceTier: tier, provider: "apple_intelligence",
                    count: 5 * k, rewardSum: 0.0,
                    updatedAt: Date(timeIntervalSince1970: 0)
                ),
                BanditArmState(
                    kind: kind, deviceTier: tier, provider: "zhipu",
                    count: 5 * k, rewardSum: 0.9 * Double(5 * k),
                    updatedAt: Date(timeIntervalSince1970: 0)
                ),
            ]
        }

        // Sample 1000 draws per window and record zhipu's frequency.
        var freqs: [Double] = []
        for arms in snapshots {
            var zhipuHits = 0
            for _ in 0..<1000 {
                let pick = bandit.selectProvider(
                    kind: kind, deviceTier: tier,
                    arms: arms, availableProviders: available
                )
                if pick == "zhipu" { zhipuHits += 1 }
            }
            freqs.append(Double(zhipuHits) / 1000.0)
        }

        // Non-decreasing across windows, and >= 1 - ε at the end (only
        // the explore branch can pick apple in these snapshots).
        for i in 1..<freqs.count {
            #expect(freqs[i] >= freqs[i - 1] - 0.05,
                    "window \(i): zhipu frequency dropped from \(freqs[i-1]) to \(freqs[i])")
        }
        let finalFreq = freqs.last ?? 0
        #expect(finalFreq >= 0.85,
                "final zhipu frequency \(finalFreq) < 0.85 — exploit branch not selecting the strong arm")
    }

    // MARK: - FR-012/013: cloudOnly device drops on-device arm

    @Test("FR-012/013: cloudOnly caller-filtered availableProviders → on-device never picked")
    func cloudOnlyDropsOnDevice() {
        let prior = makeStage1Prior()
        let sampler = LCGSampler(seed: 0xABCDEF)
        let bandit = AIRoutingBandit(
            explorationEpsilon: 0.1,
            staticPrior: prior,
            deterministicSampler: sampler
        )
        // The caller (AIRouter) is responsible for excluding on-device
        // providers on `.cloudOnly`. This test asserts the bandit honors
        // that contract — given a cloud-only availableProviders, it never
        // picks the on-device arm regardless of arm state noise.
        //
        // Seed the arms with "the on-device arm has been observed" so the
        // bandit isn't just skipping it because arms are empty.
        let arms: [BanditArmState] = [
            BanditArmState(
                kind: .substitute, deviceTier: .cloudOnly, provider: "apple_intelligence",
                count: 100, rewardSum: 100.0,
                updatedAt: Date(timeIntervalSince1970: 0)
            ),
            BanditArmState(
                kind: .substitute, deviceTier: .cloudOnly, provider: "zhipu",
                count: 100, rewardSum: 10.0,
                updatedAt: Date(timeIntervalSince1970: 0)
            ),
        ]
        var appleHits = 0
        for _ in 0..<1000 {
            let pick = bandit.selectProvider(
                kind: .substitute, deviceTier: .cloudOnly,
                arms: arms, availableProviders: ["zhipu"]
            )
            if pick == "apple_intelligence" { appleHits += 1 }
        }
        #expect(appleHits == 0,
                "on-device arm leaked into cloudOnly selection: \(appleHits)/1000")
    }

    // MARK: - Reward calculation invariants

    @Test("reward: all-positive inputs = 1.0; all-null inputs = 0.0")
    func rewardBounds() {
        let bandit = AIRoutingBandit(
            explorationEpsilon: 0.0,
            staticPrior: [:],
            deterministicSampler: ScriptedSampler([0])
        )
        #expect(bandit.computeReward(schemaValid: true, accepted: true, offlineScore: 1.0) == 1.0)
        #expect(bandit.computeReward(schemaValid: false, accepted: false, offlineScore: nil) == 0.0)
        #expect(bandit.computeReward(schemaValid: false, accepted: nil, offlineScore: nil) == 0.0)
    }

    @Test("reward: schemaValid alone = 0.4; accepted alone = 0.4")
    func rewardWeights() {
        let bandit = AIRoutingBandit(
            explorationEpsilon: 0.0,
            staticPrior: [:],
            deterministicSampler: ScriptedSampler([0])
        )
        #expect(bandit.computeReward(schemaValid: true, accepted: false, offlineScore: nil) == 0.4)
        #expect(bandit.computeReward(schemaValid: false, accepted: true, offlineScore: nil) == 0.4)
    }

    @Test("reward: offlineScore weighted 0.2 and clamped to [0,1]")
    func rewardOfflineClamp() {
        let bandit = AIRoutingBandit(
            explorationEpsilon: 0.0,
            staticPrior: [:],
            deterministicSampler: ScriptedSampler([0])
        )
        let base = bandit.computeReward(schemaValid: false, accepted: false, offlineScore: 0.5)
        #expect(abs(base - 0.1) < 1e-9, "offlineScore=0.5 → 0.1, got \(base)")

        let over = bandit.computeReward(schemaValid: false, accepted: false, offlineScore: 5.0)
        #expect(abs(over - 0.2) < 1e-9, "offlineScore>1 must clamp; got \(over)")

        let under = bandit.computeReward(schemaValid: false, accepted: false, offlineScore: -1.0)
        #expect(abs(under - 0.0) < 1e-9, "offlineScore<0 must clamp; got \(under)")
    }

    // MARK: - Edge behavior

    @Test("selectProvider: single-item availableProviders always returns that item")
    func singleProviderShortCircuit() {
        let bandit = AIRoutingBandit(
            explorationEpsilon: 1.0,
            staticPrior: [:],
            deterministicSampler: ScriptedSampler([0.99])
        )
        let pick = bandit.selectProvider(
            kind: .chat, deviceTier: .cloudOnly,
            arms: [], availableProviders: ["zhipu"]
        )
        #expect(pick == "zhipu")
    }

    @Test("selectProvider: empty availableProviders returns empty string (safe default)")
    func emptyProviderReturnsSafeDefault() {
        let bandit = AIRoutingBandit(
            explorationEpsilon: 0.0,
            staticPrior: [:],
            deterministicSampler: ScriptedSampler([0])
        )
        let pick = bandit.selectProvider(
            kind: .chat, deviceTier: .cloudOnly,
            arms: [], availableProviders: []
        )
        #expect(pick.isEmpty)
    }

    @Test("selectProvider: ε=0 pure exploit uses argmax posterior")
    func pureExploitPicksHighestPosterior() {
        // No explore possible → the highest posterior wins regardless of
        // sampler input.
        let sampler = ScriptedSampler([0.99, 0.99])
        let bandit = AIRoutingBandit(
            explorationEpsilon: 0.0,
            staticPrior: [:],
            deterministicSampler: sampler
        )
        let arms: [BanditArmState] = [
            BanditArmState(
                kind: .chat, deviceTier: .appleIntelligenceCapable, provider: "a",
                count: 100, rewardSum: 90.0,
                updatedAt: Date(timeIntervalSince1970: 0)
            ),
            BanditArmState(
                kind: .chat, deviceTier: .appleIntelligenceCapable, provider: "b",
                count: 100, rewardSum: 10.0,
                updatedAt: Date(timeIntervalSince1970: 0)
            ),
        ]
        let pick = bandit.selectProvider(
            kind: .chat, deviceTier: .appleIntelligenceCapable,
            arms: arms, availableProviders: ["a", "b"]
        )
        #expect(pick == "a")
    }

    @Test("selectProvider: warm regime with ε=1 always samples uniformly from availableProviders")
    func pureExploreDrawsFromAvailable() {
        // sampler.nextDouble() returns 0.0 first (explore branch), then 0.6
        // (index = int(0.6 * 2) = 1 → second provider).
        let sampler = ScriptedSampler([0.0, 0.6])
        let bandit = AIRoutingBandit(
            explorationEpsilon: 1.0,
            staticPrior: [:],
            deterministicSampler: sampler
        )
        // Non-empty arm state to enter the warm branch.
        let arms: [BanditArmState] = [
            BanditArmState(
                kind: .chat, deviceTier: .appleIntelligenceCapable, provider: "a",
                count: 5, rewardSum: 5.0,
                updatedAt: Date(timeIntervalSince1970: 0)
            ),
        ]
        let pick = bandit.selectProvider(
            kind: .chat, deviceTier: .appleIntelligenceCapable,
            arms: arms, availableProviders: ["a", "b"]
        )
        #expect(pick == "b")
    }

    // MARK: - Static prior helper

    @Test("staticPriorFromRouterDefaults: argmax matches Stage 1 for every (kind, tier)")
    func priorArgmaxMatchesStage1() {
        let metas = [
            RegisteredProviderMeta(name: "apple_intelligence", isOnDevice: true, maxQuality: .medium),
            RegisteredProviderMeta(name: "zhipu", isOnDevice: false, maxQuality: .high),
        ]
        let prior = AIRoutingBandit.staticPriorFromRouterDefaults(providers: metas)

        // Stage 1 truth table restated inline so this test breaks if
        // AIRouter.defaultPolicy changes without the prior being updated.
        let expected: [(AITaskKind, DeviceTier, String)] = [
            (.substitute, .appleIntelligenceCapable, "apple_intelligence"),
            (.chat, .appleIntelligenceCapable, "zhipu"),
            (.overviewInsights, .appleIntelligenceCapable, "zhipu"),
            (.trainingAdvice, .appleIntelligenceCapable, "zhipu"),
            (.dataTrend, .appleIntelligenceCapable, "zhipu"),
            (.substitute, .cloudOnly, "zhipu"),
            (.chat, .cloudOnly, "zhipu"),
        ]
        for (kind, tier, want) in expected {
            let byProvider = prior[kind]?[tier] ?? [:]
            let winner = byProvider.max(by: { $0.value < $1.value })?.key
            #expect(winner == want,
                    "prior argmax mismatch for (\(kind.rawValue), \(tier.rawValue)): got \(winner ?? "nil"), want \(want)")
        }
    }

    // MARK: - Red-line assertions (constitution I)

    @Test("red-line: computeReward's public signature has no health-value input")
    func computeRewardSignatureIsPriI() {
        // Structural check: computeReward must only take Bool + Bool? + Double?.
        // Anything else (e.g. taking a full ChatResponse or a health metric
        // array) would let raw HealthKit values flow into bandit state.
        //
        // Nothing to assert at runtime — this is a compile-time contract.
        // The check exists so a reader searching for "how do we know
        // bandit state is health-free" lands on this test. Also serves as
        // a smoke test that the API compiles the way spec 019 documents.
        let bandit = AIRoutingBandit(
            explorationEpsilon: 0.0, staticPrior: [:],
            deterministicSampler: ScriptedSampler([0])
        )
        _ = bandit.computeReward(schemaValid: true, accepted: nil, offlineScore: nil)
    }
}
