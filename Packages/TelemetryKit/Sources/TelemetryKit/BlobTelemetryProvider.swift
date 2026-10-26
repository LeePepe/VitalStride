import Foundation
import Synchronization

/// Uploads typed telemetry as privacy-safe JSONL records to Azure Blob Storage.
public final class BlobTelemetryProvider: TelemetryProvider, Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let isDebugBuild: Bool
    private let uploader: Uploader
    private let pendingWork = Mutex<Task<Void, Never>?>(nil)
    private let pendingFlush = Mutex<Task<Void, Error>?>(nil)

    public init(
        configuration: BlobTelemetryConfiguration,
        appName: String,
        version: String,
        build: String,
        isDebugBuild: Bool = {
            #if DEBUG
            true
            #else
            false
            #endif
        }(),
        transport: @escaping Transport = BlobTelemetryProvider.liveTransport
    ) {
        self.isDebugBuild = isDebugBuild
        uploader = Uploader(configuration: configuration, appName: appName, version: version,
                            build: build, transport: transport)
    }

    public func track(_ event: TelemetryEvent) {
        guard !isDebugBuild else { return }
        pendingWork.withLock { pending in
            let previous = pending
            pending = Task {
                await previous?.value
                await uploader.append(event)
            }
        }
    }

    /// Uploads all events accepted since the previous flush.
    public func flush(date: Date = Date(), batchID: String = UUID().uuidString) async throws {
        guard !isDebugBuild else { return }
        let current = pendingFlush.withLock { pending in
            let previous = pending
            let current = Task { () throws -> Void in
                do {
                    try await previous?.value
                } catch {
                    // A failed flush must not prevent a later flush from retrying its buffer.
                }
                let work = pendingWork.withLock { $0 }
                await work?.value
                try await uploader.flush(date: date, batchID: batchID)
            }
            pending = current
            return current
        }
        try await current.value
    }

    public static func liveTransport(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }

    private actor Uploader {
        private let configuration: BlobTelemetryConfiguration
        private let appName: String
        private let version: String
        private let build: String
        private let transport: Transport
        private var events: [TelemetryEvent] = []

        init(configuration: BlobTelemetryConfiguration, appName: String, version: String,
             build: String, transport: @escaping Transport) {
            self.configuration = configuration
            self.appName = appName
            self.version = version
            self.build = build
            self.transport = transport
        }

        func append(_ event: TelemetryEvent) {
            events.append(event)
        }

        func flush(date: Date, batchID: String) async throws {
            guard !events.isEmpty else { return }
            guard let url = configuration.blobUploadURL(appName: appName, date: date, batchID: batchID) else {
                throw BlobTelemetryError.invalidUploadURL
            }
            let batch = events
            let payload = try Self.jsonl(events: batch, appName: appName, version: version, build: build)
            events.removeAll(keepingCapacity: true)
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.httpBody = payload
            request.setValue("BlockBlob", forHTTPHeaderField: "x-ms-blob-type")
            request.setValue("application/x-ndjson", forHTTPHeaderField: "Content-Type")
            do {
                let (_, response) = try await transport(request)
                guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                    throw BlobTelemetryError.invalidResponse
                }
            } catch {
                events.insert(contentsOf: batch, at: 0)
                throw error
            }
        }

        private static func jsonl(events: [TelemetryEvent], appName: String, version: String,
                                  build: String) throws -> Data {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            return try events.map { event in
                let record: [String: AnyEncodable] = [
                    "schema_version": AnyEncodable(1),
                    "timestamp": AnyEncodable(Date()),
                    "app": AnyEncodable(appName),
                    "version": AnyEncodable(version),
                    "build": AnyEncodable(build),
                    "event_type": AnyEncodable("product"),
                    "event_name": AnyEncodable(event.eventName),
                    "properties": AnyEncodable(event.parameters.reduce(into: [String: String]()) {
                        $0[$1.key] = $1.value
                    })
                ]
                return try encoder.encode(record)
            }.joined(separator: Data([0x0A])) + Data([0x0A])
        }
    }
}

public enum BlobTelemetryError: Error, Equatable, Sendable {
    case invalidUploadURL
    case invalidResponse
}

private struct AnyEncodable: Encodable, Sendable {
    private let encodeValue: @Sendable (Encoder) throws -> Void

    init<T: Encodable & Sendable>(_ value: T) {
        encodeValue = { encoder in try value.encode(to: encoder) }
    }

    func encode(to encoder: Encoder) throws {
        try encodeValue(encoder)
    }
}
