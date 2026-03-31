@testable import CareNote
import Foundation
import Testing

// MARK: - ClientSelectViewModel Tests
//
// These tests verify search/filter logic only.
// SwiftData integration is tested in ClientRepositoryTests.

@Suite("ClientSelectViewModel Tests")
struct ClientSelectViewModelTests {

    /// Create a ViewModel with pre-loaded clients (no SwiftData dependency).
    @MainActor
    private func makeViewModel(clients: [ClientCache] = []) -> ClientSelectViewModel {
        let container = try! makeClientOnlyTestModelContainer()
        let repo = ClientRepository(modelContext: container.mainContext)
        let vm = ClientSelectViewModel(clientRepository: repo)
        vm.clients = clients
        return vm
    }

    private func sampleClients() -> [ClientCache] {
        [
            ClientCache(id: "c1", name: "山田太郎", furigana: "やまだたろう"),
            ClientCache(id: "c2", name: "田中花子", furigana: "たなかはなこ"),
        ]
    }

    @Test @MainActor
    func loadClientsでクライアント一覧が読み込まれる() async throws {
        let container = try makeClientOnlyTestModelContainer()
        let repo = ClientRepository(modelContext: container.mainContext)
        let vm = ClientSelectViewModel(clientRepository: repo)

        // Insert via repo for loadClients test
        try repo.replaceAll(with: sampleClients())
        await vm.loadClients()

        #expect(vm.clients.count == 2)
        #expect(vm.isLoading == false)
    }

    @Test @MainActor
    func filteredClientsで名前検索がフィルタされる() {
        let vm = makeViewModel(clients: sampleClients())
        vm.searchText = "山田"

        #expect(vm.filteredClients.count == 1)
        #expect(vm.filteredClients[0].name == "山田太郎")
    }

    @Test @MainActor
    func filteredClientsでふりがな検索がフィルタされる() {
        let vm = makeViewModel(clients: sampleClients())
        vm.searchText = "たなか"

        #expect(vm.filteredClients.count == 1)
        #expect(vm.filteredClients[0].name == "田中花子")
    }

    @Test @MainActor
    func filteredClientsで検索テキスト空は全件返す() {
        let vm = makeViewModel(clients: sampleClients())
        vm.searchText = ""

        #expect(vm.filteredClients.count == 2)
    }

    @Test @MainActor
    func filteredClientsでマッチなしは空配列() {
        let vm = makeViewModel(clients: sampleClients())
        vm.searchText = "存在しない"

        #expect(vm.filteredClients.isEmpty)
    }

    @Test @MainActor
    func 大文字小文字を無視して検索() {
        let vm = makeViewModel(clients: [
            ClientCache(id: "c1", name: "TestUser", furigana: "てすとゆーざー"),
        ])
        vm.searchText = "testuser"

        #expect(vm.filteredClients.count == 1)
    }
}
