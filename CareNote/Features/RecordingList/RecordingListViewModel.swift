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
    case remoteServiceUnavailable

    /// Issue #193: Firestore security rules で拒否された（例: `createdBy=""` legacy record を
    /// 管理者以外が削除しようとした）。local も削除しない（Firestore を primary truth として整合を維持）。
    case permissionDenied

    /// Issue #193: transient な Firestore 障害 (deadlineExceeded / resourceExhausted / unavailable)。
    /// `recordingId` のみ保持する理由: `RecordingRecord` は SwiftData `@Model` で non-Sendable、
    /// `any Error` も non-Sendable のため enum の Sendable 準拠を崩す。UUID + FirestoreError なら安全。
    /// View 側は `viewModel.recordings.first(where: { $0.id == recordingId })` で対象を引き直す。
    case retryable(recordingId: UUID, underlying: FirestoreError)

    var errorDescription: String? {
        switch self {
        case .remoteServiceUnavailable:
            return "削除できませんでした。アプリを再起動するか、再度サインインしてください。"
        case .permissionDenied:
            return "この録音は管理者権限が必要です。管理者に削除を依頼してください。"
        case .retryable:
            return "通信が不安定なため削除できませんでした。時間をおいて再試行してください。"
        }
    }
}

// MARK: - RecordingListViewModel

@Observable @MainActor
final class RecordingListViewModel {
    var recordings: [RecordingRecord] = []
    var isLoading: Bool = false
    var errorMessage: String?
    /// Issue #193: 削除専用のエラー state。`.retryable` の場合に View が「再試行」ボタンを出す。
    /// `errorMessage` とは別 state にして、polling 等の generic エラーと混同しないようにする。
    var deleteError: RecordingDeleteError?

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
            } catch let firestoreError as FirestoreError {
                try Self.resolveDeleteError(
                    firestoreError,
                    recordingId: recording.id,
                    firestoreId: firestoreId
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
                    do {
                        try recordingRepository.save()
                        // 過去の polling save 失敗警告をクリア（成功 iteration で回復と判定）。
                        // 他のエラー源との混同を防ぐためリテラル一致でのみクリアする。
                        if errorMessage == Self.pollingSaveFailureMessage {
                            errorMessage = nil
                        }
                    } catch {
                        // SwiftData save 失敗は DB 整合性破壊の可能性 → permanent 扱いで UI surface
                        Self.logger.error(
                            "Polling save failed for recording \(recording.id, privacy: .public): \(error.localizedDescription, privacy: .public)"
                        )
                        errorMessage = Self.pollingSaveFailureMessage
                    }
                }
            } catch {
                // Issue #194: silent catch 廃止。transient/permanent で分類してログする。
                logPollingFetchError(recordingId: firestoreId, error: error)
            }
        }
    }

    /// polling save 失敗時に UI へ出す errorMessage リテラル（成功時 clear のため定数化）。
    private static let pollingSaveFailureMessage = "録音の更新を保存できませんでした"

    /// Issue #193: Firestore delete 失敗を分類し、UI 層へ見せる形 (RecordingDeleteError) に変換する。
    ///
    /// - `.notFound`: 他端末で既に削除済 → `return` で idempotent success。caller は local 削除を続行。
    /// - `.permissionDenied`: rules で拒否 → `RecordingDeleteError.permissionDenied` を throw、local は消さない。
    /// - `.operationFailed` かつ `isTransient`: 再試行可能 → `.retryable` を throw。
    /// - その他 (非 transient `.operationFailed` / `.encodingFailed` / `.decodingFailed` / `.documentNotFound`):
    ///   原因特定が難しいため、原 `FirestoreError` をそのまま re-throw して上位に委ねる。
    ///
    /// `static` かつ純粋関数として公開しているのは、concrete `FirestoreService` actor を
    /// stub できない現状（Issue #182 follow-up）でも分類ロジックだけは単体テストできるようにするため。
    static func resolveDeleteError(
        _ firestoreError: FirestoreError,
        recordingId: UUID,
        firestoreId: String
    ) throws {
        switch firestoreError {
        case .notFound:
            Self.logger.info(
                "Recording already removed on Firestore, proceeding with local cleanup: \(firestoreId, privacy: .public)"
            )
            return
        case .permissionDenied:
            Self.logger.warning(
                "Firestore deleteRecording denied by rules for \(firestoreId, privacy: .public)"
            )
            throw RecordingDeleteError.permissionDenied
        case .operationFailed where firestoreError.isTransient:
            Self.logger.info(
                "Firestore deleteRecording transient failure for \(firestoreId, privacy: .public): \(firestoreError.localizedDescription, privacy: .public)"
            )
            throw RecordingDeleteError.retryable(recordingId: recordingId, underlying: firestoreError)
        case .operationFailed, .encodingFailed, .decodingFailed, .documentNotFound:
            Self.logger.error(
                "Firestore deleteRecording failed for \(firestoreId, privacy: .public): \(firestoreError.localizedDescription, privacy: .public)"
            )
            throw firestoreError
        }
    }

    /// polling 中の Firestore fetch エラーを transient/permanent に分類してログする。
    ///
    /// - transient: 次回 polling (5s 間隔) で自動リトライされるため info レベル。
    /// - permanent: DI 設定 / 権限 / スキーマ drift 等、開発者の介入が必要なため error レベル。
    ///
    /// 分類ロジックは `FirestoreError.isTransient` を使用（Firestore SDK 知識を service 層に集約）。
    /// 基準はグローバル `~/.claude/rules/error-handling.md` §3 の transient/permanent プロトコル準拠。
    private func logPollingFetchError(recordingId: String, error: Error) {
        let isTransient = (error as? FirestoreError)?.isTransient ?? false
        if isTransient {
            Self.logger.info(
                "Polling fetchRecording transient error for \(recordingId, privacy: .public), will retry: \(error.localizedDescription, privacy: .public)"
            )
        } else {
            Self.logger.error(
                "Polling fetchRecording permanent error for \(recordingId, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
