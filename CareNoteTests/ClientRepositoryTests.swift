@testable import CareNote
import Foundation
import SwiftData
import Testing

// MARK: - ClientRepository Tests

@Suite("ClientRepository Tests", .serialized)
struct ClientRepositoryTests {

    @MainActor
    private func makeRepository() throws -> (ClientRepository, ModelContainer) {
        let container = try makeTestModelContainer()
        let repo = ClientRepository(modelContext: container.mainContext)
        return (repo, container)
    }

    @Test @MainActor
    func fetchAllは空の場合空配列を返す() throws {
        let (repo, _) = try makeRepository()
        let result = try repo.fetchAll()
        #expect(result.isEmpty)
    }

    @Test @MainActor
    func upsertで新規クライアントが挿入される() throws {
        let (repo, _) = try makeRepository()
        let client = ClientCache(id: "c1", name: "山田太郎", furigana: "やまだたろう")
        try repo.upsert(client)

        let result = try repo.fetchAll()
        #expect(result.count == 1)
        #expect(result[0].name == "山田太郎")
    }

    @Test @MainActor
    func upsertで既存クライアントが更新される() throws {
        let (repo, _) = try makeRepository()
        let client = ClientCache(id: "c1", name: "山田太郎", furigana: "やまだたろう")
        try repo.upsert(client)

        let updated = ClientCache(id: "c1", name: "山田次郎", furigana: "やまだじろう")
        try repo.upsert(updated)

        let result = try repo.fetchAll()
        #expect(result.count == 1)
        #expect(result[0].name == "山田次郎")
        #expect(result[0].furigana == "やまだじろう")
    }

    @Test @MainActor
    func replaceAllで全データが置き換わる() throws {
        let (repo, _) = try makeRepository()
        try repo.upsert(ClientCache(id: "c1", name: "初回", furigana: "しょかい"))

        let newClients = [
            ClientCache(id: "c2", name: "二回目A", furigana: "にかいめA"),
            ClientCache(id: "c3", name: "二回目B", furigana: "にかいめB"),
        ]
        try repo.replaceAll(with: newClients)

        let result = try repo.fetchAll()
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.name.hasPrefix("二回目") })
    }

    @Test @MainActor
    func fetchAllはふりがな順でソートされる() throws {
        let (repo, _) = try makeRepository()
        try repo.replaceAll(with: [
            ClientCache(id: "c1", name: "田中", furigana: "たなか"),
            ClientCache(id: "c2", name: "阿部", furigana: "あべ"),
            ClientCache(id: "c3", name: "山田", furigana: "やまだ"),
        ])

        let result = try repo.fetchAll()
        #expect(result[0].furigana == "あべ")
        #expect(result[1].furigana == "たなか")
        #expect(result[2].furigana == "やまだ")
    }
}
