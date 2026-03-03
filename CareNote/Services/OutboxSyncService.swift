import Foundation
import Network
import SwiftData

// MARK: - OutboxSyncError

enum OutboxSyncError: Error, Sendable {
    case modelContainerNotAvailable
    case recordingNotFound(UUID)
    case maxRetriesExceeded(UUID)
    case uploadFailed(Error)
    case transcriptionFailed(Error)
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
    private let storageService: StorageService
    private let firestoreService: FirestoreService
    private let transcriptionService: TranscriptionService
    private let tenantId: String

    private var pathMonitor: NWPathMonitor?
    private var monitorQueue: DispatchQueue?
    private var isProcessing = false
    private var isConnected = false

    // MARK: - Initialization

    init(
        modelContainer: ModelContainer,
        storageService: StorageService,
        firestoreService: FirestoreService,
        transcriptionService: TranscriptionService,
        tenantId: String
    ) {
        self.modelContainer = modelContainer
        self.storageService = storageService
        self.firestoreService = firestoreService
        self.transcriptionService = transcriptionService
        self.tenantId = tenantId
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
    func processQueueImmediately() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        let items = await fetchPendingItems()

        for item in items {
            do {
                try await processItem(item)
                await removeItem(item.id)
            } catch {
                await incrementRetryCount(item.id)
            }
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
        var firestoreId = recording.firestoreId
        if firestoreId == nil {
            let recordingData = await buildFirestoreRecording(recordingId: item.recordingId, gcsUri: gcsUri)
            if let data = recordingData {
                firestoreId = try await firestoreService.createRecording(tenantId: tenantId, recording: data)
                await updateFirestoreId(recordingId: item.recordingId, firestoreId: firestoreId!)
            }
        }

        if let fid = firestoreId {
            try? await firestoreService.updateTranscription(
                tenantId: tenantId,
                recordingId: fid,
                transcription: "",
                status: .processing
            )
        }

        // Step 3: Trigger transcription
        let transcription: String
        do {
            transcription = try await transcriptionService.transcribe(audioGCSUri: gcsUri)
        } catch {
            throw OutboxSyncError.transcriptionFailed(error)
        }

        // Step 4: Update Firestore with transcription result
        if let fid = firestoreId {
            try await firestoreService.updateTranscription(
                tenantId: tenantId,
                recordingId: fid,
                transcription: transcription,
                status: .done
            )
        }

        // Step 5: Update local SwiftData record
        await updateRecordingStatus(
            id: item.recordingId,
            uploadStatus: .done,
            transcription: transcription,
            transcriptionStatus: .done
        )

        // Apply exponential backoff delay if this was a retry
        if item.retryCount > 0 {
            let delay = Self.baseRetryDelay * pow(2.0, Double(item.retryCount - 1))
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    @MainActor
    private func fetchRecording(id: UUID) -> (localAudioPath: String, firestoreId: String?)? {
        let context = modelContainer.mainContext

        let descriptor = FetchDescriptor<RecordingRecord>(
            predicate: #Predicate<RecordingRecord> { $0.id == id }
        )

        guard let record = try? context.fetch(descriptor).first else {
            return nil
        }

        return (localAudioPath: record.localAudioPath, firestoreId: record.firestoreId)
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

        try? context.save()
    }

    @MainActor
    private func removeItem(_ id: UUID) {
        let context = modelContainer.mainContext

        let descriptor = FetchDescriptor<OutboxItem>(
            predicate: #Predicate<OutboxItem> { $0.id == id }
        )

        guard let item = try? context.fetch(descriptor).first else { return }

        context.delete(item)
        try? context.save()
    }

    @MainActor
    private func buildFirestoreRecording(recordingId: UUID, gcsUri: String) -> FirestoreRecording? {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<RecordingRecord>(
            predicate: #Predicate<RecordingRecord> { $0.id == recordingId }
        )
        guard let record = try? context.fetch(descriptor).first else { return nil }

        return FirestoreRecording(
            clientId: record.clientId,
            clientName: record.clientName,
            scene: record.scene,
            recordedAt: record.recordedAt,
            durationSeconds: record.durationSeconds,
            audioStoragePath: gcsUri,
            transcription: nil,
            transcriptionStatus: TranscriptionStatus.processing.rawValue,
            createdBy: "",
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
        try? context.save()
    }

    @MainActor
    private func incrementRetryCount(_ id: UUID) {
        let context = modelContainer.mainContext

        let descriptor = FetchDescriptor<OutboxItem>(
            predicate: #Predicate<OutboxItem> { $0.id == id }
        )

        guard let item = try? context.fetch(descriptor).first else { return }

        item.retryCount += 1
        try? context.save()
    }
}
