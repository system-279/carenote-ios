import Foundation
import Observation
import SwiftData

// MARK: - ClientSelectViewModel

@Observable
final class ClientSelectViewModel {
    var clients: [ClientCache] = []
    var isLoading: Bool = false
    var searchText: String = ""

    private let clientRepository: ClientRepository

    init(clientRepository: ClientRepository) {
        self.clientRepository = clientRepository
    }

    /// 検索テキストでフィルタされた利用者リスト
    var filteredClients: [ClientCache] {
        guard !searchText.isEmpty else { return clients }
        let query = searchText.lowercased()
        return clients.filter { client in
            client.name.lowercased().contains(query)
                || client.furigana.lowercased().contains(query)
        }
    }

    /// SwiftData から利用者キャッシュを読み込む
    @MainActor
    func loadClients() async {
        isLoading = true
        do {
            clients = try clientRepository.fetchAll()
        } catch {
            clients = []
        }
        isLoading = false
    }
}
