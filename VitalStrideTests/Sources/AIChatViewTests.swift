import Foundation
import Testing

@testable import VitalStride

@Suite("AIChatView Tests")
struct AIChatViewTests {

    // MARK: - AIChatMessage Model Tests

    @Test("appendingContent creates new message with appended content and preserves id")
    func appendingContent() {
        let original = AIChatMessage(role: .assistant, content: "Hello", state: .streaming)
        let updated = original.appendingContent(" world", state: .streaming)

        #expect(updated.id == original.id)
        #expect(updated.content == "Hello world")
        #expect(updated.state == .streaming)
        #expect(updated.role == .assistant)
    }

    @Test("appendingContent with finished state marks complete")
    func appendingContentFinished() {
        let original = AIChatMessage(role: .assistant, content: "Part", state: .streaming)
        let updated = original.appendingContent(" done", state: .complete)

        #expect(updated.content == "Part done")
        #expect(updated.state == .complete)
    }

    @Test("withState preserves content and identity")
    func withState() {
        let original = AIChatMessage(role: .assistant, content: "test", state: .streaming)
        let updated = original.withState(.complete)

        #expect(updated.id == original.id)
        #expect(updated.content == "test")
        #expect(updated.state == .complete)
        #expect(updated.timestamp == original.timestamp)
    }

    @Test("withState to error preserves content")
    func withStateError() {
        let original = AIChatMessage(role: .assistant, content: "partial", state: .streaming)
        let updated = original.withState(.error("Network failed"))

        #expect(updated.content == "partial")
        #expect(updated.state == .error("Network failed"))
    }

    @Test("AIChatMessage defaults to complete state")
    func defaultState() {
        let msg = AIChatMessage(role: .user, content: "hello")
        #expect(msg.state == .complete)
    }

    @Test("AIChatMessage generates unique IDs")
    func uniqueIds() {
        let msg1 = AIChatMessage(role: .user, content: "a")
        let msg2 = AIChatMessage(role: .user, content: "b")
        #expect(msg1.id != msg2.id)
    }

    @Test("AIChatMessage preserves custom ID")
    func customId() {
        let customId = UUID()
        let msg = AIChatMessage(id: customId, role: .assistant, content: "test")
        #expect(msg.id == customId)
    }

    // MARK: - AIChatRole Tests

    @Test("AIChatRole distinguishes user and assistant")
    func roles() {
        let userMsg = AIChatMessage(role: .user, content: "hi")
        let aiMsg = AIChatMessage(role: .assistant, content: "hello")
        #expect(userMsg.role == .user)
        #expect(aiMsg.role == .assistant)
    }

    // MARK: - AIChatMessageState Tests

    @Test("AIChatMessageState equality for same cases")
    func stateEqualitySame() {
        #expect(AIChatMessageState.complete == .complete)
        #expect(AIChatMessageState.streaming == .streaming)
        #expect(AIChatMessageState.error("a") == .error("a"))
    }

    @Test("AIChatMessageState inequality for different cases")
    func stateInequalityDifferent() {
        #expect(AIChatMessageState.complete != .streaming)
        #expect(AIChatMessageState.streaming != .error("x"))
        #expect(AIChatMessageState.error("a") != .error("b"))
    }

    // MARK: - ViewModel Tests

    @MainActor
    @Test("canSend is false when input is empty")
    func canSendEmpty() {
        let vm = AIChatViewModel()
        vm.inputText = ""
        #expect(!vm.canSend)
    }

    @MainActor
    @Test("canSend is false with whitespace-only input")
    func canSendWhitespace() {
        let vm = AIChatViewModel()
        vm.inputText = "   \n\t  "
        #expect(!vm.canSend)
    }

    @MainActor
    @Test("canSend is true with non-empty trimmed input")
    func canSendValid() {
        let vm = AIChatViewModel()
        vm.inputText = "Hello AI"
        #expect(vm.canSend)
    }

    @MainActor
    @Test("canSend is true with leading/trailing whitespace around content")
    func canSendWithWhitespace() {
        let vm = AIChatViewModel()
        vm.inputText = "  Hello  "
        #expect(vm.canSend)
    }

    @MainActor
    @Test("clearConversation resets all state")
    func clearConversation() {
        let vm = AIChatViewModel()
        vm.inputText = "some text"
        vm.clearConversation()

        #expect(vm.messages.isEmpty)
        #expect(!vm.isStreaming)
        #expect(vm.lastCompletedMessageId == nil)
    }

    @MainActor
    @Test("initial state is empty")
    func initialState() {
        let vm = AIChatViewModel()
        #expect(vm.messages.isEmpty)
        #expect(!vm.isStreaming)
        #expect(vm.inputText.isEmpty)
        #expect(!vm.canSend)
        #expect(vm.lastCompletedMessageId == nil)
    }
}
