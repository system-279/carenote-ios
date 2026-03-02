import Foundation
import Observation

// MARK: - AppEnvironment

enum AppEnvironment: String, Sendable {
    case dev
    case prod
}

// MARK: - EnvironmentManager

/// AppConfig のラッパー。環境切り替えと環境別の値取得を提供する。
@Observable
final class EnvironmentManager: @unchecked Sendable {
    private(set) var environment: AppEnvironment

    init(environment: AppEnvironment = .dev) {
        self.environment = environment
        AppConfig.current = environment
    }

    func switchEnvironment(to env: AppEnvironment) {
        AppConfig.current = env
    }

    var gcpProject: String { AppConfig.gcpProject }
    var gcpProjectNumber: String { AppConfig.gcpProjectNumber }
    var serviceAccountEmail: String { AppConfig.serviceAccountEmail }
    var storageBucket: String { AppConfig.storageBucket }

    var isProduction: Bool { environment == .prod }
}
