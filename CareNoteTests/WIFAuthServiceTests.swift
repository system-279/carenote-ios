@testable import CareNote
import Foundation
import Testing

// MARK: - WIFAuthService Tests

@Suite("WIFAuthService Tests", .serialized)
struct WIFAuthServiceTests {

    // MARK: - STS Response Helper

    private func makeSTSResponseData() -> Data {
        """
        {
            "access_token": "sts-token-123",
            "issued_token_type": "urn:ietf:params:oauth:token-type:access_token",
            "token_type": "Bearer",
            "expires_in": 3600
        }
        """.data(using: .utf8)!
    }

    private func makeImpersonationResponseData(
        accessToken: String = "gcp-access-token-456",
        expireTime: String? = nil
    ) -> Data {
        let expire = expireTime ?? ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600))
        return """
        {
            "accessToken": "\(accessToken)",
            "expireTime": "\(expire)"
        }
        """.data(using: .utf8)!
    }

    private func makeService() -> WIFAuthService {
        let config = WIFAuthConfig(
            projectNumber: "123456",
            poolId: "test-pool",
            providerId: "test-provider",
            serviceAccountEmail: "sa@test.iam.gserviceaccount.com"
        )
        return WIFAuthService(config: config, urlSession: makeMockURLSession())
    }

    // MARK: - STS Token Exchange Tests

    @Test
    func STSとImpersonationの正常レスポンスが正しくデコードされる() throws {
        // STS response
        let stsData = makeSTSResponseData()
        let stsResponse = try JSONDecoder().decode(STSResponse.self, from: stsData)
        #expect(stsResponse.accessToken == "sts-token-123")
        #expect(stsResponse.tokenType == "Bearer")
        #expect(stsResponse.expiresIn == 3600)

        // Impersonation response
        let impData = makeImpersonationResponseData()
        let impResponse = try JSONDecoder().decode(ImpersonationResponse.self, from: impData)
        #expect(impResponse.accessToken == "gcp-access-token-456")
        #expect(ISO8601DateFormatter().date(from: impResponse.expireTime) != nil)
    }

    @Test
    func STSResponse_デコード正常系() throws {
        let json = """
        {
            "access_token": "test-sts-token",
            "issued_token_type": "urn:ietf:params:oauth:token-type:access_token",
            "token_type": "Bearer",
            "expires_in": 1800
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(STSResponse.self, from: json)
        #expect(response.accessToken == "test-sts-token")
        #expect(response.issuedTokenType == "urn:ietf:params:oauth:token-type:access_token")
        #expect(response.tokenType == "Bearer")
        #expect(response.expiresIn == 1800)
    }

    @Test
    func STSResponse_CodingKeys正しい() throws {
        // Verify snake_case JSON keys map to camelCase properties
        let json = """
        {
            "access_token": "tk",
            "issued_token_type": "itt",
            "token_type": "tt",
            "expires_in": 60
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(STSResponse.self, from: json)
        #expect(response.accessToken == "tk")
        #expect(response.issuedTokenType == "itt")
    }

    @Test
    func STSResponse_不正JSONでデコードエラー() {
        let invalidJSON = "not json".data(using: .utf8)!
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(STSResponse.self, from: invalidJSON)
        }
    }

    // MARK: - ImpersonationResponse Tests

    @Test
    func ImpersonationResponse_デコード正常系() throws {
        let json = """
        {
            "accessToken": "gcp-token-abc",
            "expireTime": "2026-03-31T12:00:00Z"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ImpersonationResponse.self, from: json)
        #expect(response.accessToken == "gcp-token-abc")
        #expect(response.expireTime == "2026-03-31T12:00:00Z")
    }

    @Test
    func ImpersonationResponse_ISO8601日付パース成功() throws {
        let expireTime = "2026-04-01T00:00:00Z"
        let json = """
        {
            "accessToken": "token",
            "expireTime": "\(expireTime)"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ImpersonationResponse.self, from: json)
        let date = ISO8601DateFormatter().date(from: response.expireTime)
        #expect(date != nil)
    }

    @Test
    func ImpersonationResponse_不正expireTimeでも文字列としてデコード可能() throws {
        // expireTime is a String field, so invalid date strings still decode
        let json = """
        {
            "accessToken": "token",
            "expireTime": "not-a-date"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ImpersonationResponse.self, from: json)
        #expect(response.expireTime == "not-a-date")
        // But ISO8601 parsing should fail
        let date = ISO8601DateFormatter().date(from: response.expireTime)
        #expect(date == nil)
    }

    // MARK: - WIFError Tests

    @Test
    func WIFError_notAuthenticated() {
        let error = WIFError.notAuthenticated
        #expect(error is WIFError)
    }

    @Test
    func WIFError_tokenExchangeFailed() {
        let error = WIFError.tokenExchangeFailed("HTTP 401: Unauthorized")
        if case .tokenExchangeFailed(let message) = error {
            #expect(message == "HTTP 401: Unauthorized")
        } else {
            Issue.record("Expected tokenExchangeFailed")
        }
    }

    @Test
    func WIFError_impersonationFailed() {
        let error = WIFError.impersonationFailed("HTTP 403: Forbidden")
        if case .impersonationFailed(let message) = error {
            #expect(message == "HTTP 403: Forbidden")
        } else {
            Issue.record("Expected impersonationFailed")
        }
    }

    // MARK: - WIFAuthConfig Tests

    @Test
    func WIFAuthConfig_カスタム設定が保持される() {
        let config = WIFAuthConfig(
            projectNumber: "999",
            poolId: "my-pool",
            providerId: "my-provider",
            serviceAccountEmail: "test@sa.iam.gserviceaccount.com"
        )
        #expect(config.projectNumber == "999")
        #expect(config.poolId == "my-pool")
        #expect(config.providerId == "my-provider")
        #expect(config.serviceAccountEmail == "test@sa.iam.gserviceaccount.com")
    }
}
