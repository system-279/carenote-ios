import AuthenticationServices
@preconcurrency import FirebaseAuth
import FirebaseCore
@preconcurrency import FirebaseFunctions
@preconcurrency import GoogleSignIn
import Observation
import os.log
import UIKit

// MARK: - AuthState

enum AuthState: Sendable, Equatable {
    case signedOut
    case signedIn(userId: String, tenantId: String, isAdmin: Bool = false)

    var isSignedIn: Bool {
        if case .signedIn = self { return true }
        return false
    }

    var userId: String? {
        if case .signedIn(let userId, _, _) = self { return userId }
        return nil
    }

    var tenantId: String? {
        if case .signedIn(_, let tenantId, _) = self { return tenantId }
        return nil
    }

    var isAdmin: Bool {
        if case .signedIn(_, _, let isAdmin) = self { return isAdmin }
        return false
    }
}

// MARK: - AuthProviding Protocol

protocol AuthProviding: Sendable {
    @MainActor func signInWithGoogle() async throws -> (userId: String, tenantId: String?, role: UserRole)
    func signOut() throws
}

// MARK: - AuthError

enum AuthError: Error, Sendable {
    case viewControllerNotFound
    case googleIdTokenMissing
    case appleIdTokenMissing
    case appleSignInCancelled
}

// MARK: - FirebaseGoogleAuthProvider

final class FirebaseGoogleAuthProvider: AuthProviding {
    @MainActor
    func signInWithGoogle() async throws -> (userId: String, tenantId: String?, role: UserRole) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            throw AuthError.viewControllerNotFound
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)

        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.googleIdTokenMissing
        }

        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )

        let authResult = try await Auth.auth().signIn(with: credential)
        let tokenResult = try await authResult.user.getIDTokenResult(forcingRefresh: true)
        let tenantId = tokenResult.claims["tenantId"] as? String
        let role = UserRole.from(firestoreValue: tokenResult.claims["role"] as? String)

        return (userId: authResult.user.uid, tenantId: tenantId, role: role)
    }

    func signOut() throws {
        GIDSignIn.sharedInstance.signOut()
        try Auth.auth().signOut()
    }
}

// MARK: - EmailAuthProviding Protocol

protocol EmailAuthProviding: Sendable {
    func signIn(email: String, password: String) async throws -> (userId: String, tenantId: String?, role: UserRole)
}

// MARK: - FirebaseEmailAuthProvider

final class FirebaseEmailAuthProvider: EmailAuthProviding {
    func signIn(email: String, password: String) async throws -> (userId: String, tenantId: String?, role: UserRole) {
        let authResult = try await Auth.auth().signIn(withEmail: email, password: password)
        let tokenResult = try await authResult.user.getIDTokenResult(forcingRefresh: true)
        let tenantId = tokenResult.claims["tenantId"] as? String
        let role = UserRole.from(firestoreValue: tokenResult.claims["role"] as? String)
        return (userId: authResult.user.uid, tenantId: tenantId, role: role)
    }
}

// MARK: - AuthViewModel

@Observable
@MainActor
final class AuthViewModel {
    var authState: AuthState = .signedOut
    var isLoading: Bool = false
    var errorMessage: String?
    var displayName: String?

    private let authProvider: AuthProviding
    let appleSignInCoordinator = AppleSignInCoordinator()
    private let emailAuthProvider: EmailAuthProviding
    /// アカウント削除後にローカル SwiftData / Outbox をクリアするための依存。
    /// `private(set)` で外部書き換えを禁止（#91 セキュリティ要件: 差替で purge 無効化を防ぐ）。
    /// Optional なのは `CareNoteApp.init` で `ModelContainer` 構築後に後注入するため、および
    /// ログインのみを扱うユニットテストで注入不要にするため。
    private(set) var localDataCleaner: LocalDataCleaning?
    private nonisolated(unsafe) var authStateHandle: AuthStateDidChangeListenerHandle?
    private static let logger = Logger(subsystem: "jp.carenote.app", category: "AuthVM")

