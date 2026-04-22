@testable import CareNote
import Foundation
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

// MARK: - MockEmailAuthProvider

final class MockEmailAuthProvider: @unchecked Sendable, EmailAuthProviding {
    var signInResult: (userId: String, tenantId: String?, role: UserRole) = ("user-1", "tenant-1", .member)
    var signInError: Error?

    func signIn(email: String, password: String) async throws -> (userId: String, tenantId: String?, role: UserRole) {
        if let error = signInError {
            throw error
        }
        return signInResult
    }
}

// MARK: - MockLocalDataCleaner

final class MockLocalDataCleaner: @unchecked Sendable, LocalDataCleaning {
    var purgeCallCount = 0
    var purgeError: Error?

    func purgeAll() async throws {
        purgeCallCount += 1
        if let error = purgeError {
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

    // MARK: - performPostDeletionCleanup （#91）
    //
    // `deleteAccount()` 全体の integration test は Firebase 依存（Auth.auth().revokeToken /
    // Functions.httpsCallable）のため困難だが、post-deletion cleanup 部分は Firebase 非依存
    // の internal method として抽出済 → 以下で behavioral に検証できる。
    // `deleteAccount()` 全体の E2E は Emulator Suite（#105）で対応予定。

    @Test @MainActor
    func performPostDeletionCleanupはpurgeAllを呼ぶ() async {
        let cleaner = MockLocalDataCleaner()
        let vm = AuthViewModel(
            authProvider: MockAuthProvider(),
            emailAuthProvider: MockEmailAuthProvider(),
            localDataCleaner: cleaner
        )

        await vm.performPostDeletionCleanup()

        #expect(cleaner.purgeCallCount == 1)
        // 成功時は専用フラグを立てない（#157: UI 側で purge 失敗と誤認しないため）
        #expect(vm.postDeletionPurgeFailed == false)
        // authState は本メソッドで変更しない契約（呼び出し元の deleteAccount が遷移させる）
        #expect(vm.authState == .signedOut)
    }

    @Test @MainActor
    func purgeAll失敗時もperformPostDeletionCleanupはthrowsしない() async {
        let cleaner = MockLocalDataCleaner()
        cleaner.purgeError = NSError(domain: "TestPurge", code: 42, userInfo: [NSLocalizedDescriptionKey: "intentional"])
        let vm = AuthViewModel(
            authProvider: MockAuthProvider(),
            emailAuthProvider: MockEmailAuthProvider(),
            localDataCleaner: cleaner
        )

        // best-effort 契約: throw せず、authState も呼び出し側で .signedOut 遷移可能であること
        await vm.performPostDeletionCleanup()

        #expect(cleaner.purgeCallCount == 1)
        // #157: 失敗時は専用フラグを立ててUIに通知（errorMessage 兼用を避ける）
        #expect(vm.postDeletionPurgeFailed == true)
        // errorMessage は signIn 系と兼用のため本経路では触らない
        #expect(vm.errorMessage == nil)
    }

    @Test @MainActor
    func cleaner未注入時はpurgeAllが呼ばれずフラグ設定() async {
        let cleaner = MockLocalDataCleaner()
        let vm = AuthViewModel(
            authProvider: MockAuthProvider(),
            emailAuthProvider: MockEmailAuthProvider()
        )

        await vm.performPostDeletionCleanup()

        // 注入されていない cleaner は呼ばれない（DI 配線バグ扱い）
        #expect(cleaner.purgeCallCount == 0)
        // #157: DI 配線バグも purge 失敗と同じく専用フラグで通知
        #expect(vm.postDeletionPurgeFailed == true)
    }

    @Test @MainActor
    func postDeletionPurgeFailureMessageは再インストール案内を含む() {
        // #157 / pr-test G3: 文言 drift 防止。user-facing guidance の要件を lock する。
        let message = AuthViewModel.postDeletionPurgeFailureMessage
        #expect(message.contains("再インストール"))
        #expect(message.contains("reinstall"))
    }
}

// MARK: - Email Sign-In Tests

@Suite("Email Sign-In Tests")
struct EmailSignInTests {

    @Test @MainActor
    func メールサインイン成功時にsignedInになる() async {
        let mockAuth = MockAuthProvider()
        let mockEmail = MockEmailAuthProvider()
        mockEmail.signInResult = (userId: "user-2", tenantId: "tenant-1", role: .member)
        let vm = AuthViewModel(authProvider: mockAuth, emailAuthProvider: mockEmail)

        await vm.signInWithEmail(email: "test@example.com", password: "password")

        #expect(vm.authState == .signedIn(userId: "user-2", tenantId: "tenant-1", isAdmin: false))
        #expect(vm.errorMessage == nil)
    }

    @Test @MainActor
    func メールサインインでadminの場合isAdminがtrue() async {
        let mockAuth = MockAuthProvider()
        let mockEmail = MockEmailAuthProvider()
        mockEmail.signInResult = (userId: "user-2", tenantId: "tenant-1", role: .admin)
        let vm = AuthViewModel(authProvider: mockAuth, emailAuthProvider: mockEmail)

        await vm.signInWithEmail(email: "admin@example.com", password: "password")

        #expect(vm.authState == .signedIn(userId: "user-2", tenantId: "tenant-1", isAdmin: true))
    }

    @Test @MainActor
    func メールサインインでtenantIdがない場合エラー() async {
        let mockAuth = MockAuthProvider()
        let mockEmail = MockEmailAuthProvider()
        mockEmail.signInResult = (userId: "user-2", tenantId: nil, role: .member)
        let vm = AuthViewModel(authProvider: mockAuth, emailAuthProvider: mockEmail)

        await vm.signInWithEmail(email: "test@example.com", password: "password")

        #expect(vm.authState == .signedOut)
        #expect(vm.errorMessage?.contains("テナント情報") == true)
    }

    @Test @MainActor
    func メールサインイン失敗時にerrorMessageが設定される() async {
        let mockAuth = MockAuthProvider()
        let mockEmail = MockEmailAuthProvider()
        mockEmail.signInError = NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid credentials"])
        let vm = AuthViewModel(authProvider: mockAuth, emailAuthProvider: mockEmail)

        await vm.signInWithEmail(email: "test@example.com", password: "wrong")

        #expect(vm.authState == .signedOut)
        #expect(vm.errorMessage?.contains("サインインに失敗しました") == true)
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

// MARK: - AuthError Tests

@Suite("AuthError Tests")
struct AuthErrorTests {

    @Test func appleIdTokenMissingが存在する() {
        let error = AuthError.appleIdTokenMissing
        #expect(error == .appleIdTokenMissing)
    }

    @Test func appleSignInCancelledが存在する() {
        let error = AuthError.appleSignInCancelled
        #expect(error == .appleSignInCancelled)
    }
}
