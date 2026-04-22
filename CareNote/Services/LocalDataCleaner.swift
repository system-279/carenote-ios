import Foundation
import os.log
import SwiftData

// MARK: - LocalDataCleaning

/// アカウント削除後にローカル端末上のユーザーデータを消去するための抽象。
///
/// 別アカウントでログインした際の情報漏洩（前ユーザーの録音メタが一瞬見える等）と、
/// Outbox に残った pending item が別ユーザー tenant へ誤送信されるセキュリティリスクを防ぐ。
protocol LocalDataCleaning: Sendable {
    func purgeAll() async throws
}

// MARK: - SwiftDataLocalDataCleaner

/// SwiftData の `ModelContainer` を介してアプリ内の全 `@Model` を削除する実装。
///
/// 対象:
/// - `RecordingRecord`（録音メタ + transcription）
/// - `ClientCache`（利用者キャッシュ）
/// - `OutboxItem`（アップロード pending キュー）
/// - `OutputTemplate`（プリセット含む出力テンプレート）
final class SwiftDataLocalDataCleaner: LocalDataCleaning {
    private let modelContainer: ModelContainer
    private static let logger = Logger(subsystem: "jp.carenote.app", category: "LocalDataCleaner")

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    @MainActor
    func purgeAll() async throws {
        let context = modelContainer.mainContext

        try context.delete(model: RecordingRecord.self)
        try context.delete(model: ClientCache.self)
        try context.delete(model: OutboxItem.self)
        try context.delete(model: OutputTemplate.self)
        try context.save()

        Self.logger.info("Local SwiftData purged (RecordingRecord/ClientCache/OutboxItem/OutputTemplate)")
    }
}
