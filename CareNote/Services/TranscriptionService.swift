import Foundation

// MARK: - TranscriptionError

enum TranscriptionError: Error, Sendable {
    case authenticationFailed(Error)
    case requestFailed(statusCode: Int, body: String)
    case invalidResponse
    case noTextInResponse
}

// MARK: - Vertex AI Request/Response Models

struct VertexAIRequest: Codable, Sendable {
    let contents: [Content]
    let generationConfig: GenerationConfig

    struct Content: Codable, Sendable {
        let role: String
        let parts: [Part]
    }

    struct Part: Codable, Sendable {
        let text: String?
        let fileData: FileData?

        enum CodingKeys: String, CodingKey {
            case text
            case fileData = "file_data"
        }
    }

    struct FileData: Codable, Sendable {
        let mimeType: String
        let fileUri: String

        enum CodingKeys: String, CodingKey {
            case mimeType = "mime_type"
            case fileUri = "file_uri"
        }
    }

    struct GenerationConfig: Codable, Sendable {
        let temperature: Double
        let maxOutputTokens: Int
        let thinkingConfig: ThinkingConfig?
    }

    struct ThinkingConfig: Codable, Sendable {
        let thinkingBudget: Int
    }
}

struct VertexAIResponse: Codable, Sendable {
    let candidates: [Candidate]?

    struct Candidate: Codable, Sendable {
        let content: Content?
    }

    struct Content: Codable, Sendable {
        let parts: [Part]?
    }

    struct Part: Codable, Sendable {
        let text: String?
    }
}

// MARK: - TranscriptionService

/// Vertex AI Gemini 2.5 Flash transcription service (Spec S11).
actor TranscriptionService {

    // MARK: - Constants

    private let model = "gemini-2.5-flash"
    private let region = "asia-northeast1"

    private let transcriptionPrompt = """
        以下の音声を日本語で文字起こししてください。

        指示:
        - 句読点（。、）を適切に付与してください
        - 「えー」「あのー」などのフィラー（つなぎ言葉）は省略してください
        - 介護用語は正確に記載してください（例: 要介護度、ADL、IADL、ケアプラン、サービス担当者会議 等）
        - 話者の区別がつく場合は話者を明示してください
        - 音声が不明瞭な箇所は [不明瞭] と記載してください
        """

    // MARK: - Properties

    private let projectId: String
    private let accessTokenProvider: any AccessTokenProviding
    private let urlSession: URLSession

    // MARK: - Computed Properties

    private var endpoint: URL {
        URL(
            string: "https://\(region)-aiplatform.googleapis.com/v1/projects/\(projectId)/locations/\(region)/publishers/google/models/\(model):generateContent"
        )!
    }

    // MARK: - Initialization

    init(
        projectId: String,
        accessTokenProvider: any AccessTokenProviding,
        urlSession: URLSession = .shared
    ) {
        self.projectId = projectId
        self.accessTokenProvider = accessTokenProvider
        self.urlSession = urlSession
    }

    // MARK: - Public Methods

    /// Transcribe audio from a GCS URI using Vertex AI Gemini 2.5 Flash.
    /// - Parameter audioGCSUri: The `gs://` URI of the audio file in Cloud Storage.
    /// - Returns: The transcribed text.
    func transcribe(audioGCSUri: String) async throws -> String {
        // Get access token via WIF
        let accessToken: String
        do {
            accessToken = try await accessTokenProvider.getAccessToken()
        } catch {
            throw TranscriptionError.authenticationFailed(error)
        }

        // Build request body
        let requestBody = VertexAIRequest(
            contents: [
                VertexAIRequest.Content(
                    role: "user",
                    parts: [
                        VertexAIRequest.Part(
                            text: nil,
                            fileData: VertexAIRequest.FileData(
                                mimeType: "audio/mp4",
                                fileUri: audioGCSUri
                            )
                        ),
                        VertexAIRequest.Part(
                            text: transcriptionPrompt,
                            fileData: nil
                        ),
                    ]
                ),
            ],
            generationConfig: VertexAIRequest.GenerationConfig(
                temperature: 0.0,
                maxOutputTokens: 8192,
                thinkingConfig: VertexAIRequest.ThinkingConfig(thinkingBudget: 0)
            )
        )

        // Build HTTP request
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(requestBody)

        // Execute request
        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown"
            throw TranscriptionError.requestFailed(statusCode: httpResponse.statusCode, body: body)
        }

        // Parse response
        let vertexResponse: VertexAIResponse
        do {
            vertexResponse = try JSONDecoder().decode(VertexAIResponse.self, from: data)
        } catch {
            throw TranscriptionError.invalidResponse
        }

        // Extract text from response
        guard let text = vertexResponse.candidates?.first?.content?.parts?.compactMap(\.text).joined() else {
            throw TranscriptionError.noTextInResponse
        }

        guard !text.isEmpty else {
            throw TranscriptionError.noTextInResponse
        }

        return text
    }
}
