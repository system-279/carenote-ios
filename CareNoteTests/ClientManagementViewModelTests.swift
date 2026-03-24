@testable import CareNote
import Foundation
import Testing

// MARK: - StubClientService

private final class StubClientService: @unchecked Sendable, ClientManaging {
    var clients: [FirestoreClient] = []
    var addedClients: [(name: String, furigana: String)] = []
    var updatedClients: [(clientId: String, name: String, furigana: String)] = []
    var deletedIds: [String] = []
    var shouldThrow = false

    func fetchClients(tenantId: String) async throws -> [FirestoreClient] {
        if shouldThrow { throw FirestoreError.operationFailed(NSError(domain: "", code: -1)) }
        return clients
    }

    func addClient(tenantId: String, name: String, furigana: String) async throws {
        if shouldThrow { throw FirestoreError.operationFailed(NSError(domain: "", code: -1)) }
        addedClients.append((name: name, furigana: furigana))
        clients.append(FirestoreClient(id: "new-\(clients.count)", name: name, furigana: furigana))
    }

    func updateClient(tenantId: String, clientId: String, name: String, furigana: String) async throws {
        if shouldThrow { throw FirestoreError.operationFailed(NSError(domain: "", code: -1)) }
        updatedClients.append((clientId: clientId, name: name, furigana: furigana))
        if let index = clients.firstIndex(where: { $0.id == clientId }) {
            clients[index] = FirestoreClient(id: clientId, name: name, furigana: furigana)
        }
    }

    func deleteClient(tenantId: String, clientId: String) async throws {
        if shouldThrow { throw FirestoreError.operationFailed(NSError(domain: "", code: -1)) }
        deletedIds.append(clientId)
        clients.removeAll { $0.id == clientId }
    }
}

// MARK: - ClientManagementViewModelTests

@Suite("ClientManagementViewModel Tests")
struct ClientManagementViewModelTests {

    @MainActor
    private func makeVM(service: StubClientService = StubClientService()) -> (ClientManagementViewModel, StubClientService) {
        let vm = ClientManagementViewModel(tenantId: "tenant-1", clientService: service)
        return (vm, service)
    }

    @Test @MainActor
    func loadClientsで一覧が取得される() async {
        let service = StubClientService()
        service.clients = [
            FirestoreClient(id: "1", name: "田中太郎", furigana: "たなかたろう"),
            FirestoreClient(id: "2", name: "山田花子", furigana: "やまだはなこ"),
        ]
        let (vm, _) = makeVM(service: service)

        await vm.loadClients()

        #expect(vm.clients.count == 2)
        #expect(vm.isLoading == false)
    }

    @Test @MainActor
    func addClientで利用者が追加される() async {
        let (vm, service) = makeVM()
        vm.newName = "鈴木一郎"
        vm.newFurigana = "すずきいちろう"

        await vm.addClient()

        #expect(service.addedClients.count == 1)
        #expect(service.addedClients.first?.name == "鈴木一郎")
        #expect(service.addedClients.first?.furigana == "すずきいちろう")
        #expect(vm.newName == "")
        #expect(vm.newFurigana == "")
    }

    @Test @MainActor
    func updateClientで利用者が更新される() async {
        let service = StubClientService()
        let client = FirestoreClient(id: "1", name: "田中太郎", furigana: "たなかたろう")
        service.clients = [client]
        let (vm, _) = makeVM(service: service)
        await vm.loadClients()

        await vm.updateClient(clientId: "1", name: "田中次郎", furigana: "たなかじろう")

        #expect(vm.clients.first?.name == "田中次郎")
        #expect(vm.clients.first?.furigana == "たなかじろう")
    }

    @Test @MainActor
    func deleteClientで利用者が削除される() async {
        let service = StubClientService()
        let client = FirestoreClient(id: "1", name: "田中太郎", furigana: "たなかたろう")
        service.clients = [client]
        let (vm, _) = makeVM(service: service)
        await vm.loadClients()

        await vm.deleteClient(client)

        #expect(vm.clients.isEmpty)
        #expect(service.deletedIds == ["1"])
    }

    @Test @MainActor
    func isValidInputの境界値テスト() {
        let (vm, _) = makeVM()

        vm.newName = ""
        #expect(vm.isValidInput == false)

        vm.newName = "   "
        #expect(vm.isValidInput == false)

        vm.newName = "田中太郎"
        #expect(vm.isValidInput == true)

        vm.newName = "  田中太郎  "
        #expect(vm.isValidInput == true)
    }

    @Test @MainActor
    func fetchエラー時にerrorMessageが設定される() async {
        let service = StubClientService()
        service.shouldThrow = true
        let (vm, _) = makeVM(service: service)

        await vm.loadClients()

        #expect(vm.errorMessage != nil)
        #expect(vm.clients.isEmpty)
    }

    @Test @MainActor
    func 名前が空の場合追加されない() async {
        let (vm, service) = makeVM()
        vm.newName = ""
        vm.newFurigana = "ふりがな"

        await vm.addClient()

        #expect(service.addedClients.isEmpty)
    }
}
