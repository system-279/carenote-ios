import Foundation
import Observation
import os.log

// MARK: - ClientManagementViewModel

@Observable
@MainActor
final class ClientManagementViewModel {

    var clients: [FirestoreClient] = []
    var newName: String = ""
    var newFurigana: String = ""
    var isLoading: Bool = false
    var errorMessage: String?

    let tenantId: String
    private let clientService: ClientManaging
    private let cacheService: ClientCacheService?
    private static let logger = Logger(subsystem: "jp.carenote.app", category: "ClientMgmtVM")

    init(tenantId: String, clientService: ClientManaging = FirestoreService(), cacheService: ClientCacheService? = nil) {
        self.tenantId = tenantId
        self.clientService = clientService
        self.cacheService = cacheService
    }

    var isValidInput: Bool {
        !newName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func loadClients() async {
        isLoading = true
        defer { isLoading = false }

        do {
            clients = try await clientService.fetchClients(tenantId: tenantId)
        } catch {
            Self.logger.error("Failed to fetch clients: \(error.localizedDescription)")
            errorMessage = "利用者一覧の取得に失敗しました"
        }
    }

    func addClient() async {
        errorMessage = nil
        let name = newName.trimmingCharacters(in: .whitespaces)
        let furigana = newFurigana.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        do {
            try await clientService.addClient(tenantId: tenantId, name: name, furigana: furigana)
            try? await cacheService?.forceRefresh(tenantId: tenantId)
            newName = ""
            newFurigana = ""
            await loadClients()
        } catch {
            Self.logger.error("Failed to add client: \(error.localizedDescription)")
            errorMessage = "利用者の追加に失敗しました"
        }
    }

    func updateClient(clientId: String, name: String, furigana: String) async {
        errorMessage = nil

        do {
            try await clientService.updateClient(
                tenantId: tenantId,
                clientId: clientId,
                name: name,
                furigana: furigana
            )
            try? await cacheService?.forceRefresh(tenantId: tenantId)
            await loadClients()
        } catch {
            Self.logger.error("Failed to update client: \(error.localizedDescription)")
            errorMessage = "利用者の更新に失敗しました"
        }
    }

    func deleteClient(_ client: FirestoreClient) async {
        errorMessage = nil

        do {
            try await clientService.deleteClient(tenantId: tenantId, clientId: client.id)
            try? await cacheService?.forceRefresh(tenantId: tenantId)
            clients.removeAll { $0.id == client.id }
        } catch {
            Self.logger.error("Failed to delete client: \(error.localizedDescription)")
            errorMessage = "利用者の削除に失敗しました"
        }
    }
}
