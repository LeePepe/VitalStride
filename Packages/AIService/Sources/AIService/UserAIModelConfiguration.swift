import Foundation

public enum PluggableAIProvider: String, Codable, Sendable, Equatable, CaseIterable {
    case foundationModels
    case customOpenAICompatible
    case jevGateway
    case deterministicFallback
}

/// User-selectable provider settings. Secrets are represented by Keychain service names,
/// never by API-key values or UserDefaults fields.
public struct UserAIModelConfiguration: Codable, Sendable, Equatable {
    public let provider: PluggableAIProvider
    public let baseURL: URL?
    public let modelID: String?
    public let keychainService: String?

    public init(
        provider: PluggableAIProvider,
        baseURL: URL? = nil,
        modelID: String? = nil,
        keychainService: String? = nil
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.modelID = modelID
        self.keychainService = keychainService
    }

    public func makeProvider(
        keychain: KeychainHelper = KeychainHelper(),
        session: URLSession = .shared
    ) -> any AIProvider {
        switch provider {
        case .foundationModels:
            return AppleIntelligenceProvider()
        case .customOpenAICompatible:
            return OpenAICompatibleProvider(
                baseURL: baseURL ?? Self.defaultOpenAIBaseURL,
                model: modelID ?? "custom-model",
                keychainService: keychainService,
                keychain: keychain,
                session: session
            )
        case .jevGateway:
            return JevGatewayProvider(
                baseURL: baseURL ?? Self.defaultJevBaseURL,
                model: modelID ?? "jev-default",
                keychainService: keychainService,
                keychain: keychain,
                session: session
            )
        case .deterministicFallback:
            return DeterministicFourLayerEngine()
        }
    }

    /// Builds a chain that always ends in the local deterministic engine. Apple
    /// Intelligence remains ahead of network providers when it is registered.
    public func makeProviderChain(
        zhipuAPIKey: String? = nil,
        keychain: KeychainHelper = KeychainHelper(),
        session: URLSession = .shared
    ) -> AIProviderChain {
        var entries: [AIProviderChain.ProviderEntry] = []
        if provider != .deterministicFallback {
            entries.append(.init(
                name: "apple_intelligence",
                isAvailable: { AppleIntelligenceProvider.isAvailable },
                provider: AppleIntelligenceProvider()
            ))
        }

        switch provider {
        case .foundationModels, .deterministicFallback:
            break
        case .customOpenAICompatible, .jevGateway:
            let configured = makeProvider(keychain: keychain, session: session)
            entries.append(.init(name: provider.rawValue, isAvailable: { true }, provider: configured))
        }

        if let zhipuAPIKey {
            entries.append(.init(
                name: "zhipu",
                isAvailable: { !zhipuAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                provider: ZhipuProvider(apiKey: zhipuAPIKey, session: session)
            ))
        }

        entries.append(.init(
            name: "deterministic_fallback",
            isAvailable: { true },
            provider: DeterministicFourLayerEngine()
        ))
        return AIProviderChain(entries: entries)
    }

    public func makeRouter(
        zhipuAPIKey: String? = nil,
        keychain: KeychainHelper = KeychainHelper(),
        session: URLSession = .shared
    ) -> AIRouter {
        let chain = makeProviderChain(zhipuAPIKey: zhipuAPIKey, keychain: keychain, session: session)
        let providers = chain.providerEntries.map {
            AIRouter.RegisteredProvider(
                name: $0.name,
                isAvailable: $0.isAvailable,
                isOnDevice: $0.name == "apple_intelligence",
                maxQuality: .high,
                provider: $0.provider
            )
        }
        return AIRouter(providers: providers)
    }

    private static let defaultOpenAIBaseURL = URL(string: "https://api.openai.com/v1") ?? URL(fileURLWithPath: "/")
    private static let defaultJevBaseURL = URL(string: "http://127.0.0.1:3425/v1") ?? URL(fileURLWithPath: "/")
}
