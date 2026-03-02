import Foundation

// MARK: - RecordingScene

enum RecordingScene: String, CaseIterable, Codable, Identifiable, Sendable {
    case visit = "訪問"
    case meeting = "担当者会議"
    case phone = "電話"
    case conference = "カンファレンス"
    case intake = "インテーク"
    case assessment = "アセスメント"
    case other = "その他"

    var id: String { rawValue }

    var documentType: String {
        switch self {
        case .visit: return "訪問記録"
        case .meeting: return "担当者会議録"
        case .phone: return "電話連絡記録"
        case .conference: return "カンファレンス記録"
        case .intake: return "インテーク記録"
        case .assessment: return "アセスメント記録"
        case .other: return "記録"
        }
    }
}

// MARK: - UploadStatus

enum UploadStatus: String, Codable, Sendable {
    case pending
    case uploading
    case done
    case error
}

// MARK: - TranscriptionStatus

enum TranscriptionStatus: String, Codable, Sendable {
    case pending
    case processing
    case done
    case error
}
