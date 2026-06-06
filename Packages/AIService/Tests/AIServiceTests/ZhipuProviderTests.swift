import Foundation
import Testing
@testable import AIService

@Suite("ZhipuProvider Tests", .serialized)
struct ZhipuProviderTests {
    let testAPIKey = "test-api-key-12345"

    @Test("chat sends correct request format")
    func chatRequestFormat() async throws {
        var capturedRequest: URLRequest?

        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let responseBody: [String: Any] = [
                "choices": [["message": ["content": "Hello!"]]],
                "model": "glm-4-flash",
                "usage": ["prompt_tokens": 10, "completion_tokens": 5],
            ]
            let data = try JSONSerialization.data(withJSONObject: responseBody)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let provider = ZhipuProvider(apiKey: testAPIKey, session: makeMockSession())
        let messages = [ChatMessage(role: "user", content: "Hi")]
        _ = try await provider.chat(messages: messages, model: nil)

        let request = try #require(capturedRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://open.bigmodel.cn/api/paas/v4/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(testAPIKey)")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["model"] as? String == "glm-4-flash")
        #expect(json?["stream"] as? Bool == false)
        let msgs = json?["messages"] as? [[String: String]]
        #expect(msgs?.first?["role"] == "user")
        #expect(msgs?.first?["content"] == "Hi")
    }

    @Test("chat uses custom model when provided")
    func chatCustomModel() async throws {
        MockURLProtocol.requestHandler = { request in
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
            #expect(body?["model"] as? String == "glm-4")

            let responseBody: [String: Any] = [
                "choices": [["message": ["content": "response"]]],
                "model": "glm-4",
            ]
            let data = try JSONSerialization.data(withJSONObject: responseBody)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let provider = ZhipuProvider(apiKey: testAPIKey, session: makeMockSession())
        let result = try await provider.chat(messages: [ChatMessage(role: "user", content: "test")], model: "glm-4")
        #expect(result.model == "glm-4")
    }

    @Test("chat parses successful response")
    func chatParseResponse() async throws {
        MockURLProtocol.requestHandler = { request in
            let responseBody: [String: Any] = [
                "choices": [["message": ["content": "The answer is 42."]]],
                "model": "glm-4-flash",
                "usage": ["prompt_tokens": 15, "completion_tokens": 8],
            ]
            let data = try JSONSerialization.data(withJSONObject: responseBody)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let provider = ZhipuProvider(apiKey: testAPIKey, session: makeMockSession())
        let result = try await provider.chat(messages: [ChatMessage(role: "user", content: "test")], model: nil)

        #expect(result.content == "The answer is 42.")
        #expect(result.model == "glm-4-flash")
        #expect(result.usage?.promptTokens == 15)
        #expect(result.usage?.completionTokens == 8)
    }

    @Test("chat throws httpError on 401")
    func chatHTTPError401() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let provider = ZhipuProvider(apiKey: "bad-key", session: makeMockSession())
        await #expect(throws: AIServiceError.self) {
            try await provider.chat(messages: [ChatMessage(role: "user", content: "test")], model: nil)
        }
    }

    @Test("chat throws httpError on 429 rate limit")
    func chatHTTPError429() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let provider = ZhipuProvider(apiKey: testAPIKey, session: makeMockSession())
        await #expect(throws: AIServiceError.self) {
            try await provider.chat(messages: [ChatMessage(role: "user", content: "test")], model: nil)
        }
    }

    @Test("chat throws responseParsingFailed on invalid JSON")
    func chatInvalidJSON() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("not json".utf8))
        }

        let provider = ZhipuProvider(apiKey: testAPIKey, session: makeMockSession())
        await #expect(throws: AIServiceError.self) {
            try await provider.chat(messages: [ChatMessage(role: "user", content: "test")], model: nil)
        }
    }

    @Test("chat throws networkError on connection failure")
    func chatNetworkError() async throws {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let provider = ZhipuProvider(apiKey: testAPIKey, session: makeMockSession())
        await #expect(throws: AIServiceError.self) {
            try await provider.chat(messages: [ChatMessage(role: "user", content: "test")], model: nil)
        }
    }
}
