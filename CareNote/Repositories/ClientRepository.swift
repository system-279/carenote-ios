import Foundation
import Observation
import SwiftData

// MARK: - ClientRepository

@Observable
final class ClientRepository: @unchecked Sendable {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// 全利用者キャッシュをふりがな順で取得する
    func fetchAll() throws -> [ClientCache] {
        let descriptor = FetchDescriptor<ClientCache>(
            sortBy: [SortDescriptor(\.furigana)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// 利用者キャッシュを upsert（既存なら更新、なければ挿入）する
    func upsert(_ client: ClientCache) throws {
        let clientId = client.id
        let descriptor = FetchDescriptor<ClientCache>(
            predicate: #Predicate { $0.id == clientId }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.name = client.name
            existing.furigana = client.furigana
            existing.cachedAt = Date()
        } else {
            modelContext.insert(client)
        }
        try modelContext.save()
    }

    /// 利用者キャッシュを ID で削除する
    func delete(id: String) throws {
        let descriptor = FetchDescriptor<ClientCache>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            try modelContext.save()
        }
    }

    /// 全利用者キャッシュを入れ替える（Firestore からの全量同期用）
    func replaceAll(with clients: [ClientCache]) throws {
        try modelContext.delete(model: ClientCache.self)
        for client in clients {
            modelContext.insert(client)
        }
        try modelContext.save()
    }
}
