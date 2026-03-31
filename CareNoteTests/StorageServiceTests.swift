@testable import CareNote
import Foundation
import Testing

// MARK: - StorageService Tests

private let storageURLKey = "storage.googleapis.com"

@Suite("StorageService Tests", .serialized)
struct StorageServiceTests {

    private func makeService(
        bucketName: String = "test-bucket",
        tokenProvider: MockAccessTokenProvider = MockAccessTokenProvider()
    ) -> StorageService {
        StorageService(
            bucketName: bucketName,
            accessTokenProvider: tokenProvider,
            urlSession: makeMockURLSession()
        )
    }

    private func createTempAudioFile() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test-\(UUID().uuidString).m4a")
        try Data("fake audio data".utf8).write(to: fileURL)
        return fileURL
    }

    // MARK: - Upload Success

    @Test
    func アップロード成功時にgsURIを返す() async throws {
        MockURLProtocol.setHandler(for: storageURLKey) { request in
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer mock-access-token")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "audio/mp4")

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "{}".data(using: .utf8)!)
        }
        defer { MockURLProtocol.handlers.removeValue(forKey: storageURLKey) }

        let fileURL = try createTempAudioFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let service = makeService()
        let gsURI = try await service.uploadAudio(localURL: fileURL, tenantId: "tenant-1", recordingId: "rec-123")
        #expect(gsURI == "gs://test-bucket/tenant-1/rec-123.m4a")
    }

    // MARK: - File Not Found

    @Test
    func 存在しないファイルでfileNotFoundエラー() async {
        let nonExistentURL = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).m4a")
        let service = makeService()

        await #expect(throws: StorageError.self) {
            try await service.uploadAudio(localURL: nonExistentURL, tenantId: "t", recordingId: "r")
        }
    }

    // MARK: - Auth Failure

    @Test
    func 認証失敗時にuploadFailedエラー() async throws {
        let tokenProvider = MockAccessTokenProvider()
        await tokenProvider.setError(WIFError.notAuthenticated)

        let service = makeService(tokenProvider: tokenProvider)
        let fileURL = try createTempAudioFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        await #expect(throws: StorageError.self) {
            try await service.uploadAudio(localURL: fileURL, tenantId: "t", recordingId: "r")
        }
    }

    // MARK: - HTTP Error

    @Test
    func HTTP403でuploadFailedエラー() async throws {
        MockURLProtocol.setHandler(for: storageURLKey) { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!
            return (response, "Forbidden".data(using: .utf8)!)
        }
        defer { MockURLProtocol.handlers.removeValue(forKey: storageURLKey) }

        let fileURL = try createTempAudioFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let service = makeService()
        await #expect(throws: StorageError.self) {
            try await service.uploadAudio(localURL: fileURL, tenantId: "t", recordingId: "r")
        }
    }

    @Test
    func HTTP500でuploadFailedエラー() async throws {
        MockURLProtocol.setHandler(for: storageURLKey) { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, "Internal Server Error".data(using: .utf8)!)
        }
        defer { MockURLProtocol.handlers.removeValue(forKey: storageURLKey) }

        let fileURL = try createTempAudioFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let service = makeService()
        await #expect(throws: StorageError.self) {
            try await service.uploadAudio(localURL: fileURL, tenantId: "t", recordingId: "r")
        }
    }

    // MARK: - StorageError

    @Test
    func StorageError_fileNotFoundは正しい型() {
        let error = StorageError.fileNotFound
        if case .fileNotFound = error {
            // OK
        } else {
            Issue.record("Expected fileNotFound")
        }
    }

    @Test
    func StorageError_uploadFailedにネストされたエラーを含む() {
        let inner = NSError(domain: "Test", code: 42)
        let error = StorageError.uploadFailed(inner)
        if case .uploadFailed(let wrapped) = error {
            #expect((wrapped as NSError).code == 42)
        } else {
            Issue.record("Expected uploadFailed")
        }
    }
}
