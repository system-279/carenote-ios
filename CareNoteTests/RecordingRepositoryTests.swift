@testable import CareNote
import Foundation
import SwiftData
import Testing

@Suite("RecordingRepository Tests", .serialized)
struct RecordingRepositoryTests {

    /// テスト用 RecordingRecord を作成するヘルパー
    private static func makeRecording(id: UUID = UUID()) -> RecordingRecord {
        RecordingRecord(
            id: id,
            clientId: "client-1",
            clientName: "テスト利用者",
            scene: RecordingScene.visit.rawValue,
            recordedAt: Date(),
            durationSeconds: 30.0,
            localAudioPath: "/tmp/test.m4a"
        )
    }

    // MARK: - resetOutboxItem

    @Test @MainActor
    func resetOutboxItemで既存OutboxItemが削除され新規作成される() throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let repo = RecordingRepository(modelContext: context)

        let recordingId = UUID()
        let recording = Self.makeRecording(id: recordingId)
        context.insert(recording)

        // 既存の OutboxItem（retryCount=2）を作成
        let oldItem = OutboxItem(recordingId: recordingId, retryCount: 2)
        context.insert(oldItem)
        try context.save()

        // resetOutboxItem を実行
        try repo.resetOutboxItem(for: recordingId)

        // OutboxItem が1件のみ存在し、retryCount=0 であること
        let descriptor = FetchDescriptor<OutboxItem>(
            predicate: #Predicate { $0.recordingId == recordingId }
        )
        let items = try context.fetch(descriptor)
        #expect(items.count == 1)
        #expect(items.first?.retryCount == 0)
    }

    @Test @MainActor
    func resetOutboxItemでOutboxItemが存在しなくても新規作成される() throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let repo = RecordingRepository(modelContext: context)

        let recordingId = UUID()
        let recording = Self.makeRecording(id: recordingId)
        context.insert(recording)
        try context.save()

        // OutboxItem なしの状態で resetOutboxItem を実行
        try repo.resetOutboxItem(for: recordingId)

        let descriptor = FetchDescriptor<OutboxItem>(
            predicate: #Predicate { $0.recordingId == recordingId }
        )
        let items = try context.fetch(descriptor)
        #expect(items.count == 1)
        #expect(items.first?.retryCount == 0)
    }

    // MARK: - delete

    @Test @MainActor
    func deleteで関連OutboxItemも削除される() throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let repo = RecordingRepository(modelContext: context)

        let recordingId = UUID()
        let recording = Self.makeRecording(id: recordingId)
        context.insert(recording)

        let outboxItem = OutboxItem(recordingId: recordingId)
        context.insert(outboxItem)
        try context.save()

        try repo.delete(recording)

        // RecordingRecord が削除されていること
        let recDescriptor = FetchDescriptor<RecordingRecord>(
            predicate: #Predicate { $0.id == recordingId }
        )
        #expect(try context.fetch(recDescriptor).isEmpty)

        // OutboxItem も削除されていること
        let outboxDescriptor = FetchDescriptor<OutboxItem>(
            predicate: #Predicate { $0.recordingId == recordingId }
        )
        #expect(try context.fetch(outboxDescriptor).isEmpty)
    }
}
