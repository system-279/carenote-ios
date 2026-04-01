@testable import CareNote
import Foundation
import SwiftData
import Testing

// MARK: - MockClientManager

actor MockClientManager: ClientManaging {
    var clientsToReturn: [FirestoreClient] = []
    var errorToThrow: Error?

    func setClients(_ clients: [FirestoreClient]) {
        self.clientsToReturn = clients
    }

    func setError(_ error: Error) {
        self.errorToThrow = error
    }

    func fetchClients(tenantId: String) async throws -> [FirestoreClient] {
        if let error = errorToThrow {
            throw error
        }
        return clientsToReturn
    }

    func addClient(tenantId: String, name: String, furigana: String) async throws {}
    func updateClient(tenantId: String, clientId: String, name: String, furigana: String) async throws {}
    func deleteClient(tenantId: String, clientId: String) async throws {}
}

// MARK: - ClientCacheService Tests

@Suite("ClientCacheService Tests", .serialized)
struct ClientCacheServiceTests {

    @Test @MainActor
    func キャッシュ空の場合needsRefreshはtrue() throws {
        let container = try makeClientOnlyTestModelContainer()
        let manager = MockClientManager()
        let service = ClientCacheService(clientManager: manager, modelContainer: container)

        #expect(service.needsRefresh() == true)
    }

    @Test @MainActor
    func キャッシュ新鮮な場合needsRefreshはfalse() async throws {
        let container = try makeClientOnlyTestModelContainer()
        let manager = MockClientManager()
        await manager.setClients([
            FirestoreClient(id: "c1", name: "山田太郎", furigana: "やまだたろう"),
        ])

        let service = ClientCacheService(clientManager: manager, modelContainer: container)
        try await service.forceRefresh(tenantId: "t1")

        #expect(service.needsRefresh() == false)
    }

    @Test @MainActor
    func forceRefreshでFirestoreデータがキャッシュされる() async throws {
        let container = try makeClientOnlyTestModelContainer()
        let manager = MockClientManager()
        await manager.setClients([
            FirestoreClient(id: "c1", name: "山田太郎", furigana: "やまだたろう"),
            FirestoreClient(id: "c2", name: "田中花子", furigana: "たなかはなこ"),
        ])

        let service = ClientCacheService(clientManager: manager, modelContainer: container)
        try await service.forceRefresh(tenantId: "t1")

        let cached = try service.getCachedClients()
        #expect(cached.count == 2)
    }

    @Test @MainActor
    func getCachedClientsはふりがな順にソートされる() async throws {
        let container = try makeClientOnlyTestModelContainer()
        let manager = MockClientManager()
        await manager.setClients([
            FirestoreClient(id: "c1", name: "山田太郎", furigana: "やまだたろう"),
            FirestoreClient(id: "c2", name: "田中花子", furigana: "たなかはなこ"),
        ])

        let service = ClientCacheService(clientManager: manager, modelContainer: container)
        try await service.forceRefresh(tenantId: "t1")

        let cached = try service.getCachedClients()
        #expect(cached.count == 2)
        #expect(cached[0].furigana == "たなかはなこ")
        #expect(cached[1].furigana == "やまだたろう")
    }

    @Test @MainActor
    func forceRefreshで既存キャッシュが置き換わる() async throws {
        let container = try makeClientOnlyTestModelContainer()
        let manager = MockClientManager()

        await manager.setClients([
            FirestoreClient(id: "c1", name: "初回", furigana: "しょかい"),
        ])
        let service = ClientCacheService(clientManager: manager, modelContainer: container)
        try await service.forceRefresh(tenantId: "t1")
        #expect(try service.getCachedClients().count == 1)

        await manager.setClients([
            FirestoreClient(id: "c2", name: "二回目A", furigana: "にかいめA"),
            FirestoreClient(id: "c3", name: "二回目B", furigana: "にかいめB"),
        ])
        try await service.forceRefresh(tenantId: "t1")

        let cached = try service.getCachedClients()
        #expect(cached.count == 2)
        #expect(cached.allSatisfy { $0.name.hasPrefix("二回目") })
    }

    @Test @MainActor
    func Firestoreエラー時にrefreshFailedエラー() async throws {
        let container = try makeClientOnlyTestModelContainer()
        let manager = MockClientManager()
        await manager.setError(NSError(domain: "Test", code: 1))

        let service = ClientCacheService(clientManager: manager, modelContainer: container)

        await #expect(throws: ClientCacheError.self) {
            try await service.forceRefresh(tenantId: "t1")
        }
    }

    @Test @MainActor
    func refreshIfNeededはキャッシュ新鮮時にスキップ() async throws {
        let container = try makeClientOnlyTestModelContainer()
        let manager = MockClientManager()
        await manager.setClients([
            FirestoreClient(id: "c1", name: "テスト", furigana: "てすと"),
        ])

        let service = ClientCacheService(clientManager: manager, modelContainer: container)
        try await service.forceRefresh(tenantId: "t1")

        await manager.setError(NSError(domain: "Test", code: 1))
        try await service.refreshIfNeeded(tenantId: "t1")

        let cached = try service.getCachedClients()
        #expect(cached.count == 1)
    }
}
