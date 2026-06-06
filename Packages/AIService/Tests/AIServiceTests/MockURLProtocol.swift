import Foundation

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
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

    override func stopLoading() {}
}

func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}
