import Foundation
import Synchronization
import Testing
@testable import TelemetryKit

private final class BlobRequestCapture: Sendable {
    private let requests = Mutex<[URLRequest]>([])

    var captured: [URLRequest] { requests.withLock { $0 } }

    func append(_ request: URLRequest) {
        requests.withLock { $0.append(request) }
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.withLock { $0.append(request) }
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(
            url: url, statusCode: 201, httpVersion: nil, headerFields: nil
        ))
        return (Data(), response)
    }
}

private actor UploadGate {
    private var started = false
    private var released = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func markStarted() {
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func waitUntilReleased() async {
        guard !released else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func release() {
        released = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private actor UploadConcurrencyProbe {
    private var active = 0
    private(set) var maximumActive = 0
    let capture = BlobRequestCapture()
    let gate = UploadGate()

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        active += 1
        maximumActive = max(maximumActive, active)
        defer { active -= 1 }
        await gate.markStarted()
        await gate.waitUntilReleased()
        // Let competing flushes reach the transport while this upload is suspended.
        for _ in 0..<20 { await Task.yield() }
        return try await capture.send(request)
    }
}

@Suite("Blob telemetry configuration")
struct BlobTelemetryConfigurationTests {
    private let info: [String: Any] = [
        "LokiKitBlobEndpoint": "https://example.blob.core.windows.net/container",
        "LokiKitBlobSAS": "sv=2023-11-03&sr=c&sig=abc"
    ]

    @Test("resolves settings and creates a dated JSONL blob URL")
    func resolvesAndBuildsURL() throws {
        let configuration = try #require(BlobTelemetryConfiguration.resolve(from: info))
        let date = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01 UTC
        let url = try #require(configuration.blobUploadURL(appName: "vitalstride", date: date, batchID: "batch-1"))
        #expect(url.absoluteString == "https://example.blob.core.windows.net/container/vitalstride/2024/01/01/batch-1.jsonl?sv=2023-11-03&sr=c&sig=abc")
    }

    @Test("rejects incomplete or unsafe settings")
    func rejectsInvalidSettings() {
        #expect(BlobTelemetryConfiguration.resolve(from: [:]) == nil)
        #expect(BlobTelemetryConfiguration.resolve(from: [
            "LokiKitBlobEndpoint": "$(BLOB_ENDPOINT)",
            "LokiKitBlobSAS": "sv=1&sig=abc"
        ]) == nil)
        #expect(BlobTelemetryConfiguration.resolve(from: [
            "LokiKitBlobEndpoint": "http://example.test/container",
            "LokiKitBlobSAS": "sv=1&sig=abc"
        ]) == nil)
        #expect(BlobTelemetryConfiguration.resolve(from: [
            "LokiKitBlobEndpoint": "https://example.test/container",
            "LokiKitBlobSAS": "sv=1"
        ]) == nil)
    }
}

@Suite("Blob telemetry provider")
struct BlobTelemetryProviderTests {
    private var configuration: BlobTelemetryConfiguration {
        get throws {
            let endpoint = try #require(URL(string: "https://example.blob.core.windows.net/container"))
            return BlobTelemetryConfiguration(endpoint: endpoint, sas: "sv=2023-11-03&sr=c&sig=abc")
        }
    }

    @Test("flush includes every event accepted by concurrent track calls")
    func flushAwaitsConcurrentTracks() async throws {
        let capture = BlobRequestCapture()
        let provider = BlobTelemetryProvider(
            configuration: try configuration, appName: "vitalstride", version: "1.0",
            build: "42", isDebugBuild: false, transport: capture.send
        )
        let eventCount = 1_000
        DispatchQueue.concurrentPerform(iterations: eventCount) { index in
            provider.track(.workoutCompleted(durationSeconds: index, exerciseCount: 1, setCount: 1))
        }
        try await provider.flush(batchID: "concurrent-tracks")

        let requests = capture.captured
        #expect(requests.count == 1)
        let body = try #require(requests.first?.httpBody)
        let records = body.split(separator: 0x0A)
        let durations = try records.map { line in
            let record = try #require(JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
            let properties = try #require(record["properties"] as? [String: String])
            return try #require(properties["duration_s"])
        }
        #expect(records.count == eventCount)
        #expect(Set(durations) == Set((0..<eventCount).map { String($0) }))
    }

