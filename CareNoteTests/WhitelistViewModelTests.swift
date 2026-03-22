@testable import CareNote
import Foundation
import Testing

// MARK: - MockWhitelistManaging

private final class StubWhitelistService: @unchecked Sendable, WhitelistManaging {
    var entries: [FirestoreWhitelistEntry] = []
    var addedEmails: [(email: String, addedBy: String)] = []
    var removedIds: [String] = []
    var shouldThrow = false

    func fetchWhitelist(tenantId: String) async throws -> [FirestoreWhitelistEntry] {
        if shouldThrow { throw FirestoreError.operationFailed(NSError(domain: "", code: -1)) }
        return entries
    }

    func addToWhitelist(tenantId: String, email: String, addedBy: String) async throws {
        if shouldThrow { throw FirestoreError.operationFailed(NSError(domain: "", code: -1)) }
        addedEmails.append((email: email, addedBy: addedBy))
        entries.append(FirestoreWhitelistEntry(
            id: "new-\(entries.count)",
            email: email,
            addedBy: addedBy,
            addedAt: Date()
        ))
    }

    func removeFromWhitelist(tenantId: String, entryId: String) async throws {
        if shouldThrow { throw FirestoreError.operationFailed(NSError(domain: "", code: -1)) }
        removedIds.append(entryId)
        entries.removeAll { $0.id == entryId }
    }

    func isEmailWhitelisted(tenantId: String, email: String) async throws -> Bool {
        entries.contains { $0.email == email.lowercased() }
    }
}

// MARK: - WhitelistViewModelTests

@Suite("WhitelistViewModel Tests")
struct WhitelistViewModelTests {

    @MainActor
    private func makeVM(service: StubWhitelistService = StubWhitelistService()) -> (WhitelistViewModel, StubWhitelistService) {
        let vm = WhitelistViewModel(tenantId: "tenant-1", userId: "admin-1", whitelistService: service)
        return (vm, service)
    }

    @Test @MainActor
    func loadWhitelistで一覧が取得される() async {
        let service = StubWhitelistService()
        service.entries = [
            FirestoreWhitelistEntry(id: "1", email: "a@example.com", addedBy: "admin-1", addedAt: Date()),
            FirestoreWhitelistEntry(id: "2", email: "b@example.com", addedBy: "admin-1", addedAt: Date()),
        ]
        let (vm, _) = makeVM(service: service)

        await vm.loadWhitelist()

        #expect(vm.entries.count == 2)
        #expect(vm.isLoading == false)
    }

    @Test @MainActor
    func addEmailで新規メールが追加される() async {
        let (vm, service) = makeVM()
        vm.newEmail = "new@example.com"

        await vm.addEmail()

        #expect(service.addedEmails.count == 1)
        #expect(service.addedEmails.first?.email == "new@example.com")
        #expect(vm.newEmail == "") // 入力がクリアされる
    }

    @Test @MainActor
    func 重複メールは追加されない() async {
        let service = StubWhitelistService()
        service.entries = [
            FirestoreWhitelistEntry(id: "1", email: "dup@example.com", addedBy: "admin-1", addedAt: Date()),
        ]
        let (vm, _) = makeVM(service: service)
        await vm.loadWhitelist()

        vm.newEmail = "dup@example.com"
        await vm.addEmail()

        #expect(vm.errorMessage?.contains("既に登録") == true)
    }

    @Test @MainActor
    func removeEntryでエントリが削除される() async {
        let service = StubWhitelistService()
        let entry = FirestoreWhitelistEntry(id: "1", email: "del@example.com", addedBy: "admin-1", addedAt: Date())
        service.entries = [entry]
        let (vm, _) = makeVM(service: service)
        await vm.loadWhitelist()

        await vm.removeEntry(entry)

        #expect(vm.entries.isEmpty)
        #expect(service.removedIds == ["1"])
    }

    @Test @MainActor
    func isValidEmailの境界値テスト() {
        let (vm, _) = makeVM()

        vm.newEmail = ""
        #expect(vm.isValidEmail == false)

        vm.newEmail = "noatsign"
        #expect(vm.isValidEmail == false)

        vm.newEmail = "no@dot"
        #expect(vm.isValidEmail == false)

        vm.newEmail = "valid@example.com"
        #expect(vm.isValidEmail == true)

        vm.newEmail = "  spaced@example.com  "
        #expect(vm.isValidEmail == true)
    }

    @Test @MainActor
    func fetchエラー時にerrorMessageが設定される() async {
        let service = StubWhitelistService()
        service.shouldThrow = true
        let (vm, _) = makeVM(service: service)

        await vm.loadWhitelist()

        #expect(vm.errorMessage != nil)
        #expect(vm.entries.isEmpty)
    }
}
