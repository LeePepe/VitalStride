import AIService
import DesignKit
import Observation
import SwiftUI
import TelemetryKit

private let aiSettingsPrivacyConsentKey = "ai_privacy_consent_accepted"

enum AIModel: String, CaseIterable, Sendable {
    case glm4Flash = "glm-4-flash"
    case glm4Plus = "glm-4-plus"
    var displayName: String { self == .glm4Flash ? "GLM-4-Flash (Free)" : "GLM-4-Plus (Paid)" }
}

@MainActor
@Observable
final class AIModelSettingsStore {
    static let defaultsKey = "userAIModelConfiguration"
    static let jevKeychainService = "com.vitalstride.aiservice.jev.apikey"
    private(set) var configuration: UserAIModelConfiguration
    private let defaults: UserDefaults
    private let keychain: KeychainHelper

    init(defaults: UserDefaults = .standard, keychain: KeychainHelper = KeychainHelper()) {
        self.defaults = defaults; self.keychain = keychain
        configuration = defaults.data(forKey: Self.defaultsKey).flatMap { try? JSONDecoder().decode(UserAIModelConfiguration.self, from: $0) } ?? Self.defaultConfiguration()
    }

    static func defaultConfiguration() -> UserAIModelConfiguration { AppleIntelligenceProvider.isAvailable ? .init(provider: .foundationModels) : .init(provider: .deterministicFallback) }

    func select(_ provider: PluggableAIProvider) {
        switch provider {
        case .foundationModels: save(.init(provider: provider))
        case .customOpenAICompatible: save(.init(provider: provider, baseURL: configuration.baseURL ?? URL(string: "https://open.bigmodel.cn/api/paas/v4"), modelID: configuration.modelID ?? AIModel.glm4Flash.rawValue, keychainService: AISettingsSection.apiKeyKeychainService))
        case .jevGateway: save(.init(provider: provider, baseURL: configuration.baseURL ?? URL(string: "http://127.0.0.1:3425/v1"), modelID: configuration.modelID ?? "jev-default", keychainService: configuration.allowsUnauthenticatedGateway ? nil : Self.jevKeychainService, allowsUnauthenticatedGateway: configuration.allowsUnauthenticatedGateway))
        case .deterministicFallback: save(.init(provider: provider))
        }
    }

    func update(baseURL: String? = nil, modelID: String? = nil, allowsUnauthenticatedGateway: Bool? = nil) {
        let anonymous = allowsUnauthenticatedGateway ?? configuration.allowsUnauthenticatedGateway
        let service = configuration.provider == .customOpenAICompatible ? AISettingsSection.apiKeyKeychainService : configuration.provider == .jevGateway ? (anonymous ? nil : Self.jevKeychainService) : configuration.keychainService
        save(.init(provider: configuration.provider, baseURL: baseURL.flatMap(URL.init(string:)) ?? configuration.baseURL, modelID: modelID ?? configuration.modelID, keychainService: service, allowsUnauthenticatedGateway: anonymous))
    }

    func saveSecret(_ secret: String) {
        let value = secret.trimmingCharacters(in: .whitespacesAndNewlines); guard !value.isEmpty else { return }
        let service = configuration.provider == .jevGateway ? Self.jevKeychainService : AISettingsSection.apiKeyKeychainService
        guard (try? keychain.save(key: value, service: service)) != nil else { return }
        if configuration.provider == .jevGateway { save(.init(provider: .jevGateway, baseURL: configuration.baseURL, modelID: configuration.modelID, keychainService: service, allowsUnauthenticatedGateway: false)) }
    }

