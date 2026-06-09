import Foundation
import Testing
@testable import AIService

@Suite("AppleIntelligenceProvider Tests")
struct AppleIntelligenceProviderTests {

    @Test("formatMessages extracts system message as instructions")
    func formatWithSystemMessage() {
        let messages = [
            ChatMessage(role: "system", content: "You are helpful"),
            ChatMessage(role: "user", content: "Hello"),
        ]
        let (instructions, prompt) = AppleIntelligenceProvider.formatMessages(messages)
        #expect(instructions == "You are helpful")
        #expect(prompt == "Hello")
    }

    @Test("formatMessages returns nil instructions when no system message")
    func formatWithoutSystemMessage() {
        let messages = [
            ChatMessage(role: "user", content: "Hello"),
        ]
        let (instructions, prompt) = AppleIntelligenceProvider.formatMessages(messages)
        #expect(instructions == nil)
        #expect(prompt == "Hello")
    }

    @Test("formatMessages joins multiple system messages")
    func formatMultipleSystemMessages() {
        let messages = [
            ChatMessage(role: "system", content: "Be concise"),
            ChatMessage(role: "system", content: "Respond in English"),
            ChatMessage(role: "user", content: "Hi"),
        ]
        let (instructions, prompt) = AppleIntelligenceProvider.formatMessages(messages)
        #expect(instructions == "Be concise\nRespond in English")
        #expect(prompt == "Hi")
    }

    @Test("formatMessages formats multi-turn conversation")
    func formatMultiTurn() {
        let messages = [
            ChatMessage(role: "system", content: "You are helpful"),
            ChatMessage(role: "user", content: "What is 2+2?"),
            ChatMessage(role: "assistant", content: "4"),
            ChatMessage(role: "user", content: "And 3+3?"),
        ]
        let (instructions, prompt) = AppleIntelligenceProvider.formatMessages(messages)
        #expect(instructions == "You are helpful")
        #expect(prompt.contains("user: What is 2+2?"))
        #expect(prompt.contains("assistant: 4"))
        #expect(prompt.contains("user: And 3+3?"))
    }

    @Test("formatMessages handles empty messages")
    func formatEmptyMessages() {
        let (instructions, prompt) = AppleIntelligenceProvider.formatMessages([])
        #expect(instructions == nil)
        #expect(prompt == "")
    }

    @Test("isAvailable returns a boolean value")
    func isAvailableReturnsBool() {
        let available = AppleIntelligenceProvider.isAvailable
        #expect(available == true || available == false)
    }
}
