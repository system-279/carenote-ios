import Foundation
import Observation
import AuthenticationServices

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
final class AuthViewModel {
    var authState: AuthState = .signedOut
    var isLoading: Bool = false
    var errorMessage: String?

    /// Apple Sign-In を実行し、Firebase Auth と連携する
    @MainActor
    func signInWithApple() async {
        isLoading = true
        errorMessage = nil

        do {
            // TODO: Firebase Auth + Apple Sign-In 実装
            // 1. ASAuthorizationAppleIDProvider でリクエスト生成
            // 2. credential 取得
            // 3. Firebase Auth にサインイン
            // 4. custom claim から tenantId 取得（MVP では仮値）

            // MVP: 仮の認証成功を返す
            try await Task.sleep(for: .milliseconds(500))
            authState = .signedIn(userId: "mock-user-id", tenantId: "mock-tenant-id")
        } catch {
            errorMessage = "サインインに失敗しました: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// サインアウトする
    @MainActor
    func signOut() {
        // TODO: Firebase Auth signOut 実装
        authState = .signedOut
        errorMessage = nil
    }

    /// Firebase Auth の認証状態を監視して authState を更新する
    @MainActor
    func checkAuthState() {
        // TODO: Firebase Auth.auth().addStateDidChangeListener 実装
        // listener 内で authState を更新
        // custom claim から tenantId を取得

        // MVP: サインアウト状態を維持
        authState = .signedOut
    }
}
