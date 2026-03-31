@testable import CareNote
import Foundation
import Testing

// MARK: - Helper

private let vertexAIURLKey = "aiplatform.googleapis.com"

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
        MockURLProtocol.setHandler(for: vertexAIURLKey) { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, makeVertexAIResponseJSON(text: "テスト文字起こし結果"))
        }
        defer { MockURLProtocol.handlers.removeValue(forKey: vertexAIURLKey) }

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
        MockURLProtocol.setHandler(for: vertexAIURLKey) { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, "Internal Server Error".data(using: .utf8)!)
        }
        defer { MockURLProtocol.handlers.removeValue(forKey: vertexAIURLKey) }

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
        MockURLProtocol.setHandler(for: vertexAIURLKey) { request in
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
        defer { MockURLProtocol.handlers.removeValue(forKey: vertexAIURLKey) }

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
        MockURLProtocol.setHandler(for: vertexAIURLKey) { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, "not json".data(using: .utf8)!)
        }
        defer { MockURLProtocol.handlers.removeValue(forKey: vertexAIURLKey) }

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
