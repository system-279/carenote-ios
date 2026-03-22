import Foundation
import Observation
import os.log

// MARK: - WhitelistViewModel

@Observable
@MainActor
final class WhitelistViewModel {

    var entries: [FirestoreWhitelistEntry] = []
    var newEmail: String = ""
    var isLoading: Bool = false
    var errorMessage: String?

    let tenantId: String
    private let userId: String
    private let whitelistService: WhitelistManaging
    private static let logger = Logger(subsystem: "jp.carenote.app", category: "WhitelistVM")

    init(tenantId: String, userId: String, whitelistService: WhitelistManaging = FirestoreService()) {
        self.tenantId = tenantId
        self.userId = userId
        self.whitelistService = whitelistService
    }

    var isValidEmail: Bool {
        let trimmed = newEmail.trimmingCharacters(in: .whitespaces)
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    func loadWhitelist() async {
        isLoading = true
        defer { isLoading = false }

        do {
            entries = try await whitelistService.fetchWhitelist(tenantId: tenantId)
        } catch {
            Self.logger.error("Failed to fetch whitelist: \(error.localizedDescription)")
            errorMessage = "ホワイトリストの取得に失敗しました"
        }
    }

    func addEmail() async {
        errorMessage = nil
        let email = newEmail.normalizedEmail
        guard !email.isEmpty, isValidEmail else { return }

        // 重複チェック
        if entries.contains(where: { $0.email == email }) {
            errorMessage = "このメールアドレスは既に登録されています"
            return
        }

        do {
            try await whitelistService.addToWhitelist(tenantId: tenantId, email: email, addedBy: userId)
            newEmail = ""
            await loadWhitelist()
        } catch {
            Self.logger.error("Failed to add to whitelist: \(error.localizedDescription)")
            errorMessage = "追加に失敗しました"
        }
    }

    func removeEntry(_ entry: FirestoreWhitelistEntry) async {
        errorMessage = nil
        guard let entryId = entry.id else { return }

        do {
            try await whitelistService.removeFromWhitelist(tenantId: tenantId, entryId: entryId)
            entries.removeAll { $0.id == entryId }
        } catch {
            Self.logger.error("Failed to remove from whitelist: \(error.localizedDescription)")
            errorMessage = "削除に失敗しました"
        }
    }
}
