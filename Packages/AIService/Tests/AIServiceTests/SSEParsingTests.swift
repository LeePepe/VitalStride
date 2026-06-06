import Foundation
import Testing
@testable import AIService

@Suite("SSE Parsing Tests")
struct SSEParsingTests {
    let provider = ZhipuProvider(apiKey: "test-key")

    @Test("parses normal data chunk")
    func normalChunk() throws {
        let line = "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}"
        let chunk = try provider.parseSSELine(line)
        #expect(chunk?.content == "Hello")
        #expect(chunk?.isFinished == false)
    }

    @Test("parses [DONE] terminator")
    func doneTerminator() throws {
        let chunk = try provider.parseSSELine("data: [DONE]")
        #expect(chunk?.isFinished == true)
        #expect(chunk?.content == "")
    }

    @Test("parses chunk with finish_reason stop")
    func finishReasonStop() throws {
        let line = "data: {\"choices\":[{\"delta\":{\"content\":\"\"},\"finish_reason\":\"stop\"}]}"
        let chunk = try provider.parseSSELine(line)
        #expect(chunk?.isFinished == true)
    }

    @Test("ignores non-data lines")
    func nonDataLines() throws {
        #expect(try provider.parseSSELine("event: message") == nil)
        #expect(try provider.parseSSELine(": comment") == nil)
        #expect(try provider.parseSSELine("") == nil)
        #expect(try provider.parseSSELine("id: 123") == nil)
    }

    @Test("handles empty content in delta")
    func emptyDelta() throws {
        let line = "data: {\"choices\":[{\"delta\":{},\"finish_reason\":null}]}"
        let chunk = try provider.parseSSELine(line)
        #expect(chunk?.content == "")
        #expect(chunk?.isFinished == false)
    }

    @Test("throws on malformed JSON data payload")
    func malformedJSON() {
        #expect(throws: AIServiceError.self) {
            try provider.parseSSELine("data: {invalid json}")
        }
    }

    @Test("returns nil for empty data payload")
    func emptyDataPayload() throws {
        let chunk = try provider.parseSSELine("data: ")
        #expect(chunk == nil)
    }

    @Test("handles data: with extra spaces")
    func dataWithSpaces() throws {
        let line = "data:   {\"choices\":[{\"delta\":{\"content\":\"Hi\"},\"finish_reason\":null}]}"
        let chunk = try provider.parseSSELine(line)
        #expect(chunk?.content == "Hi")
    }

    @Test("parses chunk with special characters in content")
    func specialCharacters() throws {
        let line = "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\\nWorld\"},\"finish_reason\":null}]}"
        let chunk = try provider.parseSSELine(line)
        #expect(chunk?.content == "Hello\nWorld")
    }

    @Test("parses chunk with Chinese content")
    func chineseContent() throws {
        let line = "data: {\"choices\":[{\"delta\":{\"content\":\"你好世界\"},\"finish_reason\":null}]}"
        let chunk = try provider.parseSSELine(line)
        #expect(chunk?.content == "你好世界")
        #expect(chunk?.isFinished == false)
    }

    @Test("parses chunk with mixed Chinese and emoji content")
    func mixedMultibyteContent() throws {
        let line = "data: {\"choices\":[{\"delta\":{\"content\":\"运动建议：跑步🏃‍♂️\"},\"finish_reason\":null}]}"
        let chunk = try provider.parseSSELine(line)
        #expect(chunk?.content == "运动建议：跑步🏃‍♂️")
    }
}
