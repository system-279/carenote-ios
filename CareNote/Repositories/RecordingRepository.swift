import Foundation
import Observation
import SwiftData

// MARK: - RecordingRepository

@Observable
final class RecordingRepository: @unchecked Sendable {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// 全録音レコードを録音日時の降順で取得する
    func fetchAll() throws -> [RecordingRecord] {
        let descriptor = FetchDescriptor<RecordingRecord>(
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// 新しい録音レコードを保存する
    func save(_ recording: RecordingRecord) throws {
        modelContext.insert(recording)
        try modelContext.save()
    }

    /// 既存の録音レコードの変更を永続化する
    func update(_ recording: RecordingRecord) throws {
        try modelContext.save()
    }

    /// ID で録音レコードを検索する
    func findById(_ id: UUID) throws -> RecordingRecord? {
        let descriptor = FetchDescriptor<RecordingRecord>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    /// 録音レコードと関連する OutboxItem を削除する
    func delete(_ recording: RecordingRecord) throws {
        let recordingId = recording.id

        // 関連する OutboxItem を先に削除
        let outboxDescriptor = FetchDescriptor<OutboxItem>(
            predicate: #Predicate { $0.recordingId == recordingId }
        )
        if let outboxItems = try? modelContext.fetch(outboxDescriptor) {
            for item in outboxItems {
                modelContext.delete(item)
            }
        }

        // ID で再取得してから削除（コンテキスト不整合を防ぐ）
        let descriptor = FetchDescriptor<RecordingRecord>(
            predicate: #Predicate { $0.id == recordingId }
        )
        if let record = try modelContext.fetch(descriptor).first {
            modelContext.delete(record)
        }

        try modelContext.save()
    }

    /// 現在のコンテキスト変更を保存する
    func save() throws {
        try modelContext.save()
    }

    /// 指定録音の OutboxItem を削除し、新しいものを作成する（リトライリセット）
    func resetOutboxItem(for recordingId: UUID) throws {
        let outboxDescriptor = FetchDescriptor<OutboxItem>(
            predicate: #Predicate { $0.recordingId == recordingId }
        )
        if let items = try? modelContext.fetch(outboxDescriptor) {
            for item in items {
                modelContext.delete(item)
            }
        }

        let newItem = OutboxItem(recordingId: recordingId)
        modelContext.insert(newItem)
        try modelContext.save()
    }

    /// アップロード待ちの録音レコードを取得する
    func pendingUploads() throws -> [RecordingRecord] {
        let pending = UploadStatus.pending.rawValue
        let descriptor = FetchDescriptor<RecordingRecord>(
            predicate: #Predicate { $0.uploadStatus == pending }
        )
        return try modelContext.fetch(descriptor)
    }
}
