@testable import CareNote
import Foundation
import SwiftData
import Testing

// MARK: - ClientSelectViewModel Tests

@Suite("ClientSelectViewModel Tests", .serialized)
struct ClientSelectViewModelTests {

    @MainActor
    private func makeViewModel() throws -> (ClientSelectViewModel, ClientRepository) {
        let container = try makeTestModelContainer()
        let repo = ClientRepository(modelContext: container.mainContext)
        let vm = ClientSelectViewModel(clientRepository: repo)
        return (vm, repo)
    }

    @Test @MainActor
    func loadClientsでクライアント一覧が読み込まれる() async throws {
        let (vm, repo) = try makeViewModel()
        try repo.replaceAll(with: [
            ClientCache(id: "c1", name: "山田太郎", furigana: "やまだたろう"),
            ClientCache(id: "c2", name: "田中花子", furigana: "たなかはなこ"),
        ])

        await vm.loadClients()

        #expect(vm.clients.count == 2)
        #expect(vm.isLoading == false)
    }

    @Test @MainActor
    func filteredClientsで名前検索がフィルタされる() async throws {
        let (vm, repo) = try makeViewModel()
        try repo.replaceAll(with: [
            ClientCache(id: "c1", name: "山田太郎", furigana: "やまだたろう"),
            ClientCache(id: "c2", name: "田中花子", furigana: "たなかはなこ"),
        ])

        await vm.loadClients()
        vm.searchText = "山田"

        #expect(vm.filteredClients.count == 1)
        #expect(vm.filteredClients[0].name == "山田太郎")
    }

    @Test @MainActor
    func filteredClientsでふりがな検索がフィルタされる() async throws {
        let (vm, repo) = try makeViewModel()
        try repo.replaceAll(with: [
            ClientCache(id: "c1", name: "山田太郎", furigana: "やまだたろう"),
            ClientCache(id: "c2", name: "田中花子", furigana: "たなかはなこ"),
        ])

        await vm.loadClients()
        vm.searchText = "たなか"

        #expect(vm.filteredClients.count == 1)
        #expect(vm.filteredClients[0].name == "田中花子")
    }

    @Test @MainActor
    func filteredClientsで検索テキスト空は全件返す() async throws {
        let (vm, repo) = try makeViewModel()
        try repo.replaceAll(with: [
            ClientCache(id: "c1", name: "山田太郎", furigana: "やまだたろう"),
            ClientCache(id: "c2", name: "田中花子", furigana: "たなかはなこ"),
        ])

        await vm.loadClients()
        vm.searchText = ""

        #expect(vm.filteredClients.count == 2)
    }

    @Test @MainActor
    func filteredClientsでマッチなしは空配列() async throws {
        let (vm, repo) = try makeViewModel()
        try repo.replaceAll(with: [
            ClientCache(id: "c1", name: "山田太郎", furigana: "やまだたろう"),
        ])

        await vm.loadClients()
        vm.searchText = "存在しない"

        #expect(vm.filteredClients.isEmpty)
    }

    @Test @MainActor
    func 大文字小文字を無視して検索() async throws {
        let (vm, repo) = try makeViewModel()
        try repo.replaceAll(with: [
            ClientCache(id: "c1", name: "TestUser", furigana: "てすとゆーざー"),
        ])

        await vm.loadClients()
        vm.searchText = "testuser"

        #expect(vm.filteredClients.count == 1)
    }
}
