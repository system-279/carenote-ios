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

    /// アップロード待ちの録音レコードを取得する
    func pendingUploads() throws -> [RecordingRecord] {
        let pending = UploadStatus.pending.rawValue
        let descriptor = FetchDescriptor<RecordingRecord>(
            predicate: #Predicate { $0.uploadStatus == pending }
        )
        return try modelContext.fetch(descriptor)
    }
}
