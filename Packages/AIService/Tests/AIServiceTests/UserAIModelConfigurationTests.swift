import Foundation
import Testing
@testable import AIService

@Suite("User model configuration and routing repair")
struct UserAIModelConfigurationTests {
    @Test(arguments: PluggableAIProvider.allCases)
    func allModes(_ mode: PluggableAIProvider) async throws {
        let fixture = try IsolatedHTTPFixture { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-keychain-value")
            let object = try requestJSONObject(request)
            #expect(object["model"] as? String == "synthetic-config-model")
            let stream = object["stream"] as? Bool == true
            let body = stream ? "data: {\"choices\":[{\"delta\":{\"content\":\"configured\"},\"finish_reason\":\"stop\"}]}\n\n" : #"{"choices":[{"message":{"content":"configured"}}]}"#
            return (try testHTTPResponse(request, status: 200, headers: nil), Data(body.utf8))
        }
        defer { fixture.close() }
        let keychain = KeychainHelper(load: { service in
            #expect(service == "synthetic-service")
            return "synthetic-keychain-value"
        })
        let config = UserAIModelConfiguration(provider: mode, baseURL: fixture.baseURL, modelID: "synthetic-config-model", keychainService: "synthetic-service")
        #expect(try JSONDecoder().decode(UserAIModelConfiguration.self, from: JSONEncoder().encode(config)) == config)
        let chain = config.makeProviderChain(keychain: keychain, session: fixture.session)
        let router = config.makeRouter(keychain: keychain, session: fixture.session, deviceTier: { .appleIntelligenceCapable })
        switch mode {
        case .foundationModels:
            #expect(config.makeProvider() is AppleIntelligenceProvider)
            #expect(chain.providerEntries.map(\.name) == ["apple_intelligence", "deterministic_fallback"])
            #expect(chain.providerEntries.first?.isAvailable() == AppleIntelligenceProvider.isAvailable)
            #expect(router.plannedProviderOrder(for: .chat).isEmpty)
            #expect(router.plannedProviderOrder(for: .fourLayerAdvice) == ["deterministic_fallback"])
            #expect(router.plannedProviderOrder(for: .substitute) == (AppleIntelligenceProvider.isAvailable ? ["apple_intelligence"] : []))
            let snapshot = try testSnapshot()
            let messages = [ChatMessage(role: "user", content: String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self))]
            let local = DeterministicFourLayerEngine().makeReport(from: snapshot)
            let routed = try await router.execute(kind: .fourLayerAdvice, messages: messages, model: nil)
            #expect(try JSONDecoder().decode(HolisticFourLayerReport.self, from: Data(routed.content.utf8)) == local)
            if !AppleIntelligenceProvider.isAvailable {
                let chained = try await chain.chat(messages: messages, model: nil)
                #expect(try JSONDecoder().decode(HolisticFourLayerReport.self, from: Data(chained.content.utf8)) == local)
                await #expect(throws: (any Error).self) {
                    try await config.makeProvider().chat(messages: [], model: nil)
                }
            }
        case .customOpenAICompatible, .jevGateway:
            #expect(chain.providerEntries.map(\.name) == [mode.rawValue, "deterministic_fallback"])
            #expect(chain.providerEntries[0].isAvailable())
            for kind in AITaskKind.allCases {
                #expect(router.plannedProviderOrder(for: kind).first == mode.rawValue)
            }
            #expect(try await config.makeProvider(keychain: keychain, session: fixture.session).chat(messages: [], model: nil).content == "configured")
            #expect(try await chain.chat(messages: [], model: nil).content == "configured")
            #expect(try await router.execute(kind: .chat, messages: [], model: nil).content == "configured")
            var streamed = ""
            for try await chunk in router.executeStream(kind: .chat, messages: [], model: nil) { streamed += chunk.content }
            #expect(streamed == "configured")
        case .deterministicFallback:
            #expect(config.makeProvider() is DeterministicFourLayerEngine)
            #expect(chain.providerEntries.map(\.name) == ["deterministic_fallback"])
            let snapshot = try testSnapshot()
            let messages = [ChatMessage(role: "user", content: String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self))]
            let expected = DeterministicFourLayerEngine().makeReport(from: snapshot)
            let direct = try await config.makeProvider().chat(messages: messages, model: nil)
            let chained = try await chain.chat(messages: messages, model: nil)
            let routed = try await router.execute(kind: .fourLayerAdvice, messages: messages, model: nil)
            for response in [direct, chained, routed] {
                #expect(try JSONDecoder().decode(HolisticFourLayerReport.self, from: Data(response.content.utf8)) == expected)
            }
            for kind in AITaskKind.allCases where kind != .fourLayerAdvice {
                #expect(router.plannedProviderOrder(for: kind).isEmpty)
                await #expect(throws: AIServiceError.self) { try await router.execute(kind: kind, messages: messages, model: nil) }
            }
        }
    }

    @Test("Legacy defaults retain only Apple and optional GLM with original quality gates")
    func legacyDefaults() async throws {
        let noKey = AIProviderChain.makeDefault(zhipuAPIKey: nil)
        #expect(noKey.providerEntries.map(\.name) == ["apple_intelligence"])
        #expect(AIProviderChain.makeDefault(zhipuAPIKey: "synthetic").providerEntries.map(\.name) == ["apple_intelligence", "zhipu"])
        #expect(AIProviderChain.makeDefault(zhipuAPIKey: " ").providerEntries.last?.isAvailable() == false)
        let router = AIRouter.makeDefault(zhipuAPIKey: nil)
        for kind in [AITaskKind.chat, .overviewInsights, .trainingAdvice, .dataTrend, .fourLayerAdvice] {
            #expect(router.plannedProviderOrder(for: kind).isEmpty)
            await #expect(throws: AIServiceError.self) {
                try await router.execute(kind: kind, messages: [ChatMessage(role: "user", content: "uninterpretable")], model: nil)
            }
        }
        let foundation = UserAIModelConfiguration(provider: .foundationModels)
        #expect(foundation.makeProviderChain(zhipuAPIKey: "synthetic").providerEntries.map(\.name) == ["apple_intelligence", "zhipu", "deterministic_fallback"])
        let capable = foundation.makeRouter(zhipuAPIKey: "synthetic", deviceTier: { .appleIntelligenceCapable })
        #expect(capable.plannedProviderOrder(for: .chat) == ["zhipu"])
        let cloudOnly = foundation.makeRouter(zhipuAPIKey: "synthetic", deviceTier: { .cloudOnly })
        #expect(cloudOnly.plannedProviderOrder(for: .substitute) == ["zhipu"])
        #expect(cloudOnly.plannedProviderOrder(for: .fourLayerAdvice) == ["zhipu", "deterministic_fallback"])
        #expect(UserAIModelConfiguration(provider: .deterministicFallback).makeProviderChain(zhipuAPIKey: "synthetic").providerEntries.count == 1)
    }

    @Test("Unconfigured, absent, empty and inaccessible keys are unavailable, never anonymously downgraded")
    func availability() async throws {
        let fixture = try IsolatedHTTPFixture { _ in
            Issue.record("Unavailable configuration must not send requests")
            throw URLError(.badServerResponse)
        }
        defer { fixture.close() }
        for mode in [PluggableAIProvider.customOpenAICompatible, .jevGateway] {
            for keychain in [
                KeychainHelper(load: { _ in throw KeychainError.itemNotFound }),
                KeychainHelper(load: { _ in throw KeychainError.loadFailed(status: -25308) }),
                KeychainHelper(load: { _ in throw KeychainError.unexpectedData }),
                KeychainHelper(load: { _ in "  " }),
            ] {
                let config = UserAIModelConfiguration(provider: mode, baseURL: fixture.baseURL, modelID: "synthetic", keychainService: "synthetic-service", allowsUnauthenticatedGateway: true)
                #expect(config.makeProviderChain(keychain: keychain).providerEntries.first?.isAvailable() == false)
                let router = config.makeRouter(keychain: keychain, session: fixture.session)
                #expect(router.plannedProviderOrder(for: .chat).isEmpty)
                await #expect(throws: AIServiceError.self) { try await router.execute(kind: .chat, messages: [], model: nil) }
            }
            for config in [
                UserAIModelConfiguration(provider: mode),
                UserAIModelConfiguration(provider: mode, baseURL: fixture.baseURL, modelID: "synthetic"),
                UserAIModelConfiguration(provider: mode, baseURL: fixture.baseURL, modelID: " ", keychainService: "synthetic"),
            ] {
                #expect(config.makeProviderChain().providerEntries.first?.isAvailable() == false)
            }
        }
        let anonymous = UserAIModelConfiguration(provider: .jevGateway, baseURL: fixture.baseURL, modelID: "synthetic", allowsUnauthenticatedGateway: true)
        #expect(anonymous.makeProviderChain().providerEntries.first?.isAvailable() == true)
        #expect(anonymous.makeRouter(deviceTier: { .appleIntelligenceCapable }).plannedProviderOrder(for: .chat) == ["jevGateway"])
        let legacy = try JSONDecoder().decode(UserAIModelConfiguration.self, from: Data(#"{"provider":"jevGateway"}"#.utf8))
        #expect(!legacy.allowsUnauthenticatedGateway)
    }

    @Test("Chain never starts fallback after provider cancellation")
    func cancelledChain() async {
        for cancelled in [false, true] {
            let chain = AIProviderChain(entries: [
                .init(name: "cancelled", isAvailable: { true }, provider: ReplyProvider { _ in
                    if cancelled { throw URLError(.cancelled) }
                    throw CancellationError()
                }),
                .init(name: "must-not-run", isAvailable: { true }, provider: ReplyProvider { _ in
                    Issue.record("Cancellation must not trigger fallback")
                    return "wrong"
                }),
            ])
            await #expect(throws: CancellationError.self) { try await chain.chat(messages: [], model: nil) }
        }
    }
}
