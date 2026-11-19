import Foundation
import Testing
@testable import AIService

/// Every fixture has a unique host and a lock-protected handler. No test below
/// mutates the legacy singleton handler used by preexisting Zhipu tests.
struct IsolatedHTTPFixture: Sendable {
    let host: String
    let baseURL: URL
    let session: URLSession

    init(handler: @escaping MockURLProtocol.Handler) throws {
        let host = "fixture-\(UUID().uuidString.lowercased()).invalid"
        self.host = host
        baseURL = try #require(URL(string: "https://\(host)/v1/"))
        session = makeMockSession()
        MockURLProtocol.register(host: host, handler: handler)
    }

    func close() {
        session.invalidateAndCancel()
        MockURLProtocol.unregister(host: host)
    }
}

@Suite("Isolated OpenAI-compatible REST and SSE")
struct OpenAICompatibleProviderTests {
    @Test(arguments: [false, true])
    func rest(_ jev: Bool) async throws {
        let fixture = try IsolatedHTTPFixture { request in
            #expect(request.url?.path == "/v1/chat/completions")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-key")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            let object = try requestJSONObject(request)
            #expect(object["model"] as? String == "override-model")
            #expect(object["stream"] as? Bool == false)
            let messages = try #require(object["messages"] as? [[String: String]])
            #expect(messages == [["role": "user", "content": "synthetic input"]])
            let response = try testHTTPResponse(request, status: 200, headers: nil)
            return (response, Data(#"{"choices":[{"message":{"content":"synthetic output"}}],"model":"returned-model","usage":{"prompt_tokens":8,"completion_tokens":3}}"#.utf8))
        }
        defer { fixture.close() }
        let provider: any AIProvider = jev
            ? JevGatewayProvider(baseURL: fixture.baseURL, model: "default-model", token: "synthetic-key", session: fixture.session)
            : OpenAICompatibleProvider(baseURL: fixture.baseURL, model: "default-model", apiKey: "synthetic-key", session: fixture.session)
        let response = try await provider.chat(messages: [ChatMessage(role: "user", content: "synthetic input")], model: "override-model")
        #expect(response.content == "synthetic output" && response.model == "returned-model")
        #expect(response.usage?.promptTokens == 8 && response.usage?.completionTokens == 3)
    }

    @Test(arguments: ["", "/v1", "/v1/", "/v1/chat/completions", "/v1/chat/completions/"])
    func paths(_ path: String) async throws {
        let fixture = try IsolatedHTTPFixture { request in
            #expect(request.url?.path == (path.isEmpty ? "/chat/completions" : "/v1/chat/completions"))
            return (try testHTTPResponse(request, status: 200, headers: nil), Data(#"{"choices":[{"message":{"content":"ok"}}]}"#.utf8))
        }
        defer { fixture.close() }
        let url = try #require(URL(string: "https://\(fixture.host)\(path)?synthetic=1"))
        let response = try await OpenAICompatibleProvider(baseURL: url, model: "default-model", apiKey: "synthetic", session: fixture.session).chat(messages: [], model: nil)
        #expect(response.model == "default-model")
    }

    @Test(arguments: [false, true])
    func sse(_ jev: Bool) async throws {
        let fixture = try IsolatedHTTPFixture { request in
            #expect(request.url?.path == "/v1/chat/completions")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-stream-key")
            let object = try requestJSONObject(request)
            #expect(object["stream"] as? Bool == true && object["model"] as? String == "stream-model")
            let body = ": keepalive\n\nevent: message\ndata: {\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"first\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\" second\"}}]}\n\ndata: [DONE]\n\ndata: broken-after-done\n\n"
            return (try testHTTPResponse(request, status: 200, headers: ["Content-Type": "text/event-stream"]), Data(body.utf8))
        }
        defer { fixture.close() }
        let provider: any AIProvider = jev
            ? JevGatewayProvider(baseURL: fixture.baseURL, model: "stream-model", token: "synthetic-stream-key", session: fixture.session)
            : OpenAICompatibleProvider(baseURL: fixture.baseURL, model: "stream-model", apiKey: "synthetic-stream-key", session: fixture.session)
        var chunks: [ChatStreamChunk] = []
        for try await chunk in provider.chatStream(messages: [], model: nil) { chunks.append(chunk) }
        #expect(chunks.map(\.content).joined() == "first second")
        #expect(chunks.filter(\.isFinished).count == 1 && chunks.last?.isFinished == true)
    }

    @Test("Jev anonymous access requires explicit opt-in in REST and SSE")
    func anonymousJev() async throws {
        let fixture = try IsolatedHTTPFixture { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            let object = try requestJSONObject(request)
            let stream = object["stream"] as? Bool == true
            let body = stream ? "data: {\"choices\":[{\"delta\":{\"content\":\"ok\"},\"finish_reason\":\"stop\"}]}\n\n" : #"{"choices":[{"message":{"content":"ok"}}]}"#
            return (try testHTTPResponse(request, status: 200, headers: nil), Data(body.utf8))
        }
        defer { fixture.close() }
        let anonymous = JevGatewayProvider(baseURL: fixture.baseURL, model: "synthetic", allowsUnauthenticated: true, session: fixture.session)
        #expect(try await anonymous.chat(messages: [], model: nil).content == "ok")
        var streamed = ""
        for try await chunk in anonymous.chatStream(messages: [], model: nil) { streamed += chunk.content }
        #expect(streamed == "ok")
        let protected = JevGatewayProvider(baseURL: fixture.baseURL, model: "synthetic", session: fixture.session)
        await expectMissingKey(protected)
        let missingConfigured = JevGatewayProvider(baseURL: fixture.baseURL, model: "synthetic", allowsUnauthenticated: true, keychainService: "missing", keychain: .init(load: { _ in throw KeychainError.itemNotFound }), session: fixture.session)
        await expectMissingKey(missingConfigured)
    }

    @Test(arguments: [false, true])
    func credentialsAndErrors(_ jev: Bool) async throws {
        let fixture = try IsolatedHTTPFixture { request in
            Issue.record("Missing credentials must not issue a request")
            throw URLError(.badServerResponse)
        }
        defer { fixture.close() }
        let missing: any AIProvider = jev
            ? JevGatewayProvider(baseURL: fixture.baseURL, model: "synthetic", keychainService: "missing", keychain: .init(load: { _ in throw KeychainError.itemNotFound }), session: fixture.session)
            : OpenAICompatibleProvider(baseURL: fixture.baseURL, model: "synthetic", keychainService: "missing", keychain: .init(load: { _ in throw KeychainError.itemNotFound }), session: fixture.session)
        await expectMissingKey(missing)
        for key in ["", "  \n"] {
            let empty = OpenAICompatibleProvider(baseURL: fixture.baseURL, model: "synthetic", apiKey: key, session: fixture.session)
            await expectMissingKey(empty)
        }
        for failure in [KeychainError.loadFailed(status: -25308), .unexpectedData] {
            let keychain = KeychainHelper(load: { _ in throw failure })
            let provider: any AIProvider = jev
                ? JevGatewayProvider(baseURL: fixture.baseURL, model: "synthetic", allowsUnauthenticated: true, keychainService: "locked", keychain: keychain, session: fixture.session)
                : OpenAICompatibleProvider(baseURL: fixture.baseURL, model: "synthetic", keychainService: "locked", keychain: keychain, session: fixture.session)
            do { _ = try await provider.chat(messages: [], model: nil); Issue.record("Expected Keychain failure") }
            catch let error as KeychainError {
                switch (failure, error) {
                case (.loadFailed(let expected), .loadFailed(let actual)): #expect(expected == actual)
                case (.unexpectedData, .unexpectedData): break
                default: Issue.record("Wrong Keychain error")
                }
            }
            do { for try await _ in provider.chatStream(messages: [], model: nil) {}; Issue.record("Expected streaming Keychain error") }
            catch { #expect(error is KeychainError) }
        }
    }

    @Test(arguments: [false, true])
    func httpAndMalformed(_ jev: Bool) async throws {
        for (status, body) in [(401, "denied"), (429, "quota"), (503, "down"), (200, "not-json"), (200, #"{"choices":[]}"#)] {
            let fixture = try IsolatedHTTPFixture { request in
                (try testHTTPResponse(request, status: status, headers: nil), Data(body.utf8))
            }
            defer { fixture.close() }
            let provider: any AIProvider = jev
                ? JevGatewayProvider(baseURL: fixture.baseURL, model: "synthetic", token: "synthetic", session: fixture.session)
                : OpenAICompatibleProvider(baseURL: fixture.baseURL, model: "synthetic", apiKey: "synthetic", session: fixture.session)
            do { _ = try await provider.chat(messages: [], model: nil); Issue.record("Expected REST error") }
            catch let error as AIServiceError {
                if status != 200 {
                    guard case .httpError(let code) = error else { Issue.record("Wrong HTTP error"); continue }
                    #expect(code == status)
                } else { guard case .responseParsingFailed = error else { Issue.record("Wrong parse error"); continue } }
            }
            if status != 200 {
                do { for try await _ in provider.chatStream(messages: [], model: nil) {}; Issue.record("Expected SSE HTTP error") }
                catch let error as AIServiceError {
                    guard case .httpError(let code) = error else { Issue.record("Wrong SSE HTTP error"); continue }
                    #expect(code == status)
                }
            }
        }
        for body in ["data: malformed\n\n", "data: {\"choices\":[]}\n\n", "data: {\"choices\":[{\"delta\":{\"content\":\"truncated\"}}]}\n\n"] {
            let fixture = try IsolatedHTTPFixture { request in
                (try testHTTPResponse(request, status: 200, headers: ["Content-Type": "text/event-stream"]), Data(body.utf8))
            }
            defer { fixture.close() }
            let provider: any AIProvider = jev
                ? JevGatewayProvider(baseURL: fixture.baseURL, model: "synthetic", token: "synthetic", session: fixture.session)
                : OpenAICompatibleProvider(baseURL: fixture.baseURL, model: "synthetic", apiKey: "synthetic", session: fixture.session)
            do { for try await _ in provider.chatStream(messages: [], model: nil) {}; Issue.record("Expected SSE parse/interruption error") }
            catch let error as AIServiceError {
                if body.contains("truncated") {
                    guard case .streamingInterrupted(let count, _) = error else { Issue.record("Wrong interruption error"); continue }
                    #expect(count == 1)
                } else { guard case .responseParsingFailed = error else { Issue.record("Wrong SSE parse error"); continue } }
            }
        }
    }

    @Test(arguments: [false, true])
    func cancellationAndNetwork(_ jev: Bool) async throws {
        for code in [URLError.Code.cancelled, .notConnectedToInternet] {
            let fixture = try IsolatedHTTPFixture { _ in throw URLError(code) }
            defer { fixture.close() }
            let provider: any AIProvider = jev
                ? JevGatewayProvider(baseURL: fixture.baseURL, model: "synthetic", token: "synthetic", session: fixture.session)
                : OpenAICompatibleProvider(baseURL: fixture.baseURL, model: "synthetic", apiKey: "synthetic", session: fixture.session)
            do { _ = try await provider.chat(messages: [], model: nil); Issue.record("Expected network/cancellation error") }
            catch {
                if code == .cancelled { #expect(error is CancellationError) }
                else if case AIServiceError.networkError = error {} else { Issue.record("Expected network error") }
            }
            if code == .cancelled {
                await #expect(throws: CancellationError.self) {
                    for try await _ in provider.chatStream(messages: [], model: nil) {}
                }
            }
        }
    }

    @Test("Consumer cancellation stops the pending URLSession stream", .timeLimit(.minutes(1)), arguments: [false, true])
    func consumerCancellation(_ jev: Bool) async throws {
        let fixture = try IsolatedHTTPFixture { _ in
            Issue.record("Held requests must not invoke a response handler")
            throw URLError(.badServerResponse)
        }
        defer { fixture.close() }
        let states = AsyncStream<Bool>.makeStream()
        defer { states.continuation.finish() }
        MockURLProtocol.hold(host: fixture.host) { states.continuation.yield($0) }
        let provider: any AIProvider = jev
            ? JevGatewayProvider(baseURL: fixture.baseURL, model: "synthetic", token: "synthetic", session: fixture.session)
            : OpenAICompatibleProvider(baseURL: fixture.baseURL, model: "synthetic", apiKey: "synthetic", session: fixture.session)
        let stream = provider.chatStream(messages: [], model: nil)
        let consumer = Task {
            do { for try await _ in stream {} }
            catch { #expect(error is CancellationError) }
        }
        var iterator = states.stream.makeAsyncIterator()
        #expect(await iterator.next() == false)
        consumer.cancel()
        await consumer.value
        #expect(await iterator.next() == true)
    }

    private func expectMissingKey(_ provider: any AIProvider) async {
        do { _ = try await provider.chat(messages: [], model: nil); Issue.record("Expected missingAPIKey") }
        catch AIServiceError.missingAPIKey {} catch { Issue.record("Expected missingAPIKey, not another error") }
        do { for try await _ in provider.chatStream(messages: [], model: nil) {}; Issue.record("Expected streaming missingAPIKey") }
        catch AIServiceError.missingAPIKey {} catch { Issue.record("Expected streaming missingAPIKey, not another error") }
    }
}

func testHTTPResponse(_ request: URLRequest, status: Int, headers: [String: String]? = nil) throws -> HTTPURLResponse {
    let url = try #require(request.url)
    return try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers))
}

func requestJSONObject(_ request: URLRequest) throws -> [String: Any] {
    let data = try #require(request.httpBody)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}
