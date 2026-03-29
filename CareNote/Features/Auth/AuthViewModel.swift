import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import Observation
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
    @MainActor func signInWithGoogle() async throws -> (userId: String, tenantId: String?, role: String?)
    func signOut() throws
}

// MARK: - AuthError

enum AuthError: Error, Sendable {
    case viewControllerNotFound
    case googleIdTokenMissing
}

// MARK: - FirebaseGoogleAuthProvider

final class FirebaseGoogleAuthProvider: AuthProviding {
    @MainActor
    func signInWithGoogle() async throws -> (userId: String, tenantId: String?, role: String?) {
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
        let tokenResult = try await authResult.user.getIDTokenResult()
        let tenantId = tokenResult.claims["tenantId"] as? String
        let role = tokenResult.claims["role"] as? String

        return (userId: authResult.user.uid, tenantId: tenantId, role: role)
    }

    func signOut() throws {
        GIDSignIn.sharedInstance.signOut()
        try Auth.auth().signOut()
    }
}

// MARK: - AuthViewModel

@Observable
@MainActor
final class AuthViewModel {
    var authState: AuthState = .signedOut
    var isLoading: Bool = false
    var errorMessage: String?

    private let authProvider: AuthProviding
    private nonisolated(unsafe) var authStateHandle: AuthStateDidChangeListenerHandle?

    init(authProvider: AuthProviding = FirebaseGoogleAuthProvider()) {
        self.authProvider = authProvider
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
                errorMessage = "テナント情報の取得に失敗しました。管理者にお問い合わせください。"
                return
            }

            let isAdmin = result.role == "admin"
            authState = .signedIn(userId: result.userId, tenantId: tenantId, isAdmin: isAdmin)
        } catch {
            errorMessage = "サインインに失敗しました: \(error.localizedDescription)"
        }
    }

    /// サインアウトする
    func signOut() {
        do {
            try authProvider.signOut()
        } catch {
            print("[AuthViewModel] signOut failed: \(error.localizedDescription)")
        }
        authState = .signedOut
        errorMessage = nil
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
                    let tokenResult = try? await user.getIDTokenResult()
                    guard let tenantId = tokenResult?.claims["tenantId"] as? String,
                          !tenantId.isEmpty else {
                        self.authState = .signedOut
                        return
                    }
                    let role = tokenResult?.claims["role"] as? String
                    let isAdmin = role == "admin"
                    self.authState = .signedIn(userId: user.uid, tenantId: tenantId, isAdmin: isAdmin)
                } else {
                    self.authState = .signedOut
                }
            }
        }
    }
}
