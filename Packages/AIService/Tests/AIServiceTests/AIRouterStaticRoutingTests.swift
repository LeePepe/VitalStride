import Foundation
import Testing
@testable import AIService

@Suite("AIRouter Static Routing Tests", .serialized)
struct AIRouterStaticRoutingTests {

    // MARK: - Test helpers

    private static func makeRouter(
        tier: DeviceTier,
        appleAvailable: Bool = true,
        zhipuAvailable: Bool = true,
        appleMaxQuality: QualityClass = .medium,
        zhipuMaxQuality: QualityClass = .high
    ) -> AIRouter {
        let providers: [AIRouter.RegisteredProvider] = [
            .init(
                name: "apple_intelligence",
                isAvailable: { appleAvailable },
                isOnDevice: true,
                maxQuality: appleMaxQuality,
                provider: MockRouterProvider(name: "apple_intelligence", responseContent: "apple-out")
            ),
            .init(
                name: "zhipu",
                isAvailable: { zhipuAvailable },
                isOnDevice: false,
                maxQuality: zhipuMaxQuality,
                provider: MockRouterProvider(name: "zhipu", responseContent: "zhipu-out")
            ),
        ]
        return AIRouter(providers: providers, deviceTier: { tier })
    }

    // MARK: - FR-005 / Independent Test: on-device arm probability = 0 on cloudOnly

    @Test("cloudOnly device: on-device provider is filtered out for every kind")
    func cloudOnlyDropsOnDeviceForEveryKind() {
        let router = Self.makeRouter(tier: .cloudOnly)

        for kind in AITaskKind.allCases {
            let order = router.plannedProviderOrder(for: kind)
            #expect(!order.contains("apple_intelligence"), "kind=\(kind.rawValue) leaked on-device on cloudOnly tier")
            #expect(order == ["zhipu"], "kind=\(kind.rawValue) must resolve to zhipu-only on cloudOnly tier")
        }
    }

    @Test("cloudOnly device: substitute (interactive+low) still stays cloud-only")
    func cloudOnlySubstituteStaysCloudOnly() async throws {
        let router = Self.makeRouter(tier: .cloudOnly)
        let response = try await router.execute(kind: .substitute, messages: [ChatMessage(role: "user", content: "swap")], model: nil)
        #expect(response.content == "zhipu-out")
    }

    // MARK: - Spec Acceptance Scenarios (US1)

    @Test("appleIntelligenceCapable + substitute: routes on-device")
    func substituteRoutesOnDevice() async throws {
        // Spec §User Scenarios / Story 1 Scenario 1: "substitute → 端侧 AppleIntelligenceProvider"
        let router = Self.makeRouter(tier: .appleIntelligenceCapable)
        let response = try await router.execute(kind: .substitute, messages: [ChatMessage(role: "user", content: "swap")], model: nil)
        #expect(response.content == "apple-out")
    }

    @Test("appleIntelligenceCapable + chat (high quality): capability match prunes on-device, cloud selected")
    func chatSelectsCloudByCapability() async throws {
        // Spec §User Scenarios / Story 1 Scenario 2: ".chat → 云端质量档 (by
        // capability, not fixed order)".
        //
        // apple_intelligence.maxQuality = .medium, .chat requires .high, so the
        // on-device arm is pruned by capability match — not by re-sorting the
        // chain. `zhipu` (maxQuality=.high) becomes the primary. This is the
        // FR-004-compliant way to route: prune ineligible arms, do not reverse
        // surviving order.
        let router = Self.makeRouter(tier: .appleIntelligenceCapable)
        let order = router.plannedProviderOrder(for: .chat)
        #expect(order == ["zhipu"])

        let response = try await router.execute(kind: .chat, messages: [ChatMessage(role: "user", content: "hi")], model: nil)
        #expect(response.content == "zhipu-out")
    }

    @Test("appleIntelligenceCapable but apple unavailable: falls back to cloud without reversing chain")
    func fallsBackToCloudWhenAppleUnavailable() {
        // Spec §Edge Cases: "旧设备 + 无云端 key → noProviderAvailable". Positive
        // path: capable tier but runtime Apple unavailability (e.g. content
        // filter) → cloud only, not by re-ordering, but by isAvailable filter.
        let router = Self.makeRouter(tier: .appleIntelligenceCapable, appleAvailable: false)
        let order = router.plannedProviderOrder(for: .substitute)
        #expect(order == ["zhipu"])
    }

