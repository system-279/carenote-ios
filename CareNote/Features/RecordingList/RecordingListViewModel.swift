import Foundation
import Observation
import os.log
import SwiftData

// MARK: - RecordingListViewModel

@Observable @MainActor
final class RecordingListViewModel {
    var recordings: [RecordingRecord] = []
    var isLoading: Bool = false
    var errorMessage: String?

    private let recordingRepository: RecordingRepository
    private let firestoreService: FirestoreService?
    private let tenantId: String?

    private static let pollingInterval: TimeInterval = 5.0
    /// テナント切替検知に使う UserDefaults キー（テナント境界を越えたキャッシュ混在を防ぐ）
    private static let lastSyncedTenantKey = "recordingList.lastSyncedTenantId"
    private static let logger = Logger(subsystem: "jp.carenote.app", category: "RecordingListVM")

    private var pollingTask: Task<Void, Never>?

    init(
        recordingRepository: RecordingRepository,
        firestoreService: FirestoreService? = nil,
        tenantId: String? = nil
    ) {
        self.recordingRepository = recordingRepository
        self.firestoreService = firestoreService
        self.tenantId = tenantId
    }

    /// 録音一覧を読み込む
    /// - 前回同期時とテナントが違えば、ローカルキャッシュをクリアしてから再取得（テナント越境防止）
    /// - まず SwiftData を即時表示（オフライン時のフォールバック）
    /// - 次に Firestore から同期し SwiftData へ upsert
    func loadRecordings() async {
        isLoading = true
        defer { isLoading = false }

        // 1. テナント切替を検知してローカルキャッシュをクリア
        handleTenantSwitchIfNeeded()

        // 2. SwiftData を即座に表示（オフライン時のフォールバック）
        do {
            recordings = try recordingRepository.fetchAll()
        } catch {
            recordings = []
            errorMessage = "録音の読み込みに失敗しました"
            return
        }

        // 3. Firestore から同期し upsert（失敗時は SwiftData のまま継続）
        guard let firestoreService,
              let tenantId,
              !tenantId.isEmpty else { return }
        do {
            let remote = try await firestoreService.fetchRecordings(tenantId: tenantId)
            try recordingRepository.upsertFromFirestore(remote)
            recordings = try recordingRepository.fetchAll()
        } catch {
            Self.logger.info("Firestore sync failed (using local cache): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleTenantSwitchIfNeeded() {
        guard let currentTenant = tenantId, !currentTenant.isEmpty else { return }
        let defaults = UserDefaults.standard
        let lastSynced = defaults.string(forKey: Self.lastSyncedTenantKey)
        guard lastSynced != currentTenant else { return }

        // 未アップロードの録音を検知して警告（テナント切替時の意図しないデータ喪失を可視化）
        if let pending = try? recordingRepository.pendingUploads(), !pending.isEmpty {
            Self.logger.error("Tenant switch (\(lastSynced ?? "nil", privacy: .public) -> \(currentTenant, privacy: .public)) will discard \(pending.count) pending uploads")
        }

        do {
            try recordingRepository.deleteAll()
            Self.logger.info("Cleared local recordings for tenant switch: \(lastSynced ?? "nil", privacy: .public) -> \(currentTenant, privacy: .public)")
            // 削除成功時のみ UserDefaults を更新（失敗時は次回再試行して越境を防ぐ）
            defaults.set(currentTenant, forKey: Self.lastSyncedTenantKey)
        } catch {
            Self.logger.error("Failed to clear local recordings on tenant switch: \(error.localizedDescription, privacy: .public)")
            // UserDefaults を更新しない → 次回 loadRecordings で再試行される
        }
    }

    /// 録音の文字起こしを再試行する
    func retryRecording(_ recording: RecordingRecord) async throws {
        try recordingRepository.resetOutboxItem(for: recording.id)

        recording.uploadStatus = UploadStatus.pending.rawValue
        recording.transcriptionStatus = TranscriptionStatus.pending.rawValue
        recording.transcription = nil
        try recordingRepository.save()
    }

    /// 録音を削除する
    func deleteRecording(_ recording: RecordingRecord) async throws {
        let audioPath = recording.localAudioPath
        if FileManager.default.fileExists(atPath: audioPath) {
            try? FileManager.default.removeItem(atPath: audioPath)
        }

        try recordingRepository.delete(recording)
        recordings.removeAll { $0.id == recording.id }
    }

    /// 文字起こしテキストを編集・保存する（SwiftData + Firestore）
    func saveTranscription(_ recording: RecordingRecord, text: String) async throws {
        recording.transcription = text
        try recordingRepository.save()

        // Firestore にも同期
        if let firestoreService, let tenantId, let firestoreId = recording.firestoreId {
            try await firestoreService.updateTranscription(
                tenantId: tenantId,
                recordingId: firestoreId,
                transcription: text,
                status: .done
            )
        }
    }

    // MARK: - Polling

    /// processing 状態のアイテムがある間、Firestore をポーリングして更新する
    func startPolling() {
        stopPolling()
        pollingTask = Task {
            while !Task.isCancelled {
                await pollProcessingRecordings()

                if !hasProcessingRecordings() {
                    return
                }

                try? await Task.sleep(nanoseconds: UInt64(Self.pollingInterval * 1_000_000_000))
            }
        }
    }

    /// ポーリングを停止する
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func hasProcessingRecordings() -> Bool {
        let processingStatuses = [
            TranscriptionStatus.pending.rawValue,
            TranscriptionStatus.processing.rawValue,
        ]
        return recordings.contains { processingStatuses.contains($0.transcriptionStatus) && $0.firestoreId != nil }
    }

    private func pollProcessingRecordings() async {
        guard let firestoreService, let tenantId else { return }

        let processingStatuses = [
            TranscriptionStatus.pending.rawValue,
            TranscriptionStatus.processing.rawValue,
        ]
        let processingRecordings = recordings.filter {
            processingStatuses.contains($0.transcriptionStatus) && $0.firestoreId != nil
        }

        for recording in processingRecordings {
            guard let firestoreId = recording.firestoreId else { continue }

            do {
                guard let remote = try await firestoreService.fetchRecording(
                    tenantId: tenantId,
                    recordingId: firestoreId
                ) else { continue }

                if remote.transcriptionStatus != recording.transcriptionStatus {
                    recording.transcriptionStatus = remote.transcriptionStatus
                    recording.transcription = remote.transcription
                    try? recordingRepository.save()
                }
            } catch {
                // ポーリングエラーは静かに無視（次回リトライ）
            }
        }
    }
}
