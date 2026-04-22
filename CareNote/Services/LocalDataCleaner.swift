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

// MARK: - LocalDataCleanerError

enum LocalDataCleanerError: Error {
    /// 一部のエンティティ削除が失敗した状態（`rollback` 実施済）。
    /// どのモデルで失敗したかは `failures` で確認可能。
    case partialFailure(failures: [(model: String, error: Error)])
}

// MARK: - SwiftDataLocalDataCleaner

/// SwiftData の `ModelContainer` を介してアプリ内の全 `@Model` を削除する実装。
///
/// 対象:
/// - `RecordingRecord`（録音メタ + transcription）
/// - `ClientCache`（利用者キャッシュ）
/// - `OutboxItem`（アップロード pending キュー。残存すると別 tenant へ誤送信の恐れ）
/// - `OutputTemplate`（プリセット含む出力テンプレート）
///
/// `purgeAll()` は atomic: いずれかの entity 削除が失敗した場合は `context.rollback()` を行い、
/// `LocalDataCleanerError.partialFailure` として throw する。セキュリティ目的上、
/// partial success を残すと「OutboxItem だけ残って別 tenant 誤送信」という #91 の最大リスク
/// そのものを実現するため、all-or-nothing を保証する。
final class SwiftDataLocalDataCleaner: LocalDataCleaning {
    private let modelContainer: ModelContainer
    private static let logger = Logger(subsystem: "jp.carenote.app", category: "LocalDataCleaner")

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    @MainActor
    func purgeAll() async throws {
        let context = modelContainer.mainContext

        let operations: [(name: String, delete: () throws -> Void)] = [
            ("RecordingRecord", { try context.delete(model: RecordingRecord.self) }),
            ("ClientCache", { try context.delete(model: ClientCache.self) }),
            ("OutboxItem", { try context.delete(model: OutboxItem.self) }),
            ("OutputTemplate", { try context.delete(model: OutputTemplate.self) }),
        ]

        var failures: [(model: String, error: Error)] = []
        for op in operations {
            do {
                try op.delete()
            } catch {
                failures.append((op.name, error))
            }
        }

        guard failures.isEmpty else {
            context.rollback()
            Self.logger.error(
                "purgeAll partial failure rolled back. failures=\(failures.map { $0.model }.joined(separator: ","), privacy: .public)"
            )
            throw LocalDataCleanerError.partialFailure(failures: failures)
        }

        try context.save()
        Self.logger.info("Local SwiftData purged (RecordingRecord/ClientCache/OutboxItem/OutputTemplate)")
    }
}
