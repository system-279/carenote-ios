@testable import CareNote
import Foundation
import SwiftData
import Testing

// MARK: - Mock AccessTokenProvider

private actor StubAccessTokenProvider: AccessTokenProviding {
    func getAccessToken() async throws -> String {
        "mock-token"
    }
}

@Suite("OutboxSyncService incrementRetryCount Tests")
struct OutboxSyncServiceTests {

    private static func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: RecordingRecord.self, OutboxItem.self, ClientCache.self, OutputTemplate.self,
            configurations: config
        )
    }

    private static func makeService(container: ModelContainer) -> OutboxSyncService {
        let tokenProvider = StubAccessTokenProvider()
        return OutboxSyncService(
            modelContainer: container,
            storageService: StorageService(
                bucketName: "test-bucket",
                accessTokenProvider: tokenProvider
            ),
            firestoreService: FirestoreService(),
            transcriptionService: TranscriptionService(
                projectId: "test-project",
                accessTokenProvider: tokenProvider
            ),
            tenantId: "test-tenant"
        )
    }

    @Test @MainActor
    func incrementRetryCountで通常時はretryCount増加のみ() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let service = Self.makeService(container: container)

        let recordingId = UUID()
        let recording = RecordingRecord(
            id: recordingId,
            clientId: "client-1",
            clientName: "テスト利用者",
            scene: RecordingScene.visit.rawValue,
            localAudioPath: "/tmp/test.m4a"
        )
        context.insert(recording)

        let item = OutboxItem(recordingId: recordingId, retryCount: 0)
        context.insert(item)
        try context.save()

        await service.incrementRetryCount(item.id)

        #expect(item.retryCount == 1)
        #expect(recording.uploadStatus == UploadStatus.pending.rawValue)
        #expect(recording.transcriptionStatus == TranscriptionStatus.pending.rawValue)
    }

    @Test @MainActor
    func incrementRetryCountでmax超過時にステータスがerrorになる() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let service = Self.makeService(container: container)

        let recordingId = UUID()
        let recording = RecordingRecord(
            id: recordingId,
            clientId: "client-1",
            clientName: "テスト利用者",
            scene: RecordingScene.visit.rawValue,
            localAudioPath: "/tmp/test.m4a"
        )
        context.insert(recording)

        // retryCount=2 → increment で 3 に到達（maxRetryCount=3）
        let item = OutboxItem(recordingId: recordingId, retryCount: 2)
        context.insert(item)
        try context.save()

        await service.incrementRetryCount(item.id)

        #expect(item.retryCount == 3)
        #expect(recording.uploadStatus == UploadStatus.error.rawValue)
        #expect(recording.transcriptionStatus == TranscriptionStatus.error.rawValue)
    }

    @Test @MainActor
    func incrementRetryCountでtranscriptionStatusがdoneの場合は変更しない() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let service = Self.makeService(container: container)

        let recordingId = UUID()
        let recording = RecordingRecord(
            id: recordingId,
            clientId: "client-1",
            clientName: "テスト利用者",
            scene: RecordingScene.visit.rawValue,
            localAudioPath: "/tmp/test.m4a",
            uploadStatus: UploadStatus.pending.rawValue,
            transcriptionStatus: TranscriptionStatus.done.rawValue
        )
        context.insert(recording)

        let item = OutboxItem(recordingId: recordingId, retryCount: 2)
        context.insert(item)
        try context.save()

        await service.incrementRetryCount(item.id)

        #expect(recording.uploadStatus == UploadStatus.error.rawValue)
        #expect(recording.transcriptionStatus == TranscriptionStatus.done.rawValue)
    }
}