    init(
        authProvider: AuthProviding = FirebaseGoogleAuthProvider(),
        emailAuthProvider: EmailAuthProviding = FirebaseEmailAuthProvider(),
        localDataCleaner: LocalDataCleaning? = nil
    ) {
        self.authProvider = authProvider
        self.emailAuthProvider = emailAuthProvider
        self.localDataCleaner = localDataCleaner
    }

    deinit {
        if let handle = authStateHandle, FirebaseApp.app() != nil {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    /// Google Sign-In を実行し、Firebase Auth と連携する
    func signInWithGoogle() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await authProvider.signInWithGoogle()

            guard let tenantId = result.tenantId, !tenantId.isEmpty else {
                // Firebase にはサインイン済みだがテナント未設定 → セッション破棄して半端な状態を防止
                try? authProvider.signOut()
                errorMessage = "テナント情報の取得に失敗しました。管理者にお問い合わせください。\nFailed to retrieve tenant info. Please contact the administrator."
                return
            }

            let isAdmin = result.role == .admin
            authState = .signedIn(userId: result.userId, tenantId: tenantId, isAdmin: isAdmin)
            updateDisplayName()
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    /// Apple Sign-In の結果を処理し、Firebase Auth と連携する
    func handleAppleSignInResult(_ result: Result<ASAuthorization, Error>) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let authResult = try await appleSignInCoordinator.handleResult(result)

            guard let tenantId = authResult.tenantId, !tenantId.isEmpty else {
                try? authProvider.signOut()
                errorMessage = "テナント情報の取得に失敗しました。管理者にお問い合わせください。\nFailed to retrieve tenant info. Please contact the administrator."
                return
            }

            let isAdmin = authResult.role == .admin
            authState = .signedIn(userId: authResult.userId, tenantId: tenantId, isAdmin: isAdmin)
            updateDisplayName()
        } catch let error as ASAuthorizationError where error.code == .canceled {
            // ユーザーキャンセルはエラー表示しない
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    /// メール/パスワードでサインインする（デモアカウント用）
    func signInWithEmail(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await emailAuthProvider.signIn(email: email, password: password)

            guard let tenantId = result.tenantId, !tenantId.isEmpty else {
                try? authProvider.signOut()
                errorMessage = "テナント情報の取得に失敗しました。管理者にお問い合わせください。\nFailed to retrieve tenant info. Please contact the administrator."
                return
            }

            let isAdmin = result.role == .admin
            authState = .signedIn(userId: result.userId, tenantId: tenantId, isAdmin: isAdmin)
            updateDisplayName()
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    private static let unregisteredAccountMessage = """
        このアカウントは現在ご利用できません。管理者にお問い合わせください。
        This account is not available. Please contact your administrator.
        """

    /// Firebase Auth エラーをユーザー向けメッセージに変換する
    private static func userFacingMessage(for error: Error) -> String {
        let nsError = error as NSError

        // beforeSignIn blocking function のエラー検知（コード判定 + メッセージ文字列フォールバック）
        if isBlockingFunctionError(nsError) {
            return unregisteredAccountMessage
        }

        guard nsError.domain == "FIRAuthErrorDomain" else {
            return "サインインに失敗しました。通信環境を確認して再度お試しください。"
        }

        switch AuthErrorCode(rawValue: nsError.code) {
        case .wrongPassword, .invalidCredential:
            return "メールアドレスまたはパスワードが正しくありません。\nIncorrect email or password."
        case .invalidEmail:
            return "メールアドレスの形式が正しくありません。\nInvalid email format."
        case .userNotFound:
            return "このメールアドレスのアカウントが見つかりません。\nNo account found for this email."
        case .userDisabled:
            return "このアカウントは無効化されています。管理者にお問い合わせください。\nThis account has been disabled."
        case .networkError:
            return "ネットワークエラーが発生しました。通信環境を確認して再度お試しください。\nNetwork error. Please check your connection."
        case .tooManyRequests:
            return "ログイン試行回数が多すぎます。しばらく待ってから再度お試しください。\nToo many attempts. Please try again later."
        default:
            return "サインインに失敗しました。再度お試しください。\nSign-in failed. Please try again."
        }
    }

    /// beforeSignIn blocking function のエラーかどうかを判定する
    ///
    /// 判定優先順位:
    /// 1. AuthErrorCode.blockingCloudFunctionError（domain + code 17105）
    /// 2. FIRAuthErrorUserInfoNameKey による安定判定
    /// 3. underlyingError の再帰チェック（1, 2 を再帰適用）
    /// 4. エラーメッセージ内キーワード（最終フォールバック）
    private static func isBlockingFunctionError(_ nsError: NSError) -> Bool {
        if checkBlockingError(nsError, depth: 3) {
            return true
        }

        // 4. 全ドメインで文字列フォールバック（最終手段）
        let description = nsError.localizedDescription + (nsError.userInfo.description)
        return description.contains("BLOCKING_FUNCTION_ERROR")
            || description.contains("許可されていません")
            || description.contains("PERMISSION_DENIED")
    }

    /// NSError を再帰的にチェックして blocking function エラーか判定する
    private static func checkBlockingError(_ nsError: NSError, depth: Int) -> Bool {
        guard depth > 0 else { return false }

        // 1. domain + code チェック
        if nsError.domain == "FIRAuthErrorDomain",
           AuthErrorCode(rawValue: nsError.code) == .blockingCloudFunctionError {
            return true
        }

        // 2. FIRAuthErrorUserInfoNameKey チェック（SDK 内部の安定キー）
        if let errorName = nsError.userInfo["FIRAuthErrorUserInfoNameKey"] as? String,
           errorName == "ERROR_BLOCKING_CLOUD_FUNCTION_RETURNED_ERROR" {
            return true
        }

        // 3. underlyingError を再帰チェック
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return checkBlockingError(underlying, depth: depth - 1)
        }

        return false
    }

    /// アカウントを完全に削除する（App Store Guideline 5.1.1(v)）
    func deleteAccount() async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Apple Sign-In ユーザーは refresh token を revoke する（Guideline 5.1.1(v) 要件）。
        // authorization code の TTL は 5 分と短いため失敗しうるが、ベストエフォートで実行し
        // 削除処理は継続する（Apple 側に revoke API が呼ばれた履歴が残ることが重要）。
        if let authCode = KeychainHelper.load(forKey: KeychainKey.appleAuthorizationCode) {
            do {
                try await Auth.auth().revokeToken(withAuthorizationCode: authCode)
                Self.logger.info("Apple refresh token revoked successfully")
            } catch {
                Self.logger.info("Apple revoke token failed (best-effort, continuing): \(error.localizedDescription, privacy: .public)")
            }
            KeychainHelper.delete(forKey: KeychainKey.appleAuthorizationCode)
        }

        let functions = Functions.functions(region: "asia-northeast1")
        do {
            _ = try await functions.httpsCallable("deleteAccount").call()
        } catch {
            Self.logger.error("deleteAccount callable failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        // Cloud Functions 側で Auth ユーザーが削除されたため、Firebase Auth・Google SDK 双方の
        // ローカルセッションをクリア。Auth ユーザー削除直後の signOut は失敗しうる（想定内）が、
        // 状態整合性のため失敗内容はログに残す。
        do {
            try Auth.auth().signOut()
        } catch {
            Self.logger.info("Post-deletion signOut returned error (expected): \(error.localizedDescription, privacy: .public)")
        }
        GIDSignIn.sharedInstance.signOut()

        await performPostDeletionCleanup()

        authState = .signedOut
        displayName = nil
    }

    /// アカウント削除完了後に呼び出すローカルデータ purge フェーズ（best-effort）。
    /// 失敗しても Auth 削除は既完了のため throws せず、構造化 error ログのみ残す。
    /// `cleaner` 未注入時は no-op だが、本番環境で nil になるのは DI 配線バグなので
    /// error ログを出して検知できるようにする（#91 フォローアップ候補）。
    ///
    /// 本メソッドは Firebase 非依存のため、`deleteAccount()` 全体のユニットテストが
    /// 困難な中でも独立して behavioral test が可能（#91 レビュー指摘対応）。
    ///
    /// purge 失敗時は `errorMessage` にユーザー向けガイダンスを設定する（#157）。
    /// Auth 削除は既完了のため `authState = .signedOut` への遷移は呼び出し側で継続する。
    /// 完全復旧にはアプリ削除 + 再インストールが確実なため、その旨を案内する。
    @MainActor
    func performPostDeletionCleanup() async {
        guard let cleaner = localDataCleaner else {
            Self.logger.error("localDataCleaner not injected — post-deletion purge skipped. DI wiring bug.")
            errorMessage = Self.postDeletionPurgeFailureMessage
            return
        }

        do {
            try await cleaner.purgeAll()
        } catch {
            let ns = error as NSError
            Self.logger.error("""
                Post-deletion local data purge failed. \
                domain=\(ns.domain, privacy: .public) \
                code=\(ns.code, privacy: .public) \
                desc=\(ns.localizedDescription, privacy: .public) \
                underlying=\(String(describing: ns.userInfo[NSUnderlyingErrorKey]), privacy: .public)
                """)
            errorMessage = Self.postDeletionPurgeFailureMessage
        }
    }

    static let postDeletionPurgeFailureMessage = """
        アカウントは削除されましたが、端末内データのクリアに失敗しました。
        セキュリティ保護のため、アプリを一度削除して再インストールしてください。
        Your account has been deleted, but clearing local data on this device failed.
        Please delete and reinstall the app to ensure all data is removed.
        """

    /// サインアウトする
    func signOut() {
        errorMessage = nil
        do {
            try authProvider.signOut()
        } catch {
            Self.logger.error("signOut failed: \(error.localizedDescription)")
            errorMessage = "ログアウトに失敗しました。再度お試しください。"
        }
        authState = .signedOut
        displayName = nil
    }

    private func updateDisplayName() {
        guard FirebaseApp.app() != nil else { return }
        let user = Auth.auth().currentUser
        displayName = user?.displayName ?? user?.email
    }

    /// Firebase Auth の認証状態を監視して authState を更新する
    func checkAuthState() {
        guard FirebaseApp.app() != nil else { return }
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self else { return }
                if let user {
                    // まずキャッシュ済みトークンで暫定状態を試行（オフライン対応）
                    do {
                        let tokenResult = try await user.getIDTokenResult(forcingRefresh: false)
                        if let tenantId = tokenResult.claims["tenantId"] as? String, !tenantId.isEmpty {
                            let role = UserRole.from(firestoreValue: tokenResult.claims["role"] as? String)
                            let isAdmin = role == .admin
                            self.authState = .signedIn(userId: user.uid, tenantId: tenantId, isAdmin: isAdmin)
                            self.updateDisplayName()
                        }
                    } catch {
                        Self.logger.info("Cached token unavailable: \(error.localizedDescription)")
                    }

                    // バックグラウンドで最新トークンを取得し状態を更新
                    do {
                        let freshToken = try await user.getIDTokenResult(forcingRefresh: true)
                        guard let tenantId = freshToken.claims["tenantId"] as? String,
                              !tenantId.isEmpty else {
                            self.authState = .signedOut
                            return
                        }
                        let role = UserRole.from(firestoreValue: freshToken.claims["role"] as? String)
                        let isAdmin = role == .admin
                        self.authState = .signedIn(userId: user.uid, tenantId: tenantId, isAdmin: isAdmin)
                        self.updateDisplayName()
                    } catch {
                        // refresh失敗時: キャッシュで暫定状態が設定済みならそれを維持、未設定なら現状維持
                        Self.logger.warning("Token refresh failed (keeping current state): \(error.localizedDescription)")
                    }
                } else {
                    self.authState = .signedOut
                }
            }
        }
    }
}
