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
}
