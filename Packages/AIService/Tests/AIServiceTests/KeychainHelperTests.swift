import Foundation
import Testing
@testable import AIService

@Suite("KeychainHelper Tests")
struct KeychainHelperTests {
    let helper = KeychainHelper()
    let testService = "com.vitalstride.aiservice.test.\(UUID().uuidString)"

    @Test("save and load round-trip")
    func saveAndLoad() throws {
        try helper.save(key: "test-api-key-123", service: testService)
        let loaded = try helper.load(service: testService)
        #expect(loaded == "test-api-key-123")
        try helper.delete(service: testService)
    }

    @Test("save overwrites existing value")
    func saveOverwrites() throws {
        try helper.save(key: "old-key", service: testService)
        try helper.save(key: "new-key", service: testService)
        let loaded = try helper.load(service: testService)
        #expect(loaded == "new-key")
        try helper.delete(service: testService)
    }

    @Test("load throws itemNotFound for missing key")
    func loadMissing() throws {
        let missingService = "com.vitalstride.test.nonexistent.\(UUID().uuidString)"
        #expect(throws: KeychainError.self) {
            try helper.load(service: missingService)
        }
    }

    @Test("delete removes the key")
    func deleteRemoves() throws {
        try helper.save(key: "to-delete", service: testService)
        try helper.delete(service: testService)
        #expect(throws: KeychainError.self) {
            try helper.load(service: testService)
        }
    }

    @Test("delete nonexistent key does not throw")
    func deleteNonexistent() throws {
        let missingService = "com.vitalstride.test.delete-missing.\(UUID().uuidString)"
        try helper.delete(service: missingService)
    }

    @Test("saves and loads special characters in key")
    func specialCharacters() throws {
        let specialKey = "sk-abc123!@#$%^&*()_+-=[]{}|;':\",./<>?"
        try helper.save(key: specialKey, service: testService)
        let loaded = try helper.load(service: testService)
        #expect(loaded == specialKey)
        try helper.delete(service: testService)
    }

    @Test("saves and loads empty string")
    func emptyString() throws {
        try helper.save(key: "", service: testService)
        let loaded = try helper.load(service: testService)
        #expect(loaded == "")
        try helper.delete(service: testService)
    }
}
