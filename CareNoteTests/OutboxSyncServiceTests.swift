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
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftdata-test-\(UUID().uuidString).sqlite")
        let config = ModelConfiguration(url: url)
        return try ModelContainer(
            for: RecordingRecord.self, OutboxItem.self, ClientCache.self, OutputTemplate.self,
            configurations: config
        )
    }

    private static func makeService(
        container: ModelContainer,
        currentUidProvider: @escaping @Sendable () -> String? = { "test-uid" }
    ) -> OutboxSyncService {
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
            tenantId: "test-tenant",
            currentUidProvider: currentUidProvider
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

    // MARK: - createdBy / uid Tests

    @Test @MainActor
    func buildFirestoreRecordingでcurrentUidProviderが返すuidがcreatedByに入る() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let service = Self.makeService(
            container: container,
            currentUidProvider: { "expected-uid-123" }
        )

        let recordingId = UUID()
        let recording = RecordingRecord(
            id: recordingId,
            clientId: "client-1",
            clientName: "テスト利用者",
            scene: RecordingScene.visit.rawValue,
            localAudioPath: "/tmp/test.m4a"
        )
        context.insert(recording)
        try context.save()

        let result = try await service.buildFirestoreRecording(
            recordingId: recordingId,
            gcsUri: "gs://test-bucket/test.m4a"
        )

        #expect(result.createdBy == "expected-uid-123")
        #expect(!result.createdBy.isEmpty)
    }

    @Test @MainActor
    func buildFirestoreRecordingでuidが取れない場合はuserNotAuthenticatedエラー() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let service = Self.makeService(
            container: container,
            currentUidProvider: { nil }
        )

        let recordingId = UUID()
        let recording = RecordingRecord(
            id: recordingId,
            clientId: "client-1",
            clientName: "テスト利用者",
            scene: RecordingScene.visit.rawValue,
            localAudioPath: "/tmp/test.m4a"
        )
        context.insert(recording)
        try context.save()

        await #expect(throws: OutboxSyncError.self) {
            _ = try await service.buildFirestoreRecording(
                recordingId: recordingId,
                gcsUri: "gs://test-bucket/test.m4a"
            )
        }
    }

    @Test @MainActor
    func buildFirestoreRecordingでuidが空文字の場合もuserNotAuthenticatedエラー() async throws {
        // issue #99 二段防御の境界値テスト: nil と空文字を独立にカバー。
        // `currentUidProvider` が non-nil な空文字を返しても createdBy は保存されない。
        let container = try Self.makeContainer()
        let context = container.mainContext
        let service = Self.makeService(
            container: container,
            currentUidProvider: { "" }
        )

        let recordingId = UUID()
        let recording = RecordingRecord(
            id: recordingId,
            clientId: "client-1",
            clientName: "テスト利用者",
            scene: RecordingScene.visit.rawValue,
            localAudioPath: "/tmp/test.m4a"
        )
        context.insert(recording)
        try context.save()

        await #expect(throws: OutboxSyncError.self) {
            _ = try await service.buildFirestoreRecording(
                recordingId: recordingId,
                gcsUri: "gs://test-bucket/test.m4a"
            )
        }
    }

    @Test @MainActor
    func buildFirestoreRecordingで更新対象外フィールドは既存値を保持する() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let service = Self.makeService(
            container: container,
            currentUidProvider: { "uid-xyz" }
        )

        let recordingId = UUID()
        let recordedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let recording = RecordingRecord(
            id: recordingId,
            clientId: "client-A",
            clientName: "山田太郎",
            scene: RecordingScene.assessment.rawValue,
            recordedAt: recordedAt,
            durationSeconds: 123.45,
            localAudioPath: "/tmp/test.m4a"
        )
        context.insert(recording)
        try context.save()

        let result = try await service.buildFirestoreRecording(
            recordingId: recordingId,
            gcsUri: "gs://test-bucket/test.m4a"
        )

        #expect(result.clientId == "client-A")
        #expect(result.clientName == "山田太郎")
        #expect(result.scene == RecordingScene.assessment.rawValue)
        #expect(result.recordedAt == recordedAt)
        #expect(result.durationSeconds == 123.45)
        #expect(result.audioStoragePath == "gs://test-bucket/test.m4a")
        #expect(result.createdBy == "uid-xyz")
    }
}
