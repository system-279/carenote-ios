@testable import CareNote
import Testing

// MARK: - MockAuthProvider

final class MockAuthProvider: @unchecked Sendable, AuthProviding {
    var signInResult: (userId: String, email: String?, tenantId: String?, role: String?) = ("user-1", "test@example.com", "tenant-1", "user")
    var signInError: Error?
    var signOutError: Error?

    @MainActor
    func signInWithGoogle() async throws -> (userId: String, email: String?, tenantId: String?, role: String?) {
        if let error = signInError {
            throw error
        }
        return signInResult
    }

    func signOut() throws {
        if let error = signOutError {
            throw error
        }
    }
}

// MARK: - MockWhitelistService

final class MockWhitelistService: @unchecked Sendable, WhitelistManaging {
    var emailRoles: [String: String] = ["test@example.com": "user"]

    func fetchWhitelist(tenantId: String) async throws -> [FirestoreWhitelistEntry] { [] }
    func addToWhitelist(tenantId: String, email: String, role: String, addedBy: String) async throws {}
    func removeFromWhitelist(tenantId: String, entryId: String) async throws {}
    func updateRole(tenantId: String, entryId: String, role: String) async throws {}

    func isEmailWhitelisted(tenantId: String, email: String) async throws -> Bool {
        emailRoles.keys.contains(email.lowercased())
    }

    func fetchRoleForEmail(tenantId: String, email: String) async throws -> String? {
        emailRoles[email.lowercased()]
    }
}

// MARK: - AuthViewModelTests

@Suite("AuthViewModel Tests")
struct AuthViewModelTests {

    @Test @MainActor
    func signOut後はsignedOutになる() {
        let mock = MockAuthProvider()
        let vm = AuthViewModel(authProvider: mock, whitelistService: MockWhitelistService())
        vm.authState = .signedIn(userId: "user-1", tenantId: "tenant-1", role: "user")

        vm.signOut()

        #expect(vm.authState == .signedOut)
        #expect(vm.errorMessage == nil)
    }

    @Test @MainActor
    func signIn成功時にsignedInになる() async {
        let mock = MockAuthProvider()
        mock.signInResult = (userId: "user-1", email: "test@example.com", tenantId: "tenant-1", role: "user")
        let whitelistMock = MockWhitelistService()
        let vm = AuthViewModel(authProvider: mock, whitelistService: whitelistMock)

        await vm.signInWithGoogle()

        #expect(vm.authState == .signedIn(userId: "user-1", tenantId: "tenant-1", role: "user"))
        #expect(vm.errorMessage == nil)
    }

    @Test @MainActor
    func adminロールでsignInするとisAdminがtrueになる() async {
        let mock = MockAuthProvider()
        mock.signInResult = (userId: "user-1", email: "admin@example.com", tenantId: "tenant-1", role: "admin")
        let vm = AuthViewModel(authProvider: mock, whitelistService: MockWhitelistService())

        await vm.signInWithGoogle()

        #expect(vm.authState == .signedIn(userId: "user-1", tenantId: "tenant-1", role: "admin"))
        #expect(vm.authState.isAdmin == true)
    }

    @Test @MainActor
    func ホワイトリスト未登録のユーザーはsignInが拒否される() async {
        let mock = MockAuthProvider()
        mock.signInResult = (userId: "user-1", email: "unknown@example.com", tenantId: "tenant-1", role: "user")
        let whitelistMock = MockWhitelistService()
        whitelistMock.emailRoles = ["allowed@example.com": "user"]
        let vm = AuthViewModel(authProvider: mock, whitelistService: whitelistMock)

        await vm.signInWithGoogle()

        #expect(vm.authState == .signedOut)
        #expect(vm.errorMessage?.contains("許可されていません") == true)
    }

    @Test @MainActor
    func adminはホワイトリスト未登録でもsignInできる() async {
        let mock = MockAuthProvider()
        mock.signInResult = (userId: "user-1", email: "admin@example.com", tenantId: "tenant-1", role: "admin")
        let whitelistMock = MockWhitelistService()
        whitelistMock.emailRoles = [:] // 空のホワイトリスト
        let vm = AuthViewModel(authProvider: mock, whitelistService: whitelistMock)

        await vm.signInWithGoogle()

        #expect(vm.authState == .signedIn(userId: "user-1", tenantId: "tenant-1", role: "admin"))
    }

    @Test @MainActor
    func tenantIdが空の場合はsignedOutのまま() async {
        let mock = MockAuthProvider()
        mock.signInResult = (userId: "user-1", email: "test@example.com", tenantId: "", role: "user")
        let vm = AuthViewModel(authProvider: mock, whitelistService: MockWhitelistService())

        await vm.signInWithGoogle()

        #expect(vm.authState == .signedOut)
        #expect(vm.errorMessage != nil)
    }

    @Test @MainActor
    func tenantIdがnilの場合はsignedOutのまま() async {
        let mock = MockAuthProvider()
        mock.signInResult = (userId: "user-1", email: nil, tenantId: nil, role: nil)
        let vm = AuthViewModel(authProvider: mock, whitelistService: MockWhitelistService())

        await vm.signInWithGoogle()

        #expect(vm.authState == .signedOut)
        #expect(vm.errorMessage != nil)
    }

    @Test @MainActor
    func signIn失敗時にerrorMessageが設定される() async {
        let mock = MockAuthProvider()
        mock.signInError = AuthError.viewControllerNotFound
        let vm = AuthViewModel(authProvider: mock, whitelistService: MockWhitelistService())

        await vm.signInWithGoogle()

        #expect(vm.authState == .signedOut)
        #expect(vm.errorMessage != nil)
        #expect(vm.errorMessage?.contains("サインインに失敗しました") == true)
    }

    @Test @MainActor
    func signIn中はisLoadingがtrueになる() async {
        let mock = MockAuthProvider()
        mock.signInResult = (userId: "user-1", email: "test@example.com", tenantId: "tenant-1", role: "user")
        let vm = AuthViewModel(authProvider: mock, whitelistService: MockWhitelistService())

        #expect(vm.isLoading == false)

        await vm.signInWithGoogle()

        // signIn完了後はisLoadingがfalseに戻る
        #expect(vm.isLoading == false)
    }
}