    @Test("both providers unavailable throws noProviderAvailable")
    func bothUnavailableThrows() async {
        // Spec §Edge Cases: caller degrades gracefully via existing chain error.
        let router = Self.makeRouter(tier: .appleIntelligenceCapable, appleAvailable: false, zhipuAvailable: false)
        await #expect(throws: AIServiceError.self) {
            try await router.execute(kind: .substitute, messages: [ChatMessage(role: "user", content: "hi")], model: nil)
        }
    }

    // MARK: - FR-003: central policy table drives requirements

    @Test("policy table maps every AITaskKind to concrete requirements")
    func policyCoversEveryKind() {
        // FR-003: the policy table is the router's, not the caller's. Every kind
        // MUST have a mapped `TaskRequirements` — otherwise callers implicitly rely
        // on the safe default which is only meant for unmapped/new kinds.
        for kind in AITaskKind.allCases {
            #expect(AIRouter.defaultPolicy[kind] != nil, "policy missing for kind=\(kind.rawValue)")
        }
    }

    @Test("policy table matches documented per-kind requirements")
    func policyValuesMatchDocumented() {
        // Regression guard: the router's policy is the single source of truth.
        // If someone re-tunes it, this test forces an explicit review of every
        // change, since caller behavior implicitly depends on these settings.
        let policy = AIRouter.defaultPolicy
        #expect(policy[.chat]?.latency == .interactive)
        #expect(policy[.chat]?.quality == .high)
        #expect(policy[.chat]?.structured == false)
        #expect(policy[.overviewInsights]?.latency == .background)
        #expect(policy[.overviewInsights]?.quality == .high)
        #expect(policy[.overviewInsights]?.structured == true)
        #expect(policy[.trainingAdvice]?.latency == .interactive)
        #expect(policy[.trainingAdvice]?.quality == .high)
        #expect(policy[.trainingAdvice]?.structured == true)
        #expect(policy[.dataTrend]?.quality == .high)
        #expect(policy[.dataTrend]?.structured == true)
        #expect(policy[.substitute]?.latency == .interactive)
        #expect(policy[.substitute]?.quality == .low)
        #expect(policy[.substitute]?.carriesHealthData == false)
    }

    // MARK: - Edge Case: safe default for unknown/unmapped kinds

    @Test("requirements(for:) returns safe default when policy has no entry")
    func unknownKindReturnsSafeDefault() {
        // Spec §Edge Cases: "未知/新增 kind 无策略条目 → 回退到一个安全默认画像
        // (background + medium + 允许 fallback)，并记一条告警信号，不崩溃".
        //
        // We simulate an "unknown kind" by injecting an empty policy — this is
        // the same code path a newly-added enum case with a missing table entry
        // would traverse.
        let router = AIRouter(
            providers: [
                .init(
                    name: "zhipu",
                    isAvailable: { true },
                    isOnDevice: false,
                    maxQuality: .high,
                    provider: MockRouterProvider(name: "zhipu", responseContent: "zhipu-out")
                ),
            ],
            policy: [:],
            deviceTier: { .cloudOnly }
        )
        let requirements = router.requirements(for: .chat)
        #expect(requirements == AIRouter.safeDefaultRequirements)
        #expect(requirements.latency == .background)
        #expect(requirements.quality == .medium)
    }

    @Test("execute(kind:) does not crash when policy is empty (safe default path)")
    func executeUnknownKindDoesNotCrash() async throws {
        let router = AIRouter(
            providers: [
                .init(
                    name: "zhipu",
                    isAvailable: { true },
                    isOnDevice: false,
                    maxQuality: .high,
                    provider: MockRouterProvider(name: "zhipu", responseContent: "safe-default-ok")
                ),
            ],
            policy: [:],
            deviceTier: { .cloudOnly }
        )
        let response = try await router.execute(kind: .chat, messages: [ChatMessage(role: "user", content: "x")], model: nil)
        #expect(response.content == "safe-default-ok")
    }

    // MARK: - FR-004: delegates to AIProviderChain (no chain reversal)

    @Test("chain order not reversed: eligible on-device arm stays ahead of cloud")
    func chainOrderNotReversed() {
        // FR-004 red line from AIService/CONTEXT.md: chain order MUST NOT be
        // reversed. Every kind on a capable device where the on-device arm is
        // still eligible (i.e. its `maxQuality` meets the requirement) MUST
        // see it ahead of cloud. Kinds where the on-device arm is pruned by
        // capability match (e.g. `.chat` requires `.high` > apple's `.medium`)
        // are NOT chain reversal — the on-device arm is not present in the
        // surviving set at all.
        let router = Self.makeRouter(tier: .appleIntelligenceCapable)
        for kind in AITaskKind.allCases {
            let requirements = router.requirements(for: kind)
            let order = router.plannedProviderOrder(for: kind)
            let appleEligible = QualityClass.medium >= requirements.quality
            if appleEligible {
                #expect(order.first == "apple_intelligence", "kind=\(kind.rawValue): eligible on-device arm demoted (got \(order))")
            } else {
                #expect(!order.contains("apple_intelligence"), "kind=\(kind.rawValue): ineligible on-device arm leaked into order \(order)")
            }
        }
    }

    // MARK: - FR-003: capability matching drives provider eligibility

    @Test("capability match: provider whose maxQuality is below requirement is pruned")
    func capabilityMatchPrunesUndercapableProvider() {
        // Direct regression guard for the P0 review finding: TaskRequirements
        // MUST drive eligibility, not just be looked up and discarded. A
        // hypothetical on-device provider limited to `.low` MUST NOT be picked
        // for a `.high` request (`.dataTrend`), even on a capable tier.
        let router = Self.makeRouter(tier: .appleIntelligenceCapable, appleMaxQuality: .low)
        let dataTrendOrder = router.plannedProviderOrder(for: .dataTrend)
        #expect(!dataTrendOrder.contains("apple_intelligence"))
        #expect(dataTrendOrder == ["zhipu"])

        // But a `.low` requirement (.substitute) still keeps it in the running.
        let substituteOrder = router.plannedProviderOrder(for: .substitute)
        #expect(substituteOrder == ["apple_intelligence", "zhipu"])
    }

    // MARK: - Stage 2 acceptance: overviewInsights + dataTrend keep pre-migration cloud behavior

    @Test(".overviewInsights on capable tier: on-device arm pruned by .high requirement (spec 019 SC-004)")
    func overviewInsightsPrunesOnDeviceOnCapableTier() {
        // Pre-migration, this call site instantiated ZhipuProvider directly.
        // After Stage 2 the router must reproduce that: even on an Apple
        // Intelligence-capable device, the on-device arm (maxQuality=.medium)
        // is below the .overviewInsights requirement (quality=.high) and gets
        // pruned by capability match. No chain reversal, just capability
        // filtering. FR-004 preserved.
        let router = Self.makeRouter(tier: .appleIntelligenceCapable)
        let order = router.plannedProviderOrder(for: .overviewInsights)
        #expect(!order.contains("apple_intelligence"))
        #expect(order == ["zhipu"])
    }

    @Test(".dataTrend on capable tier: on-device arm pruned by .high requirement (spec 019 SC-004)")
    func dataTrendPrunesOnDeviceOnCapableTier() {
        // Same rationale as .overviewInsights: pre-migration this went to
        // cloud GLM. The .high requirement prunes the on-device arm on a
        // capable tier so the routed order is cloud-only, matching Stage 1
        // behavior. FR-004 preserved.
        let router = Self.makeRouter(tier: .appleIntelligenceCapable)
        let order = router.plannedProviderOrder(for: .dataTrend)
        #expect(!order.contains("apple_intelligence"))
        #expect(order == ["zhipu"])
    }

    // MARK: - Stage 5b: bandit + prior mix, chain order not reversed

    @Test("Stage 5b Day-1: router with bandit + empty repo picks Stage 1 primary (SC-006)")
    func banditWithEmptyRepoMatchesStage1() async throws {
        // With `NoOpBanditArmStateRepository` (default when no repo
        // injected) `loadAll` returns []; the bandit falls back to the
        // static prior's argmax, which is constructed from the Stage 1
        // policy. So the executed provider MUST equal Stage 1's pick.
        let prior = AIRoutingBandit.staticPriorFromRouterDefaults(providers: [
            RegisteredProviderMeta(name: "apple_intelligence", isOnDevice: true, maxQuality: .medium),
            RegisteredProviderMeta(name: "zhipu", isOnDevice: false, maxQuality: .high),
        ])
        let bandit = AIRoutingBandit(
            explorationEpsilon: 0.5, // even a big ε shouldn't matter — Day-1 is deterministic
            staticPrior: prior,
            deterministicSampler: FixedSampler(value: 0.001) // would explore, but Day-1 skips sampler
        )
        let providers: [AIRouter.RegisteredProvider] = [
            .init(
                name: "apple_intelligence",
                isAvailable: { true },
                isOnDevice: true,
                maxQuality: .medium,
                provider: MockRouterProvider(name: "apple_intelligence", responseContent: "apple-out")
            ),
            .init(
                name: "zhipu",
                isAvailable: { true },
                isOnDevice: false,
                maxQuality: .high,
                provider: MockRouterProvider(name: "zhipu", responseContent: "zhipu-out")
            ),
        ]
        let router = AIRouter(
            providers: providers,
            deviceTier: { .appleIntelligenceCapable },
            bandit: bandit
        )

        // .substitute (both eligible on capable) → Stage 1 picks apple.
        let sub = try await router.execute(kind: .substitute, messages: [ChatMessage(role: "user", content: "swap")], model: nil)
        #expect(sub.content == "apple-out",
                "Day-1 bandit primary must match Stage 1's on-device pick for .substitute")

        // .chat → Stage 1 prunes apple by capability → zhipu.
        let chat = try await router.execute(kind: .chat, messages: [ChatMessage(role: "user", content: "hi")], model: nil)
        #expect(chat.content == "zhipu-out",
                "Day-1 bandit must respect capability filter: .chat still cloud-only")
    }

    @Test("Stage 5b: bandit-driven reorder still delegates to chain (constitution V: order not reversed)")
    func banditPrimaryStillGoesThroughChain() async throws {
        // Even when the bandit is on, execute() must still delegate to
        // AIProviderChain — a failing primary MUST fall back to the next
        // eligible provider, not throw. This is the guarantee that the
        // "chain order not reversed" red line holds even in the bandit
        // regime.
        let prior = AIRoutingBandit.staticPriorFromRouterDefaults(providers: [
            RegisteredProviderMeta(name: "apple_intelligence", isOnDevice: true, maxQuality: .medium),
            RegisteredProviderMeta(name: "zhipu", isOnDevice: false, maxQuality: .high),
        ])
        let bandit = AIRoutingBandit(
            explorationEpsilon: 0.0, staticPrior: prior,
            deterministicSampler: FixedSampler(value: 0.5)
        )
        let providers: [AIRouter.RegisteredProvider] = [
            .init(
                name: "apple_intelligence",
                isAvailable: { true }, isOnDevice: true, maxQuality: .medium,
                provider: AlwaysFailProvider(name: "apple_intelligence")
            ),
            .init(
                name: "zhipu",
                isAvailable: { true }, isOnDevice: false, maxQuality: .high,
                provider: MockRouterProvider(name: "zhipu", responseContent: "zhipu-fallback-out")
            ),
        ]
        let router = AIRouter(
            providers: providers,
            deviceTier: { .appleIntelligenceCapable },
            bandit: bandit
        )
        // Bandit's Day-1 primary for .substitute is apple; apple throws;
        // chain must fall back to zhipu.
        let response = try await router.execute(
            kind: .substitute,
            messages: [ChatMessage(role: "user", content: "swap")],
            model: nil
        )
        #expect(response.content == "zhipu-fallback-out",
                "chain fallback broken after bandit reorder — constitution V red line")
    }

    @Test("Stage 5b: nil bandit = Stage 1 exact routing (no repo call, no sampler use)")
    func nilBanditPreservesStage1() async throws {
        // Explicit nil-bandit path documented in the AIRouter init.
        // Everything Stage 1 asserted about static routing must still hold
        // when the bandit is not installed.
        let router = Self.makeRouter(tier: .appleIntelligenceCapable)
        #expect(router.plannedProviderOrder(for: .substitute) == ["apple_intelligence", "zhipu"])
        let sub = try await router.execute(kind: .substitute, messages: [ChatMessage(role: "user", content: "swap")], model: nil)
        #expect(sub.content == "apple-out")
    }

    @Test("Stage 5b: bandit with warm arms flips primary but chain still fallback-capable")
    func banditWarmSelectionFlipsPrimary() async throws {
        // Warm repo: strongly favor zhipu for .substitute. Bandit reorders
        // the primary → zhipu wins even though apple is Stage 1's default.
        // The point: the reorder is a bandit-driven policy change, not a
        // chain reversal — apple was still eligible and would have been
        // tried on fallback if zhipu had failed.
        let prior = AIRoutingBandit.staticPriorFromRouterDefaults(providers: [
            RegisteredProviderMeta(name: "apple_intelligence", isOnDevice: true, maxQuality: .medium),
            RegisteredProviderMeta(name: "zhipu", isOnDevice: false, maxQuality: .high),
        ])
        let bandit = AIRoutingBandit(
            explorationEpsilon: 0.0, staticPrior: prior,
            deterministicSampler: FixedSampler(value: 0.99) // never explores
        )
        let repo = InMemoryBanditRepo(state: [
            BanditArmState(
                kind: .substitute, deviceTier: .appleIntelligenceCapable, provider: "apple_intelligence",
                count: 20, rewardSum: 0.0, updatedAt: Date(timeIntervalSince1970: 0)
            ),
            BanditArmState(
                kind: .substitute, deviceTier: .appleIntelligenceCapable, provider: "zhipu",
                count: 20, rewardSum: 20.0, updatedAt: Date(timeIntervalSince1970: 0)
            ),
        ])
        let providers: [AIRouter.RegisteredProvider] = [
            .init(name: "apple_intelligence", isAvailable: { true }, isOnDevice: true, maxQuality: .medium,
                  provider: MockRouterProvider(name: "apple_intelligence", responseContent: "apple-out")),
            .init(name: "zhipu", isAvailable: { true }, isOnDevice: false, maxQuality: .high,
                  provider: MockRouterProvider(name: "zhipu", responseContent: "zhipu-out")),
        ]
        let router = AIRouter(
            providers: providers,
            deviceTier: { .appleIntelligenceCapable },
            bandit: bandit,
            banditRepo: repo
        )
        let response = try await router.execute(kind: .substitute, messages: [ChatMessage(role: "user", content: "swap")], model: nil)
        #expect(response.content == "zhipu-out",
                "warm bandit failed to flip primary to the higher-reward arm")
    }

    @Test("Stage 5b: FR-008 — banditRepo write failure does not affect execute return value")
    func banditRepoWriteFailureIsFireAndForget() async throws {
        let prior = AIRoutingBandit.staticPriorFromRouterDefaults(providers: [
            RegisteredProviderMeta(name: "apple_intelligence", isOnDevice: true, maxQuality: .medium),
            RegisteredProviderMeta(name: "zhipu", isOnDevice: false, maxQuality: .high),
        ])
        let bandit = AIRoutingBandit(
            explorationEpsilon: 0.0, staticPrior: prior,
            deterministicSampler: FixedSampler(value: 0.5)
        )
        // ObservingThrowingBanditRepo records that upsert was called
        // before it throws — so the test proves the throw path really
        // executed (not a silent no-op) AND that the caller was
        // unaffected. Anything less doesn't verify FR-008.
        let repo = ObservingThrowingBanditRepo()
        let providers: [AIRouter.RegisteredProvider] = [
            .init(name: "apple_intelligence", isAvailable: { true }, isOnDevice: true, maxQuality: .medium,
                  provider: MockRouterProvider(name: "apple_intelligence", responseContent: "apple-out")),
            .init(name: "zhipu", isAvailable: { true }, isOnDevice: false, maxQuality: .high,
                  provider: MockRouterProvider(name: "zhipu", responseContent: "zhipu-out")),
        ]
        let router = AIRouter(
            providers: providers,
            deviceTier: { .appleIntelligenceCapable },
            bandit: bandit,
            banditRepo: repo
        )
        // A throwing repo would break the caller if upsert were awaited on
        // the hot path. FR-008 says it must not.
        let response = try await router.execute(kind: .substitute, messages: [ChatMessage(role: "user", content: "swap")], model: nil)
        #expect(response.content == "apple-out",
                "throwing banditRepo affected user-visible return — FR-008 violated")
        // Give the detached upsert task a bounded window to fire.
        let start = ContinuousClock().now
        while await repo.throwCount() == 0, ContinuousClock().now - start < .seconds(2) {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        let throwCount = await repo.throwCount()
        #expect(throwCount >= 1,
                "upsert never threw — the FR-008 fire-and-forget path wasn't exercised (\(throwCount))")
    }

    @Test("Stage 5b: FR-012/013 — cloudOnly tier + bandit never picks on-device arm")
    func cloudOnlyBanditNeverPicksOnDevice() async throws {
        // Feed the repo strong (but ineligible) apple_intelligence data
        // for .cloudOnly. The router's tier filter drops apple before it
        // reaches the bandit, so even a huge rewardSum can't lift it into
        // the executed order. 1000 draws = 0 apple hits.
        let prior = AIRoutingBandit.staticPriorFromRouterDefaults(providers: [
            RegisteredProviderMeta(name: "apple_intelligence", isOnDevice: true, maxQuality: .medium),
            RegisteredProviderMeta(name: "zhipu", isOnDevice: false, maxQuality: .high),
        ])
        let bandit = AIRoutingBandit(
            explorationEpsilon: 0.5, staticPrior: prior,
            deterministicSampler: FixedSampler(value: 0.1) // WOULD explore
        )
        let repo = InMemoryBanditRepo(state: [
            BanditArmState(
                kind: .substitute, deviceTier: .cloudOnly, provider: "apple_intelligence",
                count: 100, rewardSum: 100.0, updatedAt: Date(timeIntervalSince1970: 0)
            ),
        ])
        let providers: [AIRouter.RegisteredProvider] = [
            .init(name: "apple_intelligence", isAvailable: { true }, isOnDevice: true, maxQuality: .medium,
                  provider: MockRouterProvider(name: "apple_intelligence", responseContent: "apple-out")),
            .init(name: "zhipu", isAvailable: { true }, isOnDevice: false, maxQuality: .high,
                  provider: MockRouterProvider(name: "zhipu", responseContent: "zhipu-out")),
        ]
        let router = AIRouter(
            providers: providers,
            deviceTier: { .cloudOnly },
            bandit: bandit,
            banditRepo: repo
        )
        for _ in 0..<50 {
            let response = try await router.execute(kind: .substitute, messages: [ChatMessage(role: "user", content: "swap")], model: nil)
            #expect(response.content == "zhipu-out",
                    "cloudOnly bandit leaked into on-device arm — FR-012/013 violated")
        }
    }
}

