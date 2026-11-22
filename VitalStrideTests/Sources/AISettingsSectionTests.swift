import AIService
import Foundation
import Testing

@testable import VitalStride

@Suite("AI Settings Section Tests")
struct AISettingsSectionTests {
    @Test("AIModel has correct raw values for AppStorage")
    func aiModelRawValues() {
        #expect(AIModel.glm4Flash.rawValue == "glm-4-flash")
        #expect(AIModel.glm4Plus.rawValue == "glm-4-plus")
    }

    @Test("AIModel conforms to CaseIterable with two cases")
    func aiModelCaseIterable() {
        #expect(AIModel.allCases.count == 2)
        #expect(AIModel.allCases.contains(.glm4Flash))
        #expect(AIModel.allCases.contains(.glm4Plus))
    }

    @Test("AIModel display names include tier labels")
    func aiModelDisplayNames() {
        #expect(AIModel.glm4Flash.displayName.contains("GLM-4-Flash"))
        #expect(AIModel.glm4Plus.displayName.contains("GLM-4-Plus"))
    }

    @Test("AIModel default is glm-4-flash")
    func aiModelDefault() {
        let defaultModel: AIModel = .glm4Flash
        #expect(defaultModel.rawValue == "glm-4-flash")
    }

    @MainActor
    @Test("API key keychain service uses standard prefix")
    func apiKeyKeychainService() {
        let service = AISettingsSection.apiKeyKeychainService
        #expect(service.hasPrefix("com.vitalstride.aiservice"))
        #expect(service.hasSuffix(".apikey"))
    }

    @MainActor
    @Test("AIModelSettingsStore caches secret presence and completes 20 rapid provider switches in < 5ms")
    func settingsStoreSub5msProviderSwitching() throws {
        let suiteName = "ai-settings-hotpath-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        AIModelSettingsStore.setCachedSecret("synthetic-test-key", for: AISettingsSection.apiKeyKeychainService)
        AIModelSettingsStore.setCachedSecret("synthetic-jev-key", for: AIModelSettingsStore.jevKeychainService)
        defer { AIModelSettingsStore.resetSecretCache() }

        let store = AIModelSettingsStore(defaults: defaults)
        // Warm up once
        store.select(.customOpenAICompatible)
        _ = store.status

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for idx in 0..<20 {
                let provider = PluggableAIProvider.allCases[idx % PluggableAIProvider.allCases.count]
                store.select(provider)
                _ = store.status
                _ = store.chainSummary
                _ = store.isSelectedProviderReady
            }
        }
        let elapsedMs = Double(elapsed.components.seconds) * 1_000.0
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000.0
        #expect(elapsedMs < 5.0, "Expected 20 rapid AIModelSettingsStore switches in < 5ms, got \(elapsedMs)ms")
    }
}
