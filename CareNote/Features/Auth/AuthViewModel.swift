import FirebaseAuth
import GoogleSignIn
import Observation
import UIKit

// MARK: - AuthState

enum AuthState: Sendable, Equatable {
    case signedOut
    case signedIn(userId: String, tenantId: String)

    var isSignedIn: Bool {
        if case .signedIn = self { return true }
        return false
    }

    var userId: String? {
        if case .signedIn(let userId, _) = self { return userId }
        return nil
    }

    var tenantId: String? {
        if case .signedIn(_, let tenantId) = self { return tenantId }
        return nil
    }
}

// MARK: - AuthViewModel

@Observable
@MainActor
final class AuthViewModel {
    var authState: AuthState = .signedOut
    var isLoading: Bool = false
    var errorMessage: String?

    private nonisolated(unsafe) var authStateHandle: AuthStateDidChangeListenerHandle?

    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    /// Google Sign-In を実行し、Firebase Auth と連携する
    func signInWithGoogle() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.windows.first?.rootViewController else {
                errorMessage = "画面の取得に失敗しました"
                return
            }

            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)

            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = "Google ID Token の取得に失敗しました"
                return
            }

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )

            let authResult = try await Auth.auth().signIn(with: credential)
            let tokenResult = try await authResult.user.getIDTokenResult()

            guard let tenantId = tokenResult.claims["tenantId"] as? String,
                  !tenantId.isEmpty else {
                errorMessage = "テナント情報の取得に失敗しました。管理者にお問い合わせください。"
                return
            }

            authState = .signedIn(userId: authResult.user.uid, tenantId: tenantId)
        } catch {
            errorMessage = "サインインに失敗しました: \(error.localizedDescription)"
        }
    }

    /// サインアウトする
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        do {
            try Auth.auth().signOut()
        } catch {
            print("[AuthViewModel] signOut failed: \(error.localizedDescription)")
        }
        authState = .signedOut
        errorMessage = nil
    }

    /// Firebase Auth の認証状態を監視して authState を更新する
    func checkAuthState() {
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
                    self.authState = .signedIn(userId: user.uid, tenantId: tenantId)
                } else {
                    self.authState = .signedOut
                }
            }
        }
    }
}
