import Foundation
import Synchronization

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    private static let isolatedHandlers = Mutex<[String: Handler]>([:])
    private static let heldHandlers = Mutex<[String: @Sendable (Bool) -> Void]>([:])

    static func hold(host: String, onStateChange: @escaping @Sendable (Bool) -> Void) {
        heldHandlers.withLock { $0[host] = onStateChange }
    }

    static func register(host: String, handler: @escaping Handler) {
        isolatedHandlers.withLock { $0[host] = handler }
    }

    static func unregister(host: String) {
        _ = isolatedHandlers.withLock { $0.removeValue(forKey: host) }
        _ = heldHandlers.withLock { $0.removeValue(forKey: host) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let onStateChange = Self.heldHandlers.withLock({ $0[request.url?.host ?? ""] }) {
            onStateChange(false)
            return
        }
        let isolated = Self.isolatedHandlers.withLock { $0[request.url?.host ?? ""] }
        guard let handler = isolated ?? MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        var captured = request
        if captured.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            defer {
                buffer.deallocate()
                stream.close()
            }
            while stream.hasBytesAvailable {
                let bytesRead = stream.read(buffer, maxLength: 4096)
                if bytesRead > 0 {
                    data.append(buffer, count: bytesRead)
                } else {
                    break
                }
            }
            captured.httpBody = data
        }

        do {
            let (response, data) = try handler(captured)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        Self.heldHandlers.withLock { $0[request.url?.host ?? ""] }?(true)
    }
}

func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}
