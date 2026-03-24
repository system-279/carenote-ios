import Foundation
import OSLog

// MARK: - ExportableRecording

struct ExportableRecording: Sendable {
    let clientName: String
    let scene: String
    let recordedAt: Date
    let durationSeconds: Double
    let templateName: String?
    let transcription: String
}

// MARK: - GoogleDocsExportError

enum GoogleDocsExportError: Error, LocalizedError, Sendable, Equatable {
    case documentCreationFailed(statusCode: Int)
    case formattingFailed(statusCode: Int)
    case invalidResponse
    case noTranscription

    var errorDescription: String? {
        switch self {
        case .documentCreationFailed(let code): return "ドキュメントの作成に失敗しました (HTTP \(code))"
        case .formattingFailed(let code): return "ドキュメントの書式設定に失敗しました (HTTP \(code))"
        case .invalidResponse: return "サーバーから無効なレスポンスが返されました"
        case .noTranscription: return "文字起こしデータがありません"
        }
    }
}

// MARK: - GoogleDocsExporting Protocol

protocol GoogleDocsExporting: Sendable {
    func exportRecording(_ recording: ExportableRecording, accessToken: String) async throws -> URL
}

// MARK: - GoogleDocsExportService

actor GoogleDocsExportService: GoogleDocsExporting {
    private let session: URLSession
    private static let baseURL = "https://docs.googleapis.com/v1/documents"

    init(session: URLSession = .shared) {
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

    // MARK: - Private

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

        let requests = buildBatchUpdateBody(recording: recording)
        let body: [String: Any] = ["requests": requests]
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

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let mm = total / 60
        let ss = total % 60
        return String(format: "%02d:%02d", mm, ss)
    }

    private func buildBatchUpdateBody(recording: ExportableRecording) -> [[String: Any]] {
        let dateStr = recording.recordedAt.formatted(.dateTime.year().month().day().hour().minute())
        let duration = formatDuration(recording.durationSeconds)
        let templateName = recording.templateName ?? "文字起こし"

        let titleLine = "\(recording.clientName) - \(recording.scene) (\(dateStr))\n"
        let metaLine = "録音時間: \(duration) | 出力形式: \(templateName)\n"
        let separator = "\n"
        let headingLine = "文字起こし\n"
        let bodyText = recording.transcription + "\n"

        let fullText = titleLine + metaLine + separator + headingLine + bodyText

        // Google Docs API はUTF-16コードユニット数でインデックスを計算する
        var idx = 1  // Google Docs はインデックス1始まり
        let titleStart = idx
        let titleEnd = idx + titleLine.utf16.count
        idx = titleEnd
        let metaStart = idx
        let metaEnd = idx + metaLine.utf16.count
        idx = metaEnd + separator.utf16.count
        let headingStart = idx
        let headingEnd = idx + headingLine.utf16.count

        var requests: [[String: Any]] = []

        // 1. テキスト全体を挿入
        requests.append([
            "insertText": [
                "text": fullText,
                "location": ["index": 1],
            ]
        ])

        // 2. タイトル行を HEADING_1 に
        requests.append([
            "updateParagraphStyle": [
                "range": ["startIndex": titleStart, "endIndex": titleEnd - 1],
                "paragraphStyle": ["namedStyleType": "HEADING_1"],
                "fields": "namedStyleType",
            ]
        ])

        // 3. メタ行をグレー・小フォントに
        requests.append([
            "updateTextStyle": [
                "range": ["startIndex": metaStart, "endIndex": metaEnd - 1],
                "textStyle": [
                    "foregroundColor": ["color": ["rgbColor": ["red": 0.5, "green": 0.5, "blue": 0.5]]],
                    "fontSize": ["magnitude": 10, "unit": "PT"],
                ],
                "fields": "foregroundColor,fontSize",
            ]
        ])

        // 4. 見出し行を HEADING_2 に
        requests.append([
            "updateParagraphStyle": [
                "range": ["startIndex": headingStart, "endIndex": headingEnd - 1],
                "paragraphStyle": ["namedStyleType": "HEADING_2"],
                "fields": "namedStyleType",
            ]
        ])

        return requests
    }
}