    @Test("concurrent track and flush calls serialize uploads without losing events")
    func concurrentFlushesAreSerialized() async throws {
        let probe = UploadConcurrencyProbe()
        let provider = BlobTelemetryProvider(
            configuration: try configuration, appName: "vitalstride", version: "1.0",
            build: "42", isDebugBuild: false, transport: probe.send
        )
        let eventCount = 128
        provider.track(.workoutCompleted(durationSeconds: 0, exerciseCount: 1, setCount: 1))
        let firstFlush = Task { try await provider.flush(batchID: "first") }
        await probe.gate.waitUntilStarted()
        DispatchQueue.concurrentPerform(iterations: eventCount - 1) { index in
            provider.track(.workoutCompleted(durationSeconds: index + 1, exerciseCount: 1, setCount: 1))
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<eventCount {
                group.addTask {
                    try await provider.flush(batchID: "concurrent-\(index)")
                }
            }
            await probe.gate.release()
            try await group.waitForAll()
        }
        try await firstFlush.value
        try await provider.flush(batchID: "final")

        #expect(await probe.maximumActive == 1)
        let requests = probe.capture.captured
        #expect(requests.count == 2)
        let durations = try requests.flatMap { request in
            let body = try #require(request.httpBody)
            return try body.split(separator: 0x0A).map { line in
                let record = try #require(JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
                let properties = try #require(record["properties"] as? [String: String])
                return try #require(properties["duration_s"])
            }
        }
        #expect(durations.count == eventCount)
        #expect(Set(durations) == Set((0..<eventCount).map { String($0) }))
    }

    @Test("serializes typed events and uploads with Azure headers")
    func uploadsJSONL() async throws {
        let capture = BlobRequestCapture()
        let provider = BlobTelemetryProvider(
            configuration: try configuration, appName: "vitalstride", version: "1.0",
            build: "42", isDebugBuild: false, transport: capture.send
        )
        provider.track(.workoutCompleted(durationSeconds: 120, exerciseCount: 2, setCount: 6))
        await Task.yield()
        try await provider.flush(date: Date(timeIntervalSince1970: 1_704_067_200), batchID: "batch")

        let request = try #require(capture.captured.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.value(forHTTPHeaderField: "x-ms-blob-type") == "BlockBlob")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-ndjson")
        let body = try #require(request.httpBody)
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.contains("\"event_name\":\"workout_completed\""))
        #expect(text.contains("\"duration_s\":\"120\""))
        #expect(!text.contains("\"heart_rate\""))
    }

    @Test("DEBUG guard does not accept events")
    func debugNoOp() async throws {
        let capture = BlobRequestCapture()
        let provider = BlobTelemetryProvider(
            configuration: try configuration, appName: "vitalstride", version: "1.0",
            build: "42", isDebugBuild: true, transport: capture.send
        )
        provider.track(.onboardingCompleted)
        try await provider.flush()
        #expect(capture.captured.isEmpty)
    }

    @Test("TelemetryService forwards events to the blob provider")
    func integratesWithTelemetryService() async throws {
        let capture = BlobRequestCapture()
        let provider = BlobTelemetryProvider(
            configuration: try configuration, appName: "vitalstride", version: "1.0",
            build: "42", isDebugBuild: false, transport: capture.send
        )
        let service = TelemetryService()
        await service.register(provider)
        await service.track(.aiInsightGenerated(durationMs: 200, cardCount: 3))
        try await provider.flush(batchID: "integration")
        #expect(capture.captured.count == 1)
    }

    @Test("retains events tracked during an in-flight upload")
    func retainsConcurrentEvents() async throws {
        let capture = BlobRequestCapture()
        let gate = UploadGate()
        let provider = BlobTelemetryProvider(
            configuration: try configuration, appName: "vitalstride", version: "1.0",
            build: "42", isDebugBuild: false,
            transport: { request in
                await gate.markStarted()
                await gate.waitUntilReleased()
                return try await capture.send(request)
            }
        )

        provider.track(.onboardingCompleted)
        let firstFlush = Task<Void, Error> { try await provider.flush(batchID: "first") }
        await gate.waitUntilStarted()
        provider.track(.workoutCompleted(durationSeconds: 30, exerciseCount: 1, setCount: 1))
        await gate.release()
        try await firstFlush.value
        try await provider.flush(batchID: "second")

        let requests = capture.captured
        #expect(requests.count == 2)
        let firstBody = String(decoding: try #require(requests[0].httpBody), as: UTF8.self)
        let secondBody = String(decoding: try #require(requests[1].httpBody), as: UTF8.self)
        #expect(firstBody.contains("\"event_name\":\"onboarding_completed\""))
        #expect(!firstBody.contains("\"event_name\":\"workout_completed\""))
        #expect(secondBody.contains("\"event_name\":\"workout_completed\""))
    }
}
