import Foundation

// MARK: - RecordingScene

enum RecordingScene: String, CaseIterable, Codable, Identifiable, Sendable {
    case visit
    case meeting
    case conference
    case intake
    case assessment
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .visit: "訪問"
        case .meeting: "担当者会議"
        case .conference: "カンファレンス"
        case .intake: "インテーク"
        case .assessment: "アセスメント"
        case .other: "その他"
        }
    }

    var documentType: String {
        switch self {
        case .visit: "訪問記録"
        case .meeting: "担当者会議録"
        case .conference: "カンファレンス記録"
        case .intake: "インテーク記録"
        case .assessment: "アセスメント記録"
        case .other: "記録"
        }
    }

    /// 旧rawValue（日本語）からの変換。SwiftData/Firestore既存データの後方互換用
    static func fromLegacy(_ value: String) -> RecordingScene? {
        switch value {
        case "訪問": return .visit
        case "担当者会議": return .meeting
        case "カンファレンス": return .conference
        case "インテーク": return .intake
        case "アセスメント": return .assessment
        case "その他": return .other
        default: return nil
        }
    }

    /// 保存値（英語rawValue or 旧日本語）から表示名を解決する
    static func displayName(forStoredValue value: String) -> String {
        RecordingScene(rawValue: value)?.displayName
            ?? RecordingScene.fromLegacy(value)?.displayName
            ?? value
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

// MARK: - OutputType

enum OutputType: String, CaseIterable, Codable, Sendable, Identifiable {
    case transcription
    case visitRecord
    case meetingMinutes
    case summary
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .transcription: "文字起こし"
        case .visitRecord: "訪問記録"
        case .meetingMinutes: "会議録"
        case .summary: "要約"
        case .custom: "カスタム"
        }
    }

    /// 旧rawValue（日本語）からの変換。SwiftData/Firestore既存データの後方互換用
    static func fromLegacy(_ value: String) -> OutputType? {
        switch value {
        case "文字起こし": return .transcription
        case "訪問記録": return .visitRecord
        case "会議録": return .meetingMinutes
        case "要約": return .summary
        case "カスタム": return .custom
        default: return nil
        }
    }

    /// 保存値（英語rawValue or 旧日本語）から表示名を解決する
    static func displayName(forStoredValue value: String) -> String {
        OutputType(rawValue: value)?.displayName
            ?? OutputType.fromLegacy(value)?.displayName
            ?? value
    }
}
