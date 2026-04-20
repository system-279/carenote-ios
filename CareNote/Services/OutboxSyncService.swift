import Foundation
import Network
import os.log
import SwiftData

// MARK: - OutboxSyncError

enum OutboxSyncError: Error, Sendable {
    case modelContainerNotAvailable
    case recordingNotFound(UUID)
    case maxRetriesExceeded(UUID)
    case uploadFailed(Error)
    case transcriptionFailed(Error)
    /// `currentUidProvider` が nil または空文字を返した状態。
    /// 既存 retry ラダー（3回 exponential backoff）に乗せて扱う: アプリ cold-start 直後に
    /// outbox item が enqueue された際、FirebaseAuth のセッション復元と競合して一時的に
    /// uid 未取得になるケースを吸収するため。恒久的な未ログインは 3 回後に
    /// `.maxRetriesExceeded` として `uploadStatus = error` で終端する。
    case userNotAuthenticated
}

// MARK: - OutboxSyncService

/// Offline recording upload queue manager.
/// Uses SwiftData OutboxItem as a persistent queue with NWPathMonitor for connectivity.
actor OutboxSyncService {

    // MARK: - Constants

    private static let maxRetryCount = 3
    private static let baseRetryDelay: TimeInterval = 2.0 // seconds

    // MARK: - Properties

    private let modelContainer: ModelContainer
    private let storageService: any AudioUploading
    private let firestoreService: any RecordingStoring
    private let transcriptionService: any Transcribing
    private let tenantId: String
    private let currentUidProvider: @Sendable () -> String?

    private var pathMonitor: NWPathMonitor?
    private var monitorQueue: DispatchQueue?
    private static let logger = Logger(subsystem: "jp.carenote.app", category: "OutboxSync")

    private var isProcessing = false
    private var isConnected = false

    // MARK: - Initialization

    init(
        modelContainer: ModelContainer,
        storageService: any AudioUploading,
        firestoreService: any RecordingStoring,
        transcriptionService: any Transcribing,
        tenantId: String,
        currentUidProvider: @escaping @Sendable () -> String?
    ) {
        self.modelContainer = modelContainer
        self.storageService = storageService
        self.firestoreService = firestoreService
        self.transcriptionService = transcriptionService
        self.tenantId = tenantId
        self.currentUidProvider = currentUidProvider
    }

    // MARK: - Queue Management

    /// Add a recording to the upload queue.
    /// - Parameter recordingId: The UUID of the recording to enqueue.
    @MainActor
    func enqueue(recordingId: UUID) throws {
        let context = modelContainer.mainContext
        let item = OutboxItem(recordingId: recordingId)
        context.insert(item)
        try context.save()
    }

    /// Process all pending items in the outbox queue.
    func processQueue() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        let items = await fetchPendingItems()

        for item in items {
            guard isConnected else { break }

            // リトライ時は exponential backoff で待機
            if item.retryCount > 0 {
                let delay = Self.baseRetryDelay * pow(2.0, Double(item.retryCount - 1))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            do {
                try await processItem(item)
                await removeItem(item.id)
            } catch {
                await incrementRetryCount(item.id)
            }
        }
    }

    /// Process all pending items immediately, bypassing the isConnected check.
    /// Use this when triggering processing right after enqueuing an item,
    /// since NWPathMonitor callback may not have fired yet.
    /// Throws the last error encountered so the caller can surface it to the user.
    func processQueueImmediately() async throws {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        let items = await fetchPendingItems()
        var lastError: Error?

        for item in items {
            // Skip stale items whose audio file no longer exists (e.g., app reinstalled)
            if let recording = await fetchRecording(id: item.recordingId) {
                if !FileManager.default.fileExists(atPath: recording.localAudioPath) {
                    await removeItem(item.id)
                    continue
                }
            } else {
                await removeItem(item.id)
                continue
            }

            // リトライ時は exponential backoff で待機
            if item.retryCount > 0 {
                let delay = Self.baseRetryDelay * pow(2.0, Double(item.retryCount - 1))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            do {
                try await processItem(item)
                await removeItem(item.id)
            } catch {
                await incrementRetryCount(item.id)
                lastError = error
            }
        }

        if let error = lastError {
            throw error
        }
    }

    // MARK: - Network Monitoring

    /// Start monitoring network connectivity.
    /// Automatically triggers queue processing when connectivity is restored.
    func startMonitoring() {
        guard pathMonitor == nil else { return }

        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "com.carenote.outbox.network")

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            Task {
                await self.handleNetworkChange(isConnected: path.status == .satisfied)
            }
        }

        monitor.start(queue: queue)
        pathMonitor = monitor
        monitorQueue = queue
    }

    /// Stop monitoring network connectivity.
    func stopMonitoring() {
        pathMonitor?.cancel()
        pathMonitor = nil
        monitorQueue = nil
    }

    // MARK: - Private Methods

    private func handleNetworkChange(isConnected: Bool) async {
        self.isConnected = isConnected

        if isConnected {
            await processQueue()
        }
    }

    @MainActor
    private func fetchPendingItems() -> [(id: UUID, recordingId: UUID, retryCount: Int)] {
        let context = modelContainer.mainContext

        let maxRetry = Self.maxRetryCount
        var descriptor = FetchDescriptor<OutboxItem>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.predicate = #Predicate<OutboxItem> { item in
            item.retryCount < maxRetry
        }

        guard let items = try? context.fetch(descriptor) else {
            return []
        }

        return items.map { (id: $0.id, recordingId: $0.recordingId, retryCount: $0.retryCount) }
    }

    private func processItem(_ item: (id: UUID, recordingId: UUID, retryCount: Int)) async throws {
        // Fetch recording from SwiftData
        guard let recording = await fetchRecording(id: item.recordingId) else {
            throw OutboxSyncError.recordingNotFound(item.recordingId)
        }

        // Pre-flight auth check for new recordings: avoid uploading audio to
        // Cloud Storage when Firestore document creation will fail at uid
        // validation anyway. Prevents medical audio orphaning in Storage during
        // auth cold-start edge cases (uid nil/empty). `buildFirestoreRecording`
        // re-validates as a defense-in-depth for existing firestoreId paths.
        if recording.firestoreId == nil {
            guard let uid = currentUidProvider(), !uid.isEmpty else {
                throw OutboxSyncError.userNotAuthenticated
            }
            _ = uid
        }

        // Step 1: Upload audio to Cloud Storage
        let localURL = URL(fileURLWithPath: recording.localAudioPath)
        let gcsUri: String
        do {
            gcsUri = try await storageService.uploadAudio(
                localURL: localURL,
                tenantId: tenantId,
                recordingId: item.recordingId.uuidString
            )
        } catch {
            throw OutboxSyncError.uploadFailed(error)
        }

        // Step 2: Create or update Firestore document
        let fid: String
        if let existing = recording.firestoreId {
            fid = existing
        } else {
            let recordingData = try await buildFirestoreRecording(recordingId: item.recordingId, gcsUri: gcsUri)
            let newId = try await firestoreService.createRecording(tenantId: tenantId, recording: recordingData)
            await updateFirestoreId(recordingId: item.recordingId, firestoreId: newId)
            fid = newId
        }

        try? await firestoreService.updateTranscription(
            tenantId: tenantId,
            recordingId: fid,
            transcription: "",
            status: .processing
        )

        // Step 3: Trigger transcription (with template prompt if available)
        let transcription: String
        do {
            transcription = try await transcriptionService.transcribe(
                audioGCSUri: gcsUri,
                templatePrompt: recording.templatePromptSnapshot
            )
        } catch {
            throw OutboxSyncError.transcriptionFailed(error)
        }

        // Step 4: Update Firestore with transcription result
        try await firestoreService.updateTranscription(
            tenantId: tenantId,
            recordingId: fid,
            transcription: transcription,
            status: .done
        )

        // Step 5: Update local SwiftData record
        await updateRecordingStatus(
            id: item.recordingId,
            uploadStatus: .done,
            transcription: transcription,
            transcriptionStatus: .done
        )
    }

    @MainActor
    private func fetchRecording(id: UUID) -> (localAudioPath: String, firestoreId: String?, templatePromptSnapshot: String?)? {
        let context = modelContainer.mainContext

        let descriptor = FetchDescriptor<RecordingRecord>(
            predicate: #Predicate<RecordingRecord> { $0.id == id }
        )

        guard let record = try? context.fetch(descriptor).first else {
            return nil
        }

        return (localAudioPath: record.localAudioPath, firestoreId: record.firestoreId, templatePromptSnapshot: record.templatePromptSnapshot)
    }

    @MainActor
    private func updateRecordingStatus(
        id: UUID,
        uploadStatus: UploadStatus,
        transcription: String,
        transcriptionStatus: TranscriptionStatus
    ) {
        let context = modelContainer.mainContext

        let descriptor = FetchDescriptor<RecordingRecord>(
            predicate: #Predicate<RecordingRecord> { $0.id == id }
        )

        guard let record = try? context.fetch(descriptor).first else { return }

        record.uploadStatus = uploadStatus.rawValue
        record.transcription = transcription
        record.transcriptionStatus = transcriptionStatus.rawValue

        do {
            try context.save()
        } catch {
            Self.logger.error("Failed to save recording status: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func removeItem(_ id: UUID) {
        let context = modelContainer.mainContext

        let descriptor = FetchDescriptor<OutboxItem>(
            predicate: #Predicate<OutboxItem> { $0.id == id }
        )

        guard let item = try? context.fetch(descriptor).first else { return }

        context.delete(item)
        do {
            try context.save()
        } catch {
            Self.logger.error("Failed to remove outbox item: \(error.localizedDescription)")
        }
    }

    /// internal 可視性は OutboxSyncServiceTests から直接呼ぶためのテストシーム。
    /// 本番コードパスでは `processItem` からのみ呼び出すこと。
    @MainActor
    func buildFirestoreRecording(recordingId: UUID, gcsUri: String) throws -> FirestoreRecording {
        // issue #99 の二段防御: currentUidProvider は `String?` だが、Firebase Auth が
        // token refresh 境界等で非 nil の空文字を返す可能性を排除できない。
        // 空文字で createdBy を保存すると deleteAccount の
        // `where createdBy == uid` クエリで永遠に孤立化するため、nil 同等に拒否する。
        guard let uid = currentUidProvider(), !uid.isEmpty else {
            throw OutboxSyncError.userNotAuthenticated
        }
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<RecordingRecord>(
            predicate: #Predicate<RecordingRecord> { $0.id == recordingId }
        )
        let records: [RecordingRecord]
        do {
            records = try context.fetch(descriptor)
        } catch {
            Self.logger.error("SwiftData fetch failed for \(recordingId): \(error.localizedDescription)")
            throw error
        }
        guard let record = records.first else {
            throw OutboxSyncError.recordingNotFound(recordingId)
        }

        return FirestoreRecording(
            clientId: record.clientId,
            clientName: record.clientName,
            scene: record.scene,
            recordedAt: record.recordedAt,
            durationSeconds: record.durationSeconds,
            audioStoragePath: gcsUri,
            transcription: nil,
            transcriptionStatus: TranscriptionStatus.processing.rawValue,
            createdBy: uid,
            createdAt: record.recordedAt,
            updatedAt: Date()
        )
    }

    @MainActor
    private func updateFirestoreId(recordingId: UUID, firestoreId: String) {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<RecordingRecord>(
            predicate: #Predicate<RecordingRecord> { $0.id == recordingId }
        )
        guard let record = try? context.fetch(descriptor).first else { return }
        record.firestoreId = firestoreId
        do {
            try context.save()
        } catch {
            Self.logger.error("Failed to save firestoreId: \(error.localizedDescription)")
        }
    }

    @MainActor
    func incrementRetryCount(_ id: UUID) {
        let context = modelContainer.mainContext

        let descriptor = FetchDescriptor<OutboxItem>(
            predicate: #Predicate<OutboxItem> { $0.id == id }
        )

        guard let item = try? context.fetch(descriptor).first else { return }

        item.retryCount += 1

        // 最大リトライ超過時、RecordingRecord のステータスを error に更新
        if item.retryCount >= Self.maxRetryCount {
            let recordingId = item.recordingId
            let recDescriptor = FetchDescriptor<RecordingRecord>(
                predicate: #Predicate<RecordingRecord> { $0.id == recordingId }
            )
            if let record = try? context.fetch(recDescriptor).first {
                if record.uploadStatus == UploadStatus.pending.rawValue {
                    record.uploadStatus = UploadStatus.error.rawValue
                }
                if record.transcriptionStatus != TranscriptionStatus.done.rawValue {
                    record.transcriptionStatus = TranscriptionStatus.error.rawValue
                }
            }
        }

        do {
            try context.save()
        } catch {
            Self.logger.error("Failed to save retry count: \(error.localizedDescription)")
        }
    }
}
