@testable import CareNote
import Foundation

// MARK: - MockURLProtocol

/// URL-based routing mock that allows multiple handlers to be registered by URL substring.
/// Note: `handlers` is a global nonisolated(unsafe) static dictionary. Test suites that register
/// handlers must use `.serialized` to avoid cross-suite state collisions.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handlers: [String: (URLRequest) throws -> (HTTPURLResponse, Data)] = [:]

    static func setHandler(
        for urlContaining: String,
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) {
        handlers[urlContaining] = handler
    }

    static func clearHandlers() {
        handlers.removeAll()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    /// `URLSession` は `httpBody` を内部で `httpBodyStream` に変換してから
    /// `URLProtocol` へ渡すことがある（Foundation の既知の挙動）。
    /// そのままだと `startLoading()` 内で `request.httpBody` が `nil` になり、
    /// リクエストボディを検証するテストが本来の挙動を観測できない。
    /// ここで stream を読み戻して `httpBody` に復元する。
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        guard request.httpBody == nil, let bodyStream = request.httpBodyStream else {
            return request
        }

        bodyStream.open()
        defer { bodyStream.close() }

        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while bodyStream.hasBytesAvailable {
            let bytesRead = bodyStream.read(&buffer, maxLength: bufferSize)
            if bytesRead > 0 {
                data.append(buffer, count: bytesRead)
            } else {
                break
            }
        }

        var newRequest = request
        newRequest.httpBodyStream = nil
        newRequest.httpBody = data
        return newRequest
    }

    override func startLoading() {
        let urlString = request.url?.absoluteString ?? ""

        // URL-based routing: match registered handlers by URL substring
        // NOTE: Dictionary iteration order is undefined in Swift.
        // Ensure registered keys are mutually exclusive substrings.
        for (key, handler) in Self.handlers {
            if urlString.contains(key) {
                do {
                    let (response, data) = try handler(request)
                    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                    client?.urlProtocol(self, didLoad: data)
                    client?.urlProtocolDidFinishLoading(self)
                } catch {
                    client?.urlProtocol(self, didFailWithError: error)
                }
                return
            }
        }

        // No handler matched — fail fast to detect test setup errors
        fatalError("""
        MockURLProtocol: No handler registered for URL: \(urlString)
        Registered keys: \(Array(Self.handlers.keys))
        Did you forget to call MockURLProtocol.setHandler(for:) in your test?
        """)
    }

    override func stopLoading() {}
}

// MARK: - MockAccessTokenProvider

actor MockAccessTokenProvider: AccessTokenProviding {
    private var tokenToReturn: String = "mock-access-token"
    private var errorToThrow: Error?

    func setError(_ error: Error?) {
        self.errorToThrow = error
    }

    func setToken(_ token: String) {
        self.tokenToReturn = token
    }

    func getAccessToken() async throws -> String {
        if let error = errorToThrow {
            throw error
        }
        return tokenToReturn
    }
}

// MARK: - Helper Functions

func makeMockURLSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}
