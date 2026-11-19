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
    public let allowsUnauthenticatedGateway: Bool

    public init(
        provider: PluggableAIProvider,
        baseURL: URL? = nil,
        modelID: String? = nil,
        keychainService: String? = nil,
        allowsUnauthenticatedGateway: Bool = false
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.modelID = modelID
        self.keychainService = keychainService
        self.allowsUnauthenticatedGateway = allowsUnauthenticatedGateway
    }

    private enum CodingKeys: String, CodingKey {
        case provider, baseURL, modelID, keychainService, allowsUnauthenticatedGateway
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            provider: try values.decode(PluggableAIProvider.self, forKey: .provider),
            baseURL: try values.decodeIfPresent(URL.self, forKey: .baseURL),
            modelID: try values.decodeIfPresent(String.self, forKey: .modelID),
            keychainService: try values.decodeIfPresent(String.self, forKey: .keychainService),
            allowsUnauthenticatedGateway: try values.decodeIfPresent(Bool.self, forKey: .allowsUnauthenticatedGateway) ?? false
        )
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
                allowsUnauthenticated: allowsUnauthenticatedGateway,
                keychainService: keychainService,
                keychain: keychain,
                session: session
            )
        case .deterministicFallback:
            return DeterministicFourLayerEngine()
        }
    }

    /// Explicit remote modes are primary; foundation mode keeps Apple before GLM.
    /// The final deterministic provider accepts physiological snapshots only.
    public func makeProviderChain(
        zhipuAPIKey: String? = nil,
        keychain: KeychainHelper = KeychainHelper(),
        session: URLSession = .shared
    ) -> AIProviderChain {
        var entries: [AIProviderChain.ProviderEntry] = []
        if provider == .foundationModels {
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
            entries.append(.init(name: provider.rawValue, isAvailable: {
                guard let baseURL, ["https", "http"].contains(baseURL.scheme?.lowercased() ?? ""),
                      baseURL.host != nil, let modelID,
                      !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
                if let keychainService {
                    do {
                        return !(try keychain.load(service: keychainService))
                            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    } catch {
                        return false
                    }
                }
                return provider == .jevGateway && allowsUnauthenticatedGateway
            }, provider: configured))
        }

        if provider != .deterministicFallback, let zhipuAPIKey {
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
        session: URLSession = .shared,
        deviceTier: @escaping @Sendable () -> DeviceTier = { DeviceTier.detect() }
    ) -> AIRouter {
        let chain = makeProviderChain(zhipuAPIKey: zhipuAPIKey, keychain: keychain, session: session)
        let providers = chain.providerEntries.map {
            AIRouter.RegisteredProvider(
                name: $0.name,
                isAvailable: $0.isAvailable,
                isOnDevice: $0.name == "apple_intelligence",
                maxQuality: $0.name == "apple_intelligence" ? .medium : .high,
                supportedTasks: $0.name == "deterministic_fallback" ? [.fourLayerAdvice] : Set(AITaskKind.allCases),
                provider: $0.provider
            )
        }
        return AIRouter(providers: providers, deviceTier: deviceTier)
    }

    private static let defaultOpenAIBaseURL = URL(string: "https://api.openai.com/v1") ?? URL(fileURLWithPath: "/")
    private static let defaultJevBaseURL = URL(string: "http://127.0.0.1:3425/v1") ?? URL(fileURLWithPath: "/")
}
