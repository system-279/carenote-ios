import FirebaseStorage
import Foundation

// MARK: - StorageError

enum StorageError: Error, Sendable {
    case fileNotFound
    case uploadFailed(Error)
    case bucketNotConfigured
}

// MARK: - StorageService

/// Cloud Storage for Firebase upload service.
actor StorageService {

    // MARK: - Properties

    private let storage: Storage

    // MARK: - Initialization

    init(storage: Storage = Storage.storage()) {
        self.storage = storage
    }

    // MARK: - Public Methods

    /// Upload an audio file to Cloud Storage.
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

        let storagePath = "\(tenantId)/\(recordingId).m4a"
        let storageRef = storage.reference().child(storagePath)

        let metadata = StorageMetadata()
        metadata.contentType = "audio/mp4"

        do {
            nonisolated(unsafe) let ref = storageRef
            _ = try await ref.putFileAsync(from: localURL, metadata: metadata)
        } catch {
            throw StorageError.uploadFailed(error)
        }

        // Construct gs:// URI
        let bucket = storage.reference().bucket
        let gcsUri = "gs://\(bucket)/\(storagePath)"

        return gcsUri
    }

    /// Upload an audio file with progress reporting via AsyncStream.
    /// - Parameters:
    ///   - localURL: The local file URL of the audio recording.
    ///   - tenantId: The tenant identifier for multi-tenant path separation.
    ///   - recordingId: The unique recording identifier.
    /// - Returns: A tuple of the progress stream and the upload task result.
    func uploadAudioWithProgress(
        localURL: URL,
        tenantId: String,
        recordingId: String
    ) async throws -> (progress: AsyncStream<Double>, gcsUri: String) {
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            throw StorageError.fileNotFound
        }

        let storagePath = "\(tenantId)/\(recordingId).m4a"
        let storageRef = storage.reference().child(storagePath)

        let metadata = StorageMetadata()
        metadata.contentType = "audio/mp4"

        // Create AsyncStream for progress
        var progressContinuation: AsyncStream<Double>.Continuation?
        let progressStream = AsyncStream<Double> { continuation in
            progressContinuation = continuation
        }

        // Start upload task
        nonisolated(unsafe) let uploadTask = storageRef.putFile(from: localURL, metadata: metadata)

        // Observe progress
        uploadTask.observe(.progress) { snapshot in
            if let progress = snapshot.progress {
                let fractionCompleted = progress.fractionCompleted
                progressContinuation?.yield(fractionCompleted)
            }
        }

        // Observe completion
        let gcsUri: String = try await withCheckedThrowingContinuation { continuation in
            uploadTask.observe(.success) { [weak self] _ in
                progressContinuation?.yield(1.0)
                progressContinuation?.finish()

                guard let self else {
                    continuation.resume(throwing: StorageError.bucketNotConfigured)
                    return
                }

                Task {
                    let bucket = await self.getBucket()
                    let uri = "gs://\(bucket)/\(storagePath)"
                    continuation.resume(returning: uri)
                }
            }

            uploadTask.observe(.failure) { snapshot in
                progressContinuation?.finish()
                let error = snapshot.error ?? NSError(
                    domain: "StorageService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Upload failed"]
                )
                continuation.resume(throwing: StorageError.uploadFailed(error))
            }
        }

        return (progress: progressStream, gcsUri: gcsUri)
    }

    // MARK: - Private Methods

    private func getBucket() -> String {
        storage.reference().bucket
    }
}
