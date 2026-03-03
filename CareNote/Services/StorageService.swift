import Foundation

// MARK: - StorageError

enum StorageError: Error, Sendable {
    case fileNotFound
    case uploadFailed(Error)
}

// MARK: - StorageService

/// Cloud Storage upload service using GCS JSON API with WIF authentication.
actor StorageService {

    // MARK: - Properties

    private let bucketName: String
    private let accessTokenProvider: any AccessTokenProviding
    private let urlSession: URLSession

    // MARK: - Initialization

    init(
        bucketName: String = AppConfig.storageBucket,
        accessTokenProvider: any AccessTokenProviding,
        urlSession: URLSession = .shared
    ) {
        self.bucketName = bucketName
        self.accessTokenProvider = accessTokenProvider
        self.urlSession = urlSession
    }

    // MARK: - Public Methods

    /// Upload an audio file to Cloud Storage via GCS JSON API.
    /// - Parameters:
    ///   - localURL: The local file URL of the audio recording.
    ///   - tenantId: The tenant identifier for multi-tenant path separation.
    ///   - recordingId: The unique recording identifier.
    /// - Returns: The `gs://` URI of the uploaded file.
    func uploadAudio(
        localURL: URL,
        tenantId: String,
        recordingId: String
    ) async throws -> String {
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            throw StorageError.fileNotFound
        }

        let accessToken: String
        do {
            accessToken = try await accessTokenProvider.getAccessToken()
        } catch {
            throw StorageError.uploadFailed(error)
        }

        let objectName = "\(tenantId)/\(recordingId).m4a"
        let encodedName = objectName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? objectName

        guard let url = URL(
            string: "https://storage.googleapis.com/upload/storage/v1/b/\(bucketName)/o?uploadType=media&name=\(encodedName)"
        ) else {
            throw StorageError.uploadFailed(
                NSError(domain: "StorageService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid upload URL"])
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: localURL)
        request.httpBody = audioData

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode)
        else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "Unknown"
            throw StorageError.uploadFailed(
                NSError(domain: "StorageService", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(statusCode): \(body)"])
            )
        }

        return "gs://\(bucketName)/\(objectName)"
    }
}
