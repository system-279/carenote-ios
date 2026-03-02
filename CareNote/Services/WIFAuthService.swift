import FirebaseAuth
import Foundation

// MARK: - WIFError

enum WIFError: Error, Sendable {
    case notAuthenticated
    case tokenExchangeFailed(String)
    case impersonationFailed(String)
}

// MARK: - WIF Response Models

struct STSResponse: Codable, Sendable {
    let accessToken: String
    let issuedTokenType: String
    let tokenType: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case issuedTokenType = "issued_token_type"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

struct ImpersonationResponse: Codable, Sendable {
    let accessToken: String
    let expireTime: String
}

// MARK: - WIFAuthConfig

struct WIFAuthConfig: Sendable {
    let projectNumber: String
    let poolId: String
    let providerId: String
    let serviceAccountEmail: String

    static var `default`: WIFAuthConfig {
        WIFAuthConfig(
            projectNumber: AppConfig.gcpProjectNumber,
            poolId: "carenote-pool",
            providerId: "carenote-firebase-provider",
            serviceAccountEmail: AppConfig.serviceAccountEmail
        )
    }
}

// MARK: - WIFAuthService

/// Workload Identity Federation authentication service (Spec S10).
///
/// Flow: Firebase ID Token -> STS Token Exchange -> SA Impersonation
actor WIFAuthService {

    // MARK: - Properties

    private let config: WIFAuthConfig
    private let urlSession: URLSession

    private var cachedAccessToken: String?
    private var tokenExpiration: Date?

    // MARK: - Endpoints

    private var stsEndpoint: URL {
        URL(string: "https://sts.googleapis.com/v1/token")!
    }

    private var impersonationEndpoint: URL {
        let sa = config.serviceAccountEmail
        return URL(
            string: "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/\(sa):generateAccessToken"
        )!
    }

    // MARK: - Initialization

    init(config: WIFAuthConfig = .default, urlSession: URLSession = .shared) {
        self.config = config
        self.urlSession = urlSession
    }

    // MARK: - Public Methods

    /// Obtain a GCP access token via Workload Identity Federation.
    /// Caches the token and refreshes when expired.
    func getAccessToken() async throws -> String {
        // Return cached token if still valid
        if let token = cachedAccessToken,
           let expiration = tokenExpiration,
           Date() < expiration.addingTimeInterval(-60)
        {
            return token
        }

        // Step 1: Get Firebase ID token
        let firebaseToken = try await getFirebaseIDToken()

        // Step 2: Exchange for STS token
        let stsResponse = try await exchangeToken(firebaseIDToken: firebaseToken)

        // Step 3: Impersonate service account
        let impersonationResponse = try await impersonateServiceAccount(stsToken: stsResponse.accessToken)

        // Cache the token
        cachedAccessToken = impersonationResponse.accessToken
        if let expireDate = ISO8601DateFormatter().date(from: impersonationResponse.expireTime) {
            tokenExpiration = expireDate
        } else {
            // Default to 55 minutes if parsing fails
            tokenExpiration = Date().addingTimeInterval(55 * 60)
        }

        return impersonationResponse.accessToken
    }

    // MARK: - Step 1: Firebase ID Token

    private func getFirebaseIDToken() async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw WIFError.notAuthenticated
        }

        do {
            let token = try await user.getIDToken()
            return token
        } catch {
            throw WIFError.notAuthenticated
        }
    }

    // MARK: - Step 2: STS Token Exchange

    private func exchangeToken(firebaseIDToken: String) async throws -> STSResponse {
        let audience = "//iam.googleapis.com/projects/\(config.projectNumber)/locations/global/workloadIdentityPools/\(config.poolId)/providers/\(config.providerId)"

        let body: [String: String] = [
            "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange",
            "audience": audience,
            "scope": "https://www.googleapis.com/auth/cloud-platform",
            "requested_token_type": "urn:ietf:params:oauth:token-type:access_token",
            "subject_token_type": "urn:ietf:params:oauth:token-type:jwt",
            "subject_token": firebaseIDToken,
        ]

        var request = URLRequest(url: stsEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode)
        else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "Unknown"
            throw WIFError.tokenExchangeFailed("HTTP \(statusCode): \(body)")
        }

        do {
            return try JSONDecoder().decode(STSResponse.self, from: data)
        } catch {
            throw WIFError.tokenExchangeFailed("Decode error: \(error.localizedDescription)")
        }
    }

    // MARK: - Step 3: Service Account Impersonation

    private func impersonateServiceAccount(stsToken: String) async throws -> ImpersonationResponse {
        let body: [String: Any] = [
            "scope": ["https://www.googleapis.com/auth/cloud-platform"],
            "lifetime": "3600s",
        ]

        var request = URLRequest(url: impersonationEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(stsToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode)
        else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "Unknown"
            throw WIFError.impersonationFailed("HTTP \(statusCode): \(body)")
        }

        do {
            return try JSONDecoder().decode(ImpersonationResponse.self, from: data)
        } catch {
            throw WIFError.impersonationFailed("Decode error: \(error.localizedDescription)")
        }
    }
}