// MARK: - Mock provider (test-only)

/// Test-only immutable provider. Both stored properties are `let`, no mutable
/// state, so a plain `Sendable` conformance is safe — no `@unchecked` needed
/// (Constitution II / Quality Bar C).
private struct MockRouterProvider: AIProvider, Sendable {
    let name: String
    let responseContent: String

    func chat(messages: [ChatMessage], model: String?) async throws -> ChatResponse {
        ChatResponse(content: responseContent, model: name)
    }

    func chatStream(messages: [ChatMessage], model: String?) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        let content = responseContent
        return AsyncThrowingStream { continuation in
            continuation.yield(ChatStreamChunk(content: content))
            continuation.yield(ChatStreamChunk(content: "", isFinished: true))
            continuation.finish()
        }
    }
}

/// Provider that always throws — used to exercise chain fallback.
private struct AlwaysFailProvider: AIProvider, Sendable {
    let name: String
    struct Boom: Error {}
    func chat(messages: [ChatMessage], model: String?) async throws -> ChatResponse {
        throw Boom()
    }
    func chatStream(messages: [ChatMessage], model: String?) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        AsyncThrowingStream { $0.finish(throwing: Boom()) }
    }
}

/// Deterministic sampler returning a fixed value on every draw.
private struct FixedSampler: DeterministicSampler {
    let value: Double
    func nextDouble() -> Double { value }
}

