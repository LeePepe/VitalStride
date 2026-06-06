import Foundation
import Testing
@testable import AIService

@Suite("SSE Parsing Tests")
struct SSEParsingTests {
    let provider = ZhipuProvider(apiKey: "test-key")

    @Test("parses normal data chunk")
    func normalChunk() {
        let line = "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}"
        let chunk = provider.parseSSELine(line)
        #expect(chunk?.content == "Hello")
        #expect(chunk?.isFinished == false)
    }

    @Test("parses [DONE] terminator")
    func doneTerminator() {
        let chunk = provider.parseSSELine("data: [DONE]")
        #expect(chunk?.isFinished == true)
        #expect(chunk?.content == "")
    }

    @Test("parses chunk with finish_reason stop")
    func finishReasonStop() {
        let line = "data: {\"choices\":[{\"delta\":{\"content\":\"\"},\"finish_reason\":\"stop\"}]}"
        let chunk = provider.parseSSELine(line)
        #expect(chunk?.isFinished == true)
    }

    @Test("ignores non-data lines")
    func nonDataLines() {
        #expect(provider.parseSSELine("event: message") == nil)
        #expect(provider.parseSSELine(": comment") == nil)
        #expect(provider.parseSSELine("") == nil)
        #expect(provider.parseSSELine("id: 123") == nil)
    }

    @Test("handles empty content in delta")
    func emptyDelta() {
        let line = "data: {\"choices\":[{\"delta\":{},\"finish_reason\":null}]}"
        let chunk = provider.parseSSELine(line)
        #expect(chunk?.content == "")
        #expect(chunk?.isFinished == false)
    }

    @Test("handles malformed JSON gracefully")
    func malformedJSON() {
        let chunk = provider.parseSSELine("data: {invalid json}")
        #expect(chunk == nil)
    }

    @Test("handles data: with extra spaces")
    func dataWithSpaces() {
        let line = "data:   {\"choices\":[{\"delta\":{\"content\":\"Hi\"},\"finish_reason\":null}]}"
        let chunk = provider.parseSSELine(line)
        #expect(chunk?.content == "Hi")
    }

    @Test("parses chunk with special characters in content")
    func specialCharacters() {
        let line = "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\\nWorld\"},\"finish_reason\":null}]}"
        let chunk = provider.parseSSELine(line)
        #expect(chunk?.content == "Hello\nWorld")
    }

    @Test("parses chunk with Chinese content")
    func chineseContent() {
        let line = "data: {\"choices\":[{\"delta\":{\"content\":\"你好世界\"},\"finish_reason\":null}]}"
        let chunk = provider.parseSSELine(line)
        #expect(chunk?.content == "你好世界")
        #expect(chunk?.isFinished == false)
    }

    @Test("parses chunk with mixed Chinese and emoji content")
    func mixedMultibyteContent() {
        let line = "data: {\"choices\":[{\"delta\":{\"content\":\"运动建议：跑步🏃‍♂️\"},\"finish_reason\":null}]}"
        let chunk = provider.parseSSELine(line)
        #expect(chunk?.content == "运动建议：跑步🏃‍♂️")
    }
}
