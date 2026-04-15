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

    /// 全録音レコードと関連 OutboxItem を削除する（テナント切替時のキャッシュクリア用）
    func deleteAll() throws {
        let records = try fetchAll()
        for record in records {
            let recordingId = record.id
            let outboxDescriptor = FetchDescriptor<OutboxItem>(
                predicate: #Predicate { $0.recordingId == recordingId }
            )
            if let items = try? modelContext.fetch(outboxDescriptor) {
                for item in items { modelContext.delete(item) }
            }
            modelContext.delete(record)
        }
        try modelContext.save()
    }

    /// Firestore から取得した録音リストを SwiftData に upsert する
    /// - firestoreId で既存レコードを検索し、存在すれば更新、なければ新規作成
    /// - localAudioPath は remote-only レコードでは空文字（再生は不可、メタデータのみ表示）
    func upsertFromFirestore(_ remoteRecordings: [FirestoreRecording]) throws {
        for remote in remoteRecordings {
            guard let remoteId = remote.id else { continue }

            let descriptor = FetchDescriptor<RecordingRecord>(
                predicate: #Predicate { $0.firestoreId == remoteId }
            )
            if let existing = try modelContext.fetch(descriptor).first {
                existing.clientId = remote.clientId
                existing.clientName = remote.clientName
                existing.scene = remote.scene
                existing.recordedAt = remote.recordedAt
                existing.durationSeconds = remote.durationSeconds
                existing.transcription = remote.transcription
                existing.transcriptionStatus = remote.transcriptionStatus
                existing.uploadStatus = UploadStatus.done.rawValue
            } else {
                let new = RecordingRecord(
                    id: UUID(),
                    clientId: remote.clientId,
                    clientName: remote.clientName,
                    scene: remote.scene,
                    recordedAt: remote.recordedAt,
                    durationSeconds: remote.durationSeconds,
                    localAudioPath: "",
                    firestoreId: remoteId,
                    uploadStatus: UploadStatus.done.rawValue,
                    transcription: remote.transcription,
                    transcriptionStatus: remote.transcriptionStatus
                )
                modelContext.insert(new)
            }
        }
        try modelContext.save()
    }
}
