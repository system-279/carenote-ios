import Foundation
import Observation
import SwiftData

// MARK: - RecordingConfirmViewModel

@Observable
@MainActor
final class RecordingConfirmViewModel {
    let audioURL: URL
    let clientId: String
    let clientName: String
    let scene: RecordingScene
    let duration: TimeInterval

    var isSaving: Bool = false
    var errorMessage: String?

    private let modelContext: ModelContext
    private let tenantId: String

    init(
        audioURL: URL,
        clientId: String,
        clientName: String,
        scene: RecordingScene,
        duration: TimeInterval,
        modelContext: ModelContext,
        tenantId: String
    ) {
        self.audioURL = audioURL
        self.clientId = clientId
        self.clientName = clientName
        self.scene = scene
        self.duration = duration
        self.modelContext = modelContext
        self.tenantId = tenantId
    }

    /// 録音を保存し文字起こしを開始する
    func saveAndTranscribe() async throws {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            // 1. RecordingRecord を SwiftData に保存
            let recording = RecordingRecord(
                clientId: clientId,
                clientName: clientName,
                scene: scene.rawValue,
                durationSeconds: duration,
                localAudioPath: audioURL.path
            )
            modelContext.insert(recording)
            try modelContext.save()

            // 2. OutboxItem を作成してアップロードキューに追加
            let outboxItem = OutboxItem(recordingId: recording.id)
            modelContext.insert(outboxItem)
            try modelContext.save()

            // 3. OutboxSyncService を生成して即時処理
            let wifService = WIFAuthService()
            let syncService = OutboxSyncService(
                modelContainer: modelContext.container,
                storageService: StorageService(accessTokenProvider: wifService),
                firestoreService: FirestoreService(),
                transcriptionService: TranscriptionService(
                    projectId: AppConfig.gcpProject,
                    accessTokenProvider: wifService
                ),
                tenantId: tenantId
            )

            await syncService.startMonitoring()
            try await syncService.processQueueImmediately()
        } catch {
            // エラーチェーンを展開して詳細表示
            let detail: String
            if let syncError = error as? OutboxSyncError {
                switch syncError {
                case .uploadFailed(let inner):
                    detail = "Upload: \(inner)"
                case .transcriptionFailed(let inner):
                    detail = "Transcription: \(inner)"
                case .recordingNotFound(let id):
                    detail = "Recording not found: \(id)"
                case .maxRetriesExceeded(let id):
                    detail = "Max retries: \(id)"
                case .modelContainerNotAvailable:
                    detail = "ModelContainer unavailable"
                }
            } else {
                detail = "\(error)"
            }
            errorMessage = "保存に失敗しました: \(detail)"
            throw error
        }
    }

    /// 録音時間を MM:SS 形式でフォーマットする
    var formattedDuration: String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

}
