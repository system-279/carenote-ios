import Foundation
import Observation
import os.log

// MARK: - WhitelistViewModel

@Observable
@MainActor
final class WhitelistViewModel {

    var entries: [WhitelistEntry] = []
    var allowedDomains: [String] = []
    var newEmail: String = ""
    var newRole: String = "user"
    var newDomain: String = ""
    var isLoading: Bool = false
    var errorMessage: String?

    let tenantId: String
    let userId: String
    private let firestoreService: FirestoreService
    private static let logger = Logger(subsystem: "jp.carenote.app", category: "WhitelistVM")

    init(tenantId: String, userId: String, firestoreService: FirestoreService = FirestoreService()) {
        self.tenantId = tenantId
        self.userId = userId
        self.firestoreService = firestoreService
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let fetchedEntries = firestoreService.fetchWhitelist(tenantId: tenantId)
            async let fetchedDomains = firestoreService.fetchAllowedDomains(tenantId: tenantId)
            entries = try await fetchedEntries
            allowedDomains = try await fetchedDomains
        } catch {
            Self.logger.error("Failed to load whitelist: \(error.localizedDescription)")
            errorMessage = "メンバー情報の取得に失敗しました"
        }
    }

    // MARK: - Email Management

    var isValidEmail: Bool {
        let email = newEmail.trimmingCharacters(in: .whitespaces)
        return email.contains("@") && email.contains(".")
    }

    func addEmail() async {
        errorMessage = nil
        let email = newEmail.lowercased().trimmingCharacters(in: .whitespaces)
        guard !email.isEmpty else { return }

        if entries.contains(where: { $0.email == email }) {
            errorMessage = "このメールアドレスは既に登録されています"
            return
        }

        do {
            try await firestoreService.addToWhitelist(
                tenantId: tenantId,
                email: email,
                role: newRole,
                addedBy: userId
            )
            newEmail = ""
            newRole = "user"
            await load()
        } catch {
            Self.logger.error("Failed to add email: \(error.localizedDescription)")
            errorMessage = "メールアドレスの追加に失敗しました"
        }
    }

    func removeEntry(_ entry: WhitelistEntry) async {
        errorMessage = nil
        do {
            try await firestoreService.removeFromWhitelist(tenantId: tenantId, entryId: entry.id)
            entries.removeAll { $0.id == entry.id }
        } catch {
            Self.logger.error("Failed to remove entry: \(error.localizedDescription)")
            errorMessage = "メンバーの削除に失敗しました"
        }
    }

    func toggleRole(_ entry: WhitelistEntry) async {
        errorMessage = nil
        let newRole = entry.role == "admin" ? "user" : "admin"
        do {
            try await firestoreService.updateWhitelistRole(
                tenantId: tenantId,
                entryId: entry.id,
                role: newRole
            )
            await load()
        } catch {
            Self.logger.error("Failed to update role: \(error.localizedDescription)")
            errorMessage = "ロールの変更に失敗しました"
        }
    }

    // MARK: - Domain Management

    var isValidDomain: Bool {
        let domain = newDomain.trimmingCharacters(in: .whitespaces)
        return domain.contains(".") && !domain.contains("@")
    }

    func addDomain() async {
        errorMessage = nil
        let domain = newDomain.lowercased().trimmingCharacters(in: .whitespaces)
        guard !domain.isEmpty else { return }

        if allowedDomains.contains(domain) {
            errorMessage = "このドメインは既に登録されています"
            return
        }

        var updated = allowedDomains
        updated.append(domain)

        do {
            try await firestoreService.setAllowedDomains(tenantId: tenantId, domains: updated)
            allowedDomains = updated
            newDomain = ""
        } catch {
            Self.logger.error("Failed to add domain: \(error.localizedDescription)")
            errorMessage = "ドメインの追加に失敗しました"
        }
    }

    func removeDomain(_ domain: String) async {
        errorMessage = nil
        var updated = allowedDomains
        updated.removeAll { $0 == domain }

        do {
            try await firestoreService.setAllowedDomains(tenantId: tenantId, domains: updated)
            allowedDomains = updated
        } catch {
            Self.logger.error("Failed to remove domain: \(error.localizedDescription)")
            errorMessage = "ドメインの削除に失敗しました"
        }
    }
}
