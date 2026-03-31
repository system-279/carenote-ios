@testable import CareNote
import Foundation
import SwiftData
import Testing

@Suite("RecordingListViewModel Tests")
struct RecordingListViewModelTests {

    private static func makeContainer() throws -> ModelContainer {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftdata-test-\(UUID().uuidString).sqlite")
        let config = ModelConfiguration(url: url)
        return try ModelContainer(
            for: RecordingRecord.self, OutboxItem.self, ClientCache.self,
            configurations: config
        )
    }

    private static func makeErrorRecording(id: UUID = UUID(), context: ModelContext) -> RecordingRecord {
        let recording = RecordingRecord(
            id: id,
            clientId: "client-1",
            clientName: "テスト利用者",
            scene: RecordingScene.visit.rawValue,
            recordedAt: Date(),
            durationSeconds: 30.0,
            localAudioPath: "/tmp/test.m4a",
            uploadStatus: UploadStatus.error.rawValue,
            transcription: "失敗したテキスト",
            transcriptionStatus: TranscriptionStatus.error.rawValue
        )
        context.insert(recording)
        return recording
    }

    @Test @MainActor
    func retryRecordingでステータスがpendingにリセットされる() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let repo = RecordingRepository(modelContext: context)
        let vm = RecordingListViewModel(recordingRepository: repo)

        let recordingId = UUID()
        let recording = Self.makeErrorRecording(id: recordingId, context: context)

        // エラー状態の OutboxItem を作成（retryCount=3）
        let oldItem = OutboxItem(recordingId: recordingId, retryCount: 3)
        context.insert(oldItem)
        try context.save()

        #expect(recording.uploadStatus == UploadStatus.error.rawValue)
        #expect(recording.transcriptionStatus == TranscriptionStatus.error.rawValue)

        // retryRecording を実行
        try await vm.retryRecording(recording)

        // ステータスが pending にリセットされていること
        #expect(recording.uploadStatus == UploadStatus.pending.rawValue)
        #expect(recording.transcriptionStatus == TranscriptionStatus.pending.rawValue)
        #expect(recording.transcription == nil)

        // OutboxItem が retryCount=0 で再作成されていること
        let descriptor = FetchDescriptor<OutboxItem>(
            predicate: #Predicate { $0.recordingId == recordingId }
        )
        let items = try context.fetch(descriptor)
        #expect(items.count == 1)
        #expect(items.first?.retryCount == 0)
    }

    @Test @MainActor
    func saveTranscriptionでテキストがSwiftDataに保存される() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let repo = RecordingRepository(modelContext: context)
        let vm = RecordingListViewModel(recordingRepository: repo)

        let recording = RecordingRecord(
            id: UUID(),
            clientId: "client-1",
            clientName: "テスト利用者",
            scene: RecordingScene.visit.rawValue,
            localAudioPath: "/tmp/test.m4a",
            transcription: "元のテキスト",
            transcriptionStatus: TranscriptionStatus.done.rawValue
        )
        context.insert(recording)
        try context.save()

        try await vm.saveTranscription(recording, text: "修正後のテキスト")

        #expect(recording.transcription == "修正後のテキスト")

        // SwiftData に永続化されていることを確認
        let fetched = try repo.findById(recording.id)
        #expect(fetched?.transcription == "修正後のテキスト")
    }

    @Test @MainActor
    func deleteRecordingでリストから除外される() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let repo = RecordingRepository(modelContext: context)
        let vm = RecordingListViewModel(recordingRepository: repo)

        let recording = Self.makeErrorRecording(context: context)
        try context.save()

        // loadRecordings でリストに読み込む
        await vm.loadRecordings()
        #expect(vm.recordings.count == 1)

        // 削除
        try await vm.deleteRecording(recording)
        #expect(vm.recordings.isEmpty)
    }
}