    func clearSecret() { let service = configuration.provider == .jevGateway ? Self.jevKeychainService : AISettingsSection.apiKeyKeychainService; try? keychain.delete(service: service) }
    func hasSecret() -> Bool { guard let service = configuration.keychainService, let value = try? keychain.load(service: service) else { return false }; return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var status: (String, PillTone) {
        switch configuration.provider {
        case .foundationModels: return AppleIntelligenceProvider.isAvailable ? ("Ready", .success) : ("Fallback active", .warning)
        case .deterministicFallback: return ("Offline ready", .success)
        case .customOpenAICompatible: return validRemote ? (hasSecret() ? ("Ready", .success) : ("Needs key", .warning)) : ("Invalid URL", .warning)
        case .jevGateway: return validRemote ? (configuration.allowsUnauthenticatedGateway || hasSecret() ? ("Ready", .success) : ("Needs key", .warning)) : ("Invalid URL", .warning)
        }
    }
    var chainSummary: String { switch configuration.provider { case .foundationModels: "On-device Apple Intelligence → optional GLM → offline rules"; case .customOpenAICompatible: "Custom API → offline rules"; case .jevGateway: "Jev Gateway → offline rules"; case .deterministicFallback: "Deterministic physiology rules · zero network" } }
    private var validRemote: Bool { guard let url = configuration.baseURL, let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil else { return false }; return !(configuration.modelID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private func save(_ value: UserAIModelConfiguration) { configuration = value; guard let data = try? JSONEncoder().encode(value) else { return }; defaults.set(data, forKey: Self.defaultsKey); if let id = TelemetryIdentifier(validating: value.provider.rawValue) { TelemetryService.shared.trackNonisolated(.aiModelChanged(model: id)) } }
}

struct AISettingsSection: View {
    nonisolated static let apiKeyKeychainService = "\(KeychainHelper.defaultServicePrefix).apikey"
    @State private var store = AIModelSettingsStore()
    @AppStorage(aiSettingsPrivacyConsentKey) private var privacyConsented = false
    @State private var showRevoke = false
    var body: some View {
        Section {
            NavigationLink { AIModelConfigurationView(store: store) } label: { Label(String(localized: "ai_config_title", defaultValue: "AI model configuration", comment: "AI settings entry"), systemImage: "cpu.fill") }
            NavigationLink { StepsBodyRecoveryView() } label: { Label(String(localized: "steps_body_entry", defaultValue: "Steps / NEAT × Body Recovery", comment: "Steps body settings entry"), systemImage: "figure.walk.motion") }
            if privacyConsented { Button(String(localized: "ai_config_revoke", defaultValue: "Revoke AI data consent", comment: "Revoke consent"), role: .destructive) { showRevoke = true } }
        } header: { Text(String(localized: "ai_config_section", defaultValue: "AI services", comment: "AI settings section")) }
        .alert(String(localized: "ai_config_revoke_title", defaultValue: "Revoke AI data consent?", comment: "Revoke consent title"), isPresented: $showRevoke) { Button(String(localized: "ai_config_cancel", defaultValue: "Cancel", comment: "Cancel"), role: .cancel) {}; Button(String(localized: "ai_config_revoke", defaultValue: "Revoke", comment: "Revoke consent"), role: .destructive) { privacyConsented = false } }
    }
}

struct AIModelConfigurationView: View {
    @Environment(\.theme) private var theme
    @State private var store: AIModelSettingsStore
    @AppStorage(aiSettingsPrivacyConsentKey) private var privacyConsented = false
    @State private var baseURL = ""
    @State private var modelID = ""
    @State private var secret = ""
    @State private var showClear = false
    init(store: AIModelSettingsStore? = nil) { _store = State(initialValue: store ?? AIModelSettingsStore()) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                Card { HStack { SectionHeader(String(localized: "ai_config_header", defaultValue: "Pluggable AI engine", comment: "AI configuration header"), icon: "cpu.fill"); Spacer(); StatusPill(store.status.0, tone: store.status.1) }; Text(store.chainSummary).font(TypeScale.body).foregroundStyle(theme.secondaryForeground).fixedSize(horizontal: false, vertical: true) }
                Card { SectionHeader(String(localized: "ai_config_provider_header", defaultValue: "Provider", comment: "Provider header"), icon: "point.3.connected.trianglepath.dotted"); ForEach(PluggableAIProvider.allCases, id: \.self) { provider in Button { store.select(provider); syncFields() } label: { HStack { Text(providerTitle(provider)).font(TypeScale.body); Spacer(); if store.configuration.provider == provider { Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accent) } }.frame(maxWidth: .infinity, minHeight: Space.minTapTarget, alignment: .leading).contentShape(Rectangle()) }.buttonStyle(.plain) } }
                if store.configuration.provider == .customOpenAICompatible || store.configuration.provider == .jevGateway { remoteConfiguration }
                Card { HStack { Label(String(localized: "ai_config_credential", defaultValue: "Credential", comment: "Credential label"), systemImage: "key.fill"); Spacer(); Text(store.hasSecret() ? "••••••••" : String(localized: "ai_config_missing", defaultValue: "Not configured", comment: "Missing credential")).font(TypeScale.meta).foregroundStyle(theme.secondaryForeground) }; if !store.hasSecret() { SecureField(String(localized: "ai_config_secret_placeholder", defaultValue: "Enter credential", comment: "Credential placeholder"), text: $secret).onSubmit { store.saveSecret(secret); secret = "" } } else { Button(String(localized: "ai_config_clear", defaultValue: "Clear credential", comment: "Clear credential"), role: .destructive) { showClear = true }.frame(minHeight: Space.minTapTarget, alignment: .leading) } }
                Card { Toggle(String(localized: "ai_config_consent", defaultValue: "Allow AI analysis of health summaries", comment: "AI consent"), isOn: $privacyConsented); Text(privacyConsented ? String(localized: "ai_config_consent_granted", defaultValue: "Consent granted", comment: "Consent status") : String(localized: "ai_config_consent_pending", defaultValue: "Consent not granted", comment: "Consent status")).font(TypeScale.meta).foregroundStyle(theme.secondaryForeground) }
            }.padding(Space.md).frame(maxWidth: Space.contentMaxWidth, alignment: .leading)
        }.background(theme.canvas).navigationTitle(String(localized: "ai_config_title", defaultValue: "AI model configuration", comment: "AI configuration title")).onAppear(perform: syncFields).alert(String(localized: "ai_config_clear_title", defaultValue: "Clear saved credential?", comment: "Clear credential title"), isPresented: $showClear) { Button(String(localized: "ai_config_cancel", defaultValue: "Cancel", comment: "Cancel"), role: .cancel) {}; Button(String(localized: "ai_config_clear", defaultValue: "Clear", comment: "Clear credential"), role: .destructive) { store.clearSecret() } }
    }
    private var remoteConfiguration: some View { Card { SectionHeader(String(localized: "ai_config_remote_header", defaultValue: "Endpoint", comment: "Endpoint header"), icon: "network"); TextField(String(localized: "ai_config_endpoint", defaultValue: "Base URL", comment: "Endpoint field"), text: $baseURL).onSubmit { store.update(baseURL: baseURL) }; TextField(String(localized: "ai_config_model", defaultValue: "Model ID", comment: "Model field"), text: $modelID).onSubmit { store.update(modelID: modelID) }; HStack { ForEach(AIModel.allCases, id: \.self) { model in Button(model.displayName) { modelID = model.rawValue; store.update(modelID: model.rawValue) }.buttonStyle(.bordered) } }; if store.configuration.provider == .jevGateway { Toggle(String(localized: "ai_config_jev_anonymous", defaultValue: "Allow unauthenticated local gateway", comment: "Gateway auth toggle"), isOn: Binding(get: { store.configuration.allowsUnauthenticatedGateway }, set: { store.update(allowsUnauthenticatedGateway: $0) })) } } }
    private func syncFields() { baseURL = store.configuration.baseURL?.absoluteString ?? ""; modelID = store.configuration.modelID ?? "" }
    private func providerTitle(_ provider: PluggableAIProvider) -> String { switch provider { case .foundationModels: String(localized: "ai_config_foundation", defaultValue: "On-device Apple Intelligence", comment: "Provider"); case .customOpenAICompatible: String(localized: "ai_config_custom", defaultValue: "Custom OpenAI-compatible API", comment: "Provider"); case .jevGateway: String(localized: "ai_config_jev", defaultValue: "Jev Gateway", comment: "Provider"); case .deterministicFallback: String(localized: "ai_config_offline", defaultValue: "Deterministic offline rules", comment: "Provider") } }
}

#Preview("AI settings · Light") { NavigationStack { AIModelConfigurationView() }.designThemePreview() }
#Preview("AI settings · Dark") { NavigationStack { AIModelConfigurationView() }.designThemePreview().preferredColorScheme(.dark) }
