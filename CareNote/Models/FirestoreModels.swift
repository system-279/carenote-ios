import Foundation

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
    var id: String?
    let name: String
    let role: String
    let createdAt: Date
}

// MARK: - WhitelistEntry

struct WhitelistEntry: Sendable, Identifiable {
    let id: String
    let email: String
    let role: String
    let addedBy: String
    let addedAt: Date
}
