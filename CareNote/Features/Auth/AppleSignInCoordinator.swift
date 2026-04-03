import AuthenticationServices
import CryptoKit
@preconcurrency import FirebaseAuth
import os.log

// MARK: - AppleSignInCoordinator

@MainActor
final class AppleSignInCoordinator {
    private static let logger = Logger(subsystem: "jp.carenote.app", category: "AppleSignIn")

    private var currentNonce: String?

    /// SignInWithAppleButton の onRequest で呼び出し、nonce を設定する
    func configureRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    /// SignInWithAppleButton の onCompletion で呼び出し、Firebase Auth と連携する
    func handleResult(_ result: Result<ASAuthorization, Error>) async throws
        -> (userId: String, tenantId: String?, role: UserRole)
    {
        let authorization = try result.get()

        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AuthError.appleIdTokenMissing
        }

        guard let appleIDToken = appleIDCredential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            throw AuthError.appleIdTokenMissing
        }

        guard let nonce = currentNonce else {
            throw AuthError.appleIdTokenMissing
        }

        let credential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: appleIDCredential.fullName
        )

        let authResult = try await Auth.auth().signIn(with: credential)
        let tokenResult = try await authResult.user.getIDTokenResult(forcingRefresh: true)
        let tenantId = tokenResult.claims["tenantId"] as? String
        let role = UserRole.from(firestoreValue: tokenResult.claims["role"] as? String)

        Self.logger.info("Apple Sign-In succeeded: userId=\(authResult.user.uid)")
        return (userId: authResult.user.uid, tenantId: tenantId, role: role)
    }

    // MARK: - Nonce Utilities

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}
