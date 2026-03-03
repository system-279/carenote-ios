@testable import CareNote
import Foundation
import Testing

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

// MARK: - MockURLProtocol

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            fatalError("MockURLProtocol.requestHandler is not set")
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Helper

private func makeMockURLSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

private func makeVertexAIResponseJSON(text: String) -> Data {
    """
    {
        "candidates": [{
            "content": {
                "parts": [{"text": "\(text)"}]
            }
        }]
    }
    """.data(using: .utf8)!
}

// MARK: - TranscriptionServiceTests

@Suite("TranscriptionService Tests", .serialized)
struct TranscriptionServiceTests {

    @Test
    func 正常系_文字起こしテキストが返る() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, makeVertexAIResponseJSON(text: "テスト文字起こし結果"))
        }

        let tokenProvider = MockAccessTokenProvider()
        let service = TranscriptionService(
            projectId: "test-project",
            accessTokenProvider: tokenProvider,
            urlSession: makeMockURLSession()
        )

        let result = try await service.transcribe(audioGCSUri: "gs://bucket/audio.m4a")
        #expect(result == "テスト文字起こし結果")
    }

    @Test
    func 認証失敗時にauthenticationFailedエラー() async {
        let tokenProvider = MockAccessTokenProvider()
        await tokenProvider.setError(WIFError.notAuthenticated)

        let service = TranscriptionService(
            projectId: "test-project",
            accessTokenProvider: tokenProvider,
            urlSession: makeMockURLSession()
        )

        await #expect(throws: TranscriptionError.self) {
            try await service.transcribe(audioGCSUri: "gs://bucket/audio.m4a")
        }
    }

    @Test
    func HTTP_500でrequestFailedエラー() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, "Internal Server Error".data(using: .utf8)!)
        }

        let tokenProvider = MockAccessTokenProvider()
        let service = TranscriptionService(
            projectId: "test-project",
            accessTokenProvider: tokenProvider,
            urlSession: makeMockURLSession()
        )

        await #expect(throws: TranscriptionError.self) {
            try await service.transcribe(audioGCSUri: "gs://bucket/audio.m4a")
        }
    }

    @Test
    func レスポンスにテキストがない場合noTextInResponseエラー() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let body = """
            {
                "candidates": [{
                    "content": {
                        "parts": []
                    }
                }]
            }
            """.data(using: .utf8)!
            return (response, body)
        }

        let tokenProvider = MockAccessTokenProvider()
        let service = TranscriptionService(
            projectId: "test-project",
            accessTokenProvider: tokenProvider,
            urlSession: makeMockURLSession()
        )

        await #expect(throws: TranscriptionError.self) {
            try await service.transcribe(audioGCSUri: "gs://bucket/audio.m4a")
        }
    }

    @Test
    func 不正JSONでinvalidResponseエラー() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, "not json".data(using: .utf8)!)
        }

        let tokenProvider = MockAccessTokenProvider()
        let service = TranscriptionService(
            projectId: "test-project",
            accessTokenProvider: tokenProvider,
            urlSession: makeMockURLSession()
        )

        await #expect(throws: TranscriptionError.self) {
            try await service.transcribe(audioGCSUri: "gs://bucket/audio.m4a")
        }
    }
}

