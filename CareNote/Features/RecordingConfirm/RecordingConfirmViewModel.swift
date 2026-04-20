@preconcurrency import FirebaseAuth
import Foundation
import Observation
import os.log
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
    var templateItems: [TemplateItem] = []
    var selectedItem: TemplateItem?

    private let modelContext: ModelContext
    private let tenantId: String
    private let firestoreService: any TemplateManaging
    private let syncServiceFactory: @Sendable (ModelContainer, String) -> OutboxSyncService

    init(
        audioURL: URL,
        clientId: String,
        clientName: String,
        scene: RecordingScene,
        duration: TimeInterval,
        modelContext: ModelContext,
        tenantId: String,
        firestoreService: any TemplateManaging = FirestoreService(),
        syncServiceFactory: (@Sendable (ModelContainer, String) -> OutboxSyncService)? = nil
    ) {
        self.audioURL = audioURL
        self.clientId = clientId
        self.clientName = clientName
        self.scene = scene
        self.duration = duration
        self.modelContext = modelContext
        self.tenantId = tenantId
        self.firestoreService = firestoreService
        self.syncServiceFactory = syncServiceFactory ?? Self.defaultSyncServiceFactory
    }

    private static let defaultSyncServiceFactory: @Sendable (ModelContainer, String) -> OutboxSyncService = { container, tenantId in
        let wifService = WIFAuthService()
        return OutboxSyncService(
            modelContainer: container,
            storageService: StorageService(accessTokenProvider: wifService),
            firestoreService: FirestoreService(),
            transcriptionService: TranscriptionService(
                projectId: AppConfig.gcpProject,
                accessTokenProvider: wifService
            ),
            tenantId: tenantId,
            currentUidProvider: { Auth.auth().currentUser?.uid }
        )
    }

    private static let logger = Logger(subsystem: "jp.carenote.app", category: "RecordingConfirmVM")

    /// テンプレート一覧を読み込む（プリセット + テナント共有 + 個人）
    func loadTemplates() async {
        Self.logger.info("loadTemplates called")

        // 1. ローカルテンプレート（プリセット + 個人）
        let descriptor = FetchDescriptor<OutputTemplate>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        var fetched: [OutputTemplate]
        do {
            fetched = try modelContext.fetch(descriptor)
        } catch {
            Self.logger.error("SwiftData fetch failed: \(error)")
            fetched = []
        }
        Self.logger.info("Initial fetch: \(fetched.count) templates")

        let hasPresets = fetched.contains { $0.isPreset }
        if !hasPresets {
            Self.logger.warning("No preset templates found, attempting seed fallback")
            PresetTemplates.seedIfNeeded(modelContext: modelContext)
            do {
                fetched = try modelContext.fetch(descriptor)
            } catch {
                Self.logger.error("SwiftData fetch after seed failed: \(error)")
                fetched = []
            }
            Self.logger.info("After seed fallback: \(fetched.count) templates")
        }

        let sorted = fetched.sortedForDisplay()
        let presetItems = sorted.filter(\.isPreset).map { TemplateItem(from: $0) }
        let personalItems = sorted.filter { !$0.isPreset }.map { TemplateItem(from: $0) }

        // 2. テナント共有テンプレート（Firestore）— tenantIdが空の場合はスキップ
        var tenantItems: [TemplateItem] = []
        if !tenantId.isEmpty {
            do {
                let tenantTemplates = try await firestoreService.fetchTemplates(tenantId: tenantId)
                tenantItems = tenantTemplates.map { TemplateItem(from: $0) }
            } catch {
                Self.logger.error("Failed to load tenant templates: \(error.localizedDescription)")
                errorMessage = "共有テンプレートの読み込みに失敗しました（プリセットは利用可能です）"
            }
        }

        // 3. 統合: プリセット → テナント共有 → 個人
        templateItems = presetItems + tenantItems + personalItems

        if selectedItem == nil {
            selectedItem = templateItems.first
        }

        Self.logger.info("loadTemplates done: \(self.templateItems.count) items, selected=\(self.selectedItem?.name ?? "nil")")
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
                outputType: (selectedItem?.outputType ?? .transcription).rawValue,
                templateId: selectedItem?.localTemplateId,
                templateNameSnapshot: selectedItem?.name,
                templatePromptSnapshot: selectedItem?.prompt
            )
            modelContext.insert(recording)
            try modelContext.save()

            // 2. OutboxItem を作成してアップロードキューに追加
            let outboxItem = OutboxItem(recordingId: recording.id)
            modelContext.insert(outboxItem)
            try modelContext.save()

            // 3. OutboxSyncService を生成して即時処理
            let syncService = syncServiceFactory(modelContext.container, tenantId)
            try await syncService.processQueueImmediately()
        } catch {
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
                case .userNotAuthenticated:
                    detail = "ログインが必要です"
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
