import Foundation
import os.log

// MARK: - UserRole

enum UserRole: String, Sendable, Codable {
    case admin
    case member

    static func from(firestoreValue string: String?) -> UserRole {
        (string == "admin") ? .admin : .member
    }
}

// MARK: - FirestoreRecording

struct FirestoreRecording: Codable, Sendable, Identifiable {
    var id: String?
    let clientId: String
    let clientName: String
    let scene: String
    let recordedAt: Date
    let durationSeconds: Double
    let audioStoragePath: String?
    let transcription: String?
    let transcriptionStatus: String
    let createdBy: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, clientId, clientName, scene, recordedAt, durationSeconds
        case audioStoragePath, transcription, transcriptionStatus
        case createdBy, createdAt, updatedAt
    }
}

// MARK: - FirestoreClient

struct FirestoreClient: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let furigana: String

    enum CodingKeys: String, CodingKey {
        case id, name, furigana
    }
}

// MARK: - FirestoreMember

struct FirestoreMember: Codable, Sendable, Identifiable {
    let id: String?
    let name: String
    let role: UserRole
    let createdAt: Date
}

// MARK: - FirestoreTemplate

struct FirestoreTemplate: Codable, Sendable, Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let prompt: String
    let outputType: OutputType
    let createdBy: String
    let createdByName: String
    let createdAt: Date
    let updatedAt: Date
}

// MARK: - TemplateItem

/// 録音確認画面でプリセット・テナント共有・個人テンプレートを統一的に扱うための型
struct TemplateItem: Identifiable, Equatable, Sendable {
    private static let logger = Logger(subsystem: "jp.carenote.app", category: "TemplateItem")
    enum Source: String, Sendable, Equatable {
        case preset
        case tenant
        case personal
    }

    /// Identifiable用の一意キー（source + rawId の組み合わせ）
    var id: String { "\(source.rawValue):\(rawId)" }
    let rawId: String
    let name: String
    let prompt: String
    let outputType: OutputType
    let source: Source
    /// OutputTemplate の UUID（個人・プリセット時のみ。RecordingRecord.templateId 保存用）
    let localTemplateId: UUID?

    init(from local: OutputTemplate) {
        self.rawId = local.id.uuidString
        self.name = local.name
        self.prompt = local.prompt
        if let type = OutputType(rawValue: local.outputType) ?? OutputType.fromLegacy(local.outputType) {
            self.outputType = type
        } else {
            Self.logger.error("TemplateItem: unrecognized outputType '\(local.outputType)' for template \(local.id), falling back to .custom")
            self.outputType = .custom
        }
        self.source = local.isPreset ? .preset : .personal
        self.localTemplateId = local.id
    }

    init(from remote: FirestoreTemplate) {
        self.rawId = remote.id
        self.name = remote.name
        self.prompt = remote.prompt
        self.outputType = remote.outputType
        self.source = .tenant
        self.localTemplateId = nil
    }
}

// MARK: - WhitelistEntry

struct WhitelistEntry: Sendable, Identifiable {
    let id: String
    let email: String
    let role: UserRole
    let addedBy: String
    let addedAt: Date
}
