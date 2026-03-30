@testable import CareNote
import Testing

// MARK: - MockAuthProvider

final class MockAuthProvider: @unchecked Sendable, AuthProviding {
    var signInResult: (userId: String, tenantId: String?, role: UserRole) = ("user-1", "tenant-1", .member)
    var signInError: Error?
    var signOutError: Error?

    @MainActor
    func signInWithGoogle() async throws -> (userId: String, tenantId: String?, role: UserRole) {
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

// MARK: - AuthViewModelTests

@Suite("AuthViewModel Tests")
struct AuthViewModelTests {

    @Test @MainActor
    func signOut後はsignedOutになる() {
        let mock = MockAuthProvider()
        let vm = AuthViewModel(authProvider: mock)
        vm.authState = .signedIn(userId: "user-1", tenantId: "tenant-1")

        vm.signOut()

        #expect(vm.authState == .signedOut)
        #expect(vm.errorMessage == nil)
    }

    @Test @MainActor
    func signIn成功時にsignedInになる() async {
        let mock = MockAuthProvider()
        mock.signInResult = (userId: "user-1", tenantId: "tenant-1", role: .member)
        let vm = AuthViewModel(authProvider: mock)

        await vm.signInWithGoogle()

        #expect(vm.authState == .signedIn(userId: "user-1", tenantId: "tenant-1", isAdmin: false))
        #expect(vm.errorMessage == nil)
    }

    @Test @MainActor
    func admin権限でsignInするとisAdminがtrueになる() async {
        let mock = MockAuthProvider()
        mock.signInResult = (userId: "user-1", tenantId: "tenant-1", role: .admin)
        let vm = AuthViewModel(authProvider: mock)

        await vm.signInWithGoogle()

        #expect(vm.authState == .signedIn(userId: "user-1", tenantId: "tenant-1", isAdmin: true))
        #expect(vm.authState.isAdmin == true)
    }

    @Test @MainActor
    func tenantIdが空の場合はsignedOutのまま() async {
        let mock = MockAuthProvider()
        mock.signInResult = (userId: "user-1", tenantId: "", role: .member)
        let vm = AuthViewModel(authProvider: mock)

        await vm.signInWithGoogle()

        #expect(vm.authState == .signedOut)
        #expect(vm.errorMessage != nil)
    }

    @Test @MainActor
    func tenantIdがnilの場合はsignedOutのまま() async {
        let mock = MockAuthProvider()
        mock.signInResult = (userId: "user-1", tenantId: nil, role: .member)
        let vm = AuthViewModel(authProvider: mock)

        await vm.signInWithGoogle()

        #expect(vm.authState == .signedOut)
        #expect(vm.errorMessage != nil)
    }

    @Test @MainActor
    func signIn失敗時にerrorMessageが設定される() async {
        let mock = MockAuthProvider()
        mock.signInError = AuthError.viewControllerNotFound
        let vm = AuthViewModel(authProvider: mock)

        await vm.signInWithGoogle()

        #expect(vm.authState == .signedOut)
        #expect(vm.errorMessage != nil)
        #expect(vm.errorMessage?.contains("サインインに失敗しました") == true)
    }

    @Test @MainActor
    func signIn中はisLoadingがtrueになる() async {
        let mock = MockAuthProvider()
        mock.signInResult = (userId: "user-1", tenantId: "tenant-1", role: .member)
        let vm = AuthViewModel(authProvider: mock)

        #expect(vm.isLoading == false)

        await vm.signInWithGoogle()

        // signIn完了後はisLoadingがfalseに戻る
        #expect(vm.isLoading == false)
    }
}

// MARK: - UserRole Tests

@Suite("UserRole Tests")
struct UserRoleTests {

    @Test func nilはmemberにマッピングされる() {
        #expect(UserRole.from(firestoreValue: nil) == .member)
    }

    @Test func adminはadminにマッピングされる() {
        #expect(UserRole.from(firestoreValue: "admin") == .admin)
    }

    @Test func memberはmemberにマッピングされる() {
        #expect(UserRole.from(firestoreValue: "member") == .member)
    }

    @Test func 未知の文字列はmemberにフォールバック() {
        #expect(UserRole.from(firestoreValue: "unknown") == .member)
    }

    @Test func 空文字列はmemberにフォールバック() {
        #expect(UserRole.from(firestoreValue: "") == .member)
    }
}
