import AuthenticationServices
@preconcurrency import FirebaseAuth
import FirebaseCore
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
    private nonisolated(unsafe) var authStateHandle: AuthStateDidChangeListenerHandle?
    private static let logger = Logger(subsystem: "jp.carenote.app", category: "AuthVM")

    init(
        authProvider: AuthProviding = FirebaseGoogleAuthProvider(),
        emailAuthProvider: EmailAuthProviding = FirebaseEmailAuthProvider()
    ) {
        self.authProvider = authProvider
        self.emailAuthProvider = emailAuthProvider
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
        このアカウントは登録されていません。\
        \n画面下部の「メールでログイン」からデモアカウントをご利用ください。\
        \n\nThis account is not registered.\
        \nPlease use "メールでログイン" (Email Login) below with the demo account.
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
    /// AuthErrorCode.blockingCloudFunctionError で判定できない場合（Apple Sign-In 経由等）は
    /// エラーメッセージ文字列にフォールバックする
    private static func isBlockingFunctionError(_ nsError: NSError) -> Bool {
        if nsError.domain == "FIRAuthErrorDomain",
           AuthErrorCode(rawValue: nsError.code) == .blockingCloudFunctionError {
            return true
        }
        // Apple Sign-In 経由では異なるエラーコードで返される場合がある
        let description = nsError.localizedDescription + (nsError.userInfo.description)
        return description.contains("許可されていません") || description.contains("BLOCKING_FUNCTION_ERROR")
    }

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
                    do {
                        let tokenResult = try await user.getIDTokenResult(forcingRefresh: true)
                        guard let tenantId = tokenResult.claims["tenantId"] as? String,
                              !tenantId.isEmpty else {
                            self.authState = .signedOut
                            return
                        }
                        let role = UserRole.from(firestoreValue: tokenResult.claims["role"] as? String)
                        let isAdmin = role == .admin
                        self.authState = .signedIn(userId: user.uid, tenantId: tenantId, isAdmin: isAdmin)
                        self.updateDisplayName()
                    } catch {
                        Self.logger.warning("Token refresh failed (keeping current state): \(error.localizedDescription)")
                    }
                } else {
                    self.authState = .signedOut
                }
            }
        }
    }
}
