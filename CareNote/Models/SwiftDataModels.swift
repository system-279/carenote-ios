import Foundation
import SwiftData

// MARK: - RecordingRecord

@Model
final class RecordingRecord {
    @Attribute(.unique)
    var id: UUID

    var clientId: String
    var clientName: String
    var scene: String
    var recordedAt: Date
    var durationSeconds: Double
    var localAudioPath: String
    var firestoreId: String?
    var uploadStatus: String
    var transcription: String?
    var transcriptionStatus: String

    init(
        id: UUID = UUID(),
        clientId: String,
        clientName: String,
        scene: String,
        recordedAt: Date = Date(),
        durationSeconds: Double = 0,
        localAudioPath: String,
        firestoreId: String? = nil,
        uploadStatus: String = UploadStatus.pending.rawValue,
        transcription: String? = nil,
        transcriptionStatus: String = TranscriptionStatus.pending.rawValue
    ) {
        self.id = id
        self.clientId = clientId
        self.clientName = clientName
        self.scene = scene
        self.recordedAt = recordedAt
        self.durationSeconds = durationSeconds
        self.localAudioPath = localAudioPath
        self.firestoreId = firestoreId
        self.uploadStatus = uploadStatus
        self.transcription = transcription
        self.transcriptionStatus = transcriptionStatus
    }
}

// MARK: - ClientCache

@Model
final class ClientCache {
    @Attribute(.unique)
    var id: String

    var name: String
    var furigana: String
    var cachedAt: Date

    init(
        id: String,
        name: String,
        furigana: String,
        cachedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.furigana = furigana
        self.cachedAt = cachedAt
    }
}

extension ClientCache: Hashable {
    static func == (lhs: ClientCache, rhs: ClientCache) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - OutboxItem

@Model
final class OutboxItem {
    @Attribute(.unique)
    var id: UUID

    var recordingId: UUID
    var createdAt: Date
    var retryCount: Int

    init(
        id: UUID = UUID(),
        recordingId: UUID,
        createdAt: Date = Date(),
        retryCount: Int = 0
    ) {
        self.id = id
        self.recordingId = recordingId
        self.createdAt = createdAt
        self.retryCount = retryCount
    }
}
