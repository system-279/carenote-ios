import Foundation
import Observation
import os.log
import SwiftData

// MARK: - RecordingDeleteError

enum RecordingDeleteError: LocalizedError, Sendable {
    /// Issue #182 AC5: 同期済み録音で FirestoreService / tenantId が欠落しているため
    /// local-only 削除を拒否した（再読込での復活を防ぐため）。
    ///
    /// 注意: case 名は "Unavailable" だが、実態は DI wiring bug または未サインイン状態。
    /// ネットワーク起因ではないため、ユーザーへは「再サインイン / アプリ再起動」を案内する。
    /// 将来 Firestore 側の transient 失敗を別 case として分けるなら、本 case はそのまま
    /// DI 欠落専用として残す（Issue #182 follow-up）。
    case remoteServiceUnavailable

    var errorDescription: String? {
        switch self {
        case .remoteServiceUnavailable:
            return "削除できませんでした。アプリを再起動するか、再度サインインしてください。"
        }
    }
}

// MARK: - RecordingListViewModel

@Observable @MainActor
final class RecordingListViewModel {
    var recordings: [RecordingRecord] = []
    var isLoading: Bool = false
    var errorMessage: String?

    private let recordingRepository: RecordingRepository
    // TODO(Issue #182 follow-up): migrate to `any RecordingStoring` for testability.
    //   Currently the concrete `FirestoreService` actor blocks stubbing Firestore calls
    //   in ViewModel tests. Requires adding fetchRecordings/fetchRecording to the
    //   protocol too (both used from loadRecordings and retry path).
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

    /// 録音を削除する（Issue #182）
    ///
    /// 同期済み録音（`firestoreId` あり）は Firestore delete 成功後に local を削除する。
    /// Firestore 側を先に消さないと、local-only 削除は再読込で復活する。
    /// Cloud Storage の音声ファイル削除は server-side で行うため本 method のスコープ外
    /// （Issue #182 follow-up）。
    func deleteRecording(_ recording: RecordingRecord) async throws {
        // 1. 同期済み録音なら Firestore delete を先に実行
        if let firestoreId = recording.firestoreId {
            guard let firestoreService, let tenantId, !tenantId.isEmpty else {
                // AC5: firestoreId あり + DI 欠落は local-only 削除禁止。
                // DI wiring bug / 未サインインの検知性を上げるため error レベルで記録。
                Self.logger.error(
                    """
                    deleteRecording blocked by AC5 guard: firestoreId=\(firestoreId, privacy: .public) \
                    firestoreService=\(self.firestoreService == nil ? "nil" : "set", privacy: .public) \
                    tenantId=\(self.tenantId ?? "nil", privacy: .public)
                    """
                )
                throw RecordingDeleteError.remoteServiceUnavailable
            }
            do {
                try await firestoreService.deleteRecording(
                    tenantId: tenantId,
                    recordingId: firestoreId
                )
            } catch {
                Self.logger.error(
                    "Firestore deleteRecording failed for \(firestoreId, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                throw error
            }
        }

        // 2. SwiftData + 関連 OutboxItem を削除（Repository cascade）
        try recordingRepository.delete(recording)

        // 3. local audio file を best-effort で削除（Firestore 成功後なので致命扱いしない）。
        //    try? で完全 swallow はせず、orphan ファイル調査のため warning ログは必ず残す。
        let audioPath = recording.localAudioPath
        if FileManager.default.fileExists(atPath: audioPath) {
            do {
                try FileManager.default.removeItem(atPath: audioPath)
            } catch {
                Self.logger.warning(
                    "Best-effort audio file removal failed for recording \(recording.id, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        // 4. 画面上のリストから除去
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
