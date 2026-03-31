@testable import CareNote
import Foundation

// MARK: - MockURLProtocol

/// URL-based routing mock for parallel test execution safety.
/// Multiple test suites can register handlers keyed by URL substring.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var handlers: [String: (URLRequest) throws -> (HTTPURLResponse, Data)] = [:]

    static func setHandler(
        for urlContaining: String,
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) {
        handlers[urlContaining] = handler
    }

    static func clearHandlers() {
        handlers.removeAll()
        requestHandler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let urlString = request.url?.absoluteString ?? ""

        // Try URL-based routing first
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

        // Fallback to legacy single handler
        if let handler = Self.requestHandler {
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

        // No handler matched — return 404
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - MockAccessTokenProvider

actor MockAccessTokenProvider: AccessTokenProviding {
    var tokenToReturn: String = "mock-access-token"
    var errorToThrow: Error?

    func setError(_ error: Error) {
        self.errorToThrow = error
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