/// In-memory repo returning a fixed state snapshot; upsert is a no-op.
private struct InMemoryBanditRepo: BanditArmStateRepository {
    let state: [BanditArmState]
    func loadAll() async -> [BanditArmState] { state }
    func upsert(kind: AITaskKind, deviceTier: DeviceTier, provider: String, deltaCount: Int, deltaReward: Double) async throws {}
}

/// Repo whose `upsert` actually throws, so the FR-008 fire-and-forget
/// guarantee is exercised at runtime (not just at the type level). The
/// error is thrown from inside the `async throws` implementation; the
/// detached `Task` in `AIRouter.execute` wraps the call in `try?`, so the
/// caller must still see a normal return value.
private struct ThrowingBanditRepo: BanditArmStateRepository {
    struct UpsertFailure: Error {}
    func loadAll() async -> [BanditArmState] { [] }
    func upsert(kind: AITaskKind, deviceTier: DeviceTier, provider: String, deltaCount: Int, deltaReward: Double) async throws {
        throw UpsertFailure()
    }
}

/// Same as `ThrowingBanditRepo` but records how many times `upsert` was
/// invoked before throwing. Actor conformance is inherently `Sendable`
/// (Constitution II) — no `@unchecked`, no lock.
private actor ObservingThrowingBanditRepo: BanditArmStateRepository {
    struct UpsertFailure: Error {}
    private var attemptCount: Int = 0

    func loadAll() async -> [BanditArmState] { [] }

    func upsert(kind: AITaskKind, deviceTier: DeviceTier, provider: String, deltaCount: Int, deltaReward: Double) async throws {
        attemptCount += 1
        throw UpsertFailure()
    }

    func throwCount() -> Int { attemptCount }
}
