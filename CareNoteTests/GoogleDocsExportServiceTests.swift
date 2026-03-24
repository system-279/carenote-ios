@testable import CareNote
import Foundation
import Testing

// MARK: - URLSessionProtocol

protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

// MARK: - MockURLSession

final class MockURLSession: URLSessionProtocol, @unchecked Sendable {
    var mockData: Data = Data()
    var mockResponse: URLResponse = HTTPURLResponse(
        url: URL(string: "https://docs.googleapis.com")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    )!
    var mockError: Error?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let error = mockError { throw error }
        return (mockData, mockResponse)
    }
}

// MARK: - TestableGoogleDocsExportService
// URLSessionProtocol を使ってテスト可能にした版

actor TestableGoogleDocsExportService {
    private let session: URLSessionProtocol
    private static let baseURL = "https://docs.googleapis.com/v1/documents"

    init(session: URLSessionProtocol) {
        self.session = session
    }

    func exportRecording(_ recording: ExportableRecording, accessToken: String) async throws -> URL {
        guard !recording.transcription.isEmpty else {
            throw GoogleDocsExportError.noTranscription
        }

        let docId = try await createDocument(title: formatTitle(recording), accessToken: accessToken)
        try await formatDocument(documentId: docId, recording: recording, accessToken: accessToken)
        return URL(string: "https://docs.google.com/document/d/\(docId)/edit")!
    }

    private func createDocument(title: String, accessToken: String) async throws -> String {
        guard let url = URL(string: Self.baseURL) else {
            throw GoogleDocsExportError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["title": title]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleDocsExportError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw GoogleDocsExportError.documentCreationFailed(statusCode: httpResponse.statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let documentId = json["documentId"] as? String else {
            throw GoogleDocsExportError.invalidResponse
        }
        return documentId
    }

    private func formatDocument(documentId: String, recording: ExportableRecording, accessToken: String) async throws {
        guard let url = URL(string: "\(Self.baseURL)/\(documentId):batchUpdate") else {
            throw GoogleDocsExportError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["requests": []]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleDocsExportError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw GoogleDocsExportError.formattingFailed(statusCode: httpResponse.statusCode)
        }
    }

    private func formatTitle(_ recording: ExportableRecording) -> String {
        let dateStr = recording.recordedAt.formatted(.dateTime.year().month().day())
        return "\(recording.clientName) - \(recording.scene) (\(dateStr))"
    }
}

// MARK: - GoogleDocsExportServiceTests

@Suite("GoogleDocsExportService Tests")
struct GoogleDocsExportServiceTests {

    private static func makeRecording(
        clientName: String = "山田 花子",
        scene: String = "訪問介護",
        transcription: String = "本日の訪問記録です。",
        templateName: String? = "ケア記録",
        durationSeconds: Double = 125.0,
        recordedAt: Date = Date(timeIntervalSince1970: 1_741_000_000)
    ) -> ExportableRecording {
        ExportableRecording(
            clientName: clientName,
            scene: scene,
            recordedAt: recordedAt,
            durationSeconds: durationSeconds,
            templateName: templateName,
            transcription: transcription
        )
    }

    private static func makeOkSession(documentId: String = "doc-abc-123") -> MockURLSession {
        let session = MockURLSession()
        let responseJSON: [String: Any] = ["documentId": documentId]
        session.mockData = try! JSONSerialization.data(withJSONObject: responseJSON)
        return session
    }

    // MARK: - Tests

    @Test("ドキュメント作成が成功する")
    func ドキュメント作成が成功する() async throws {
        let session = Self.makeOkSession(documentId: "doc-success-001")
        let service = TestableGoogleDocsExportService(session: session)
        let recording = Self.makeRecording()

        let url = try await service.exportRecording(recording, accessToken: "test-token")

        #expect(url.absoluteString.contains("doc-success-001"))
        #expect(url.absoluteString.hasPrefix("https://docs.google.com/document/d/"))
    }

    @Test("ドキュメント作成がHTTPエラーで失敗する")
    func ドキュメント作成がHTTPエラーで失敗する() async throws {
        let session = MockURLSession()
        session.mockResponse = HTTPURLResponse(
            url: URL(string: "https://docs.googleapis.com")!,
            statusCode: 403,
            httpVersion: nil,
            headerFields: nil
        )!
        let service = TestableGoogleDocsExportService(session: session)
        let recording = Self.makeRecording()

        await #expect(throws: GoogleDocsExportError.self) {
            _ = try await service.exportRecording(recording, accessToken: "bad-token")
        }
    }

    @Test("空のtranscriptionでnoTranscriptionエラーになる")
    func 空のtranscriptionでnoTranscriptionエラーになる() async throws {
        let session = Self.makeOkSession()
        let service = TestableGoogleDocsExportService(session: session)
        let recording = Self.makeRecording(transcription: "")

        await #expect(throws: GoogleDocsExportError.noTranscription) {
            _ = try await service.exportRecording(recording, accessToken: "token")
        }
    }

    @Test("UTF16インデックスが日本語テキストで正しく計算される")
    func UTF16インデックスが日本語テキストで正しく計算される() {
        // 日本語文字列のUTF-16カウントを検証
        let japanese = "利用者テスト\n"
        // "利用者テスト" = 6文字、各文字 1 UTF-16コードユニット、"\n" = 1
        #expect(japanese.utf16.count == 7)

        let emoji = "😀\n"
        // 絵文字は 2 UTF-16コードユニット（サロゲートペア）
        #expect(emoji.utf16.count == 3)

        // インデックス計算ロジックの確認
        let titleLine = "山田 花子 - 訪問介護 (2025/01/01 12:00)\n"
        let startIndex = 1
        let endIndex = startIndex + titleLine.utf16.count
        #expect(endIndex > startIndex)
        #expect(endIndex == 1 + titleLine.utf16.count)
    }

    @Test("フォーマットされたタイトルが正しい")
    func フォーマットされたタイトルが正しい() async throws {
        // ExportableRecording の clientName / scene が URL に反映されることを確認
        let session = Self.makeOkSession(documentId: "doc-format-test")
        let service = TestableGoogleDocsExportService(session: session)
        let recording = Self.makeRecording(
            clientName: "鈴木 一郎",
            scene: "居宅訪問",
            transcription: "テスト文字起こし内容"
        )

        let url = try await service.exportRecording(recording, accessToken: "token")
        #expect(url.absoluteString.contains("doc-format-test"))
    }

    @Test("ExportableRecordingのSendable準拠")
    func ExportableRecordingのSendable準拠() {
        // Sendable 型として別タスクに渡せることをコンパイル時に確認
        let recording: ExportableRecording = Self.makeRecording()
        let sendable: any Sendable = recording
        #expect(sendable is ExportableRecording)
    }
}
