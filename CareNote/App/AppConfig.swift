import Foundation

// MARK: - AppConfig

struct AppConfig: Sendable {
    nonisolated(unsafe) static var current: AppEnvironment = .dev

    static var gcpProject: String {
        switch current {
        case .dev: return "carenote-dev"
        case .prod: return "carenote-prod"
        }
    }

    static var gcpProjectNumber: String {
        switch current {
        case .dev: return "YOUR_DEV_PROJECT_NUMBER"
        case .prod: return "YOUR_PROD_PROJECT_NUMBER"
        }
    }

    static var serviceAccountEmail: String {
        return "carenote-ios-client@\(gcpProject).iam.gserviceaccount.com"
    }

    static var storageBucket: String {
        return "\(gcpProject)-audio"
    }
}
