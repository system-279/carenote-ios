import Foundation

// MARK: - AppConfig

struct AppConfig: Sendable {
    nonisolated(unsafe) static var current: AppEnvironment = .dev

    static var gcpProject: String {
        switch current {
        case .dev: return "carenote-dev-279"
        case .prod: return "carenote-prod-279"
        }
    }

    static var gcpProjectNumber: String {
        switch current {
        case .dev: return "444137368705"
        case .prod: return "781674225072"
        }
    }

    static var serviceAccountEmail: String {
        return "carenote-ios-client@\(gcpProject).iam.gserviceaccount.com"
    }

    static var storageBucket: String {
        return "\(gcpProject)-audio"
    }
}
