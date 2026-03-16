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
    var templates: [OutputTemplate] = []
    var selectedTemplate: OutputTemplate?

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

    /// テンプレート一覧を読み込む
    func loadTemplates() {
        let descriptor = FetchDescriptor<OutputTemplate>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        // プリセットを先に表示
        templates = fetched.sorted { a, b in
            if a.isPreset != b.isPreset { return a.isPreset }
            return a.createdAt < b.createdAt
        }

        // デフォルトで最初のプリセット（文字起こし）を選択
        if selectedTemplate == nil {
            selectedTemplate = templates.first
        }
    }

    /// 録音を保存し文字起こしを開始する
    func saveAndTranscribe() async throws {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            // 1. RecordingRecord を SwiftData に保存（テンプレート snapshot 付き）
            let recording = RecordingRecord(
                clientId: clientId,
                clientName: clientName,
                scene: scene.rawValue,
                durationSeconds: duration,
                localAudioPath: audioURL.path,
                outputType: selectedTemplate?.outputType ?? OutputType.transcription.rawValue,
                templateId: selectedTemplate?.id,
                templateNameSnapshot: selectedTemplate?.name,
                templatePromptSnapshot: selectedTemplate?.prompt
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
            defer { Task { await syncService.stopMonitoring() } }
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
        formatMMSS(duration)
    }

}
