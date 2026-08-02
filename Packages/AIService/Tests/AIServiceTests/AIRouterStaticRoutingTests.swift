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
