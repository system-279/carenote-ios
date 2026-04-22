import Foundation
import SwiftData

// MARK: - Schema Drift Guard (Issue #165)
//
// When adding a new `@Model` type in this file, update every site that
// enumerates the SwiftData schema. Missing one will silently regress:
//  - Issue #91 (LocalDataCleaner) → orphan data after account delete
//  - Issue #141 (SIGTRAP) → duplicate type registration crashes the process
//
// Sites to update:
//  1. CareNoteTests/TestHelpers/SwiftDataTestHelper.swift
//     - `SharedTestModelContainer.shared` `ModelContainer(for: ...)` init list
//     - `cleanup()` `context.delete(model:)` chain
//  2. CareNote/Services/LocalDataCleaner.swift
//     - `purgeAll()` operations array
//  3. Every production `Schema([...])` enumeration:
//     - CareNote/App/CareNoteApp.swift
//     - CareNote/Features/Recording/RecordingView.swift
//     - CareNote/Features/RecordingConfirm/RecordingConfirmView.swift
//     - CareNote/Features/Settings/TemplateListView.swift
//     - CareNote/Features/Settings/SettingsView.swift
//
// CI guard: `scripts/lint-model-container.sh` detects new test-side drift
// by rejecting any `ModelContainer(for:` outside its ALLOWED_TEST_FILES list
// (currently the helper above + OutboxSyncServiceTests.swift, the latter
// temporarily allowed while Issue #164 tracks a shared-container regression).
// Production-side `Schema([...])` drift is not CI-gated; keep this list
// current as the authoritative checklist.

// MARK: - RecordingRecord

@Model
final class RecordingRecord {
    @Attribute(.unique)
    var id: UUID

    var clientId: String
    var clientName: String
    var scene: String
    var recordedAt: Date
    var durationSeconds: Double
    var localAudioPath: String
    var firestoreId: String?
    var uploadStatus: String
    var transcription: String?
    var transcriptionStatus: String
    var outputType: String?
    var templateId: UUID?
    var templateNameSnapshot: String?
    var templatePromptSnapshot: String?

    init(
        id: UUID = UUID(),
        clientId: String,
        clientName: String,
        scene: String,
        recordedAt: Date = Date(),
        durationSeconds: Double = 0,
        localAudioPath: String,
        firestoreId: String? = nil,
        uploadStatus: String = UploadStatus.pending.rawValue,
        transcription: String? = nil,
        transcriptionStatus: String = TranscriptionStatus.pending.rawValue,
        outputType: String? = OutputType.transcription.rawValue,
        templateId: UUID? = nil,
        templateNameSnapshot: String? = nil,
        templatePromptSnapshot: String? = nil
    ) {
        self.id = id
        self.clientId = clientId
        self.clientName = clientName
        self.scene = scene
        self.recordedAt = recordedAt
        self.durationSeconds = durationSeconds
        self.localAudioPath = localAudioPath
        self.firestoreId = firestoreId
        self.uploadStatus = uploadStatus
        self.transcription = transcription
        self.transcriptionStatus = transcriptionStatus
        self.outputType = outputType
        self.templateId = templateId
        self.templateNameSnapshot = templateNameSnapshot
        self.templatePromptSnapshot = templatePromptSnapshot
    }
}

// MARK: - ClientCache

@Model
final class ClientCache {
    @Attribute(.unique)
    var id: String

    var name: String
    var furigana: String
    var cachedAt: Date

    init(
        id: String,
        name: String,
        furigana: String,
        cachedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.furigana = furigana
        self.cachedAt = cachedAt
    }
}

extension ClientCache: Hashable {
    static func == (lhs: ClientCache, rhs: ClientCache) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - OutputTemplate

@Model
final class OutputTemplate {
    @Attribute(.unique)
    var id: UUID

    var name: String
    var prompt: String
    var outputType: String
    var isPreset: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        prompt: String,
        outputType: String = OutputType.transcription.rawValue,
        isPreset: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.outputType = outputType
        self.isPreset = isPreset
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Array where Element == OutputTemplate {
    /// プリセットを先頭、カスタムを後方に、各グループ内は作成日昇順でソート
    func sortedForDisplay() -> [OutputTemplate] {
        sorted { a, b in
            if a.isPreset != b.isPreset { return a.isPreset }
            return a.createdAt < b.createdAt
        }
    }
}

// MARK: - OutboxItem

@Model
final class OutboxItem {
    @Attribute(.unique)
    var id: UUID

    var recordingId: UUID
    var createdAt: Date
    var retryCount: Int

    init(
        id: UUID = UUID(),
        recordingId: UUID,
        createdAt: Date = Date(),
        retryCount: Int = 0
    ) {
        self.id = id
        self.recordingId = recordingId
        self.createdAt = createdAt
        self.retryCount = retryCount
    }
}
