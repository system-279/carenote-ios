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

// MARK: - Mocks for processItem 主経路テスト (issue #107 / I-Cdx-3)

/// 呼び出し履歴を記録する AudioUploading stub。
private actor StubAudioUploader: AudioUploading {
    private(set) var uploadCalls: [(localURL: URL, tenantId: String, recordingId: String)] = []
    var gcsUriToReturn: String = "gs://test-bucket/default.m4a"
    var errorToThrow: Error?

    func uploadAudio(localURL: URL, tenantId: String, recordingId: String) async throws -> String {
        uploadCalls.append((localURL, tenantId, recordingId))
        if let err = errorToThrow { throw err }
        return gcsUriToReturn
    }

    func setGcsUri(_ uri: String) { gcsUriToReturn = uri }
    func setError(_ error: Error) { errorToThrow = error }
}

/// 汎用テスト用エラー（stub injection 用）。
private struct TestInjectedError: Error, Equatable {
    let label: String
}

/// 呼び出し履歴を記録する RecordingStoring stub。
private actor StubRecordingStore: RecordingStoring {
    private(set) var createCalls: [FirestoreRecording] = []
    private(set) var updateTranscriptionCalls: [(recordingId: String, status: TranscriptionStatus)] = []
    var firestoreIdToReturn: String = "firestore-id-stub"

    func createRecording(tenantId: String, recording: FirestoreRecording) async throws -> String {
        createCalls.append(recording)
        return firestoreIdToReturn
    }

    func updateTranscription(
        tenantId: String,
        recordingId: String,
        transcription: String,
        status: TranscriptionStatus
    ) async throws {
        updateTranscriptionCalls.append((recordingId, status))
    }
}

/// 呼び出し履歴を記録する Transcribing stub。
private actor StubTranscriber: Transcribing {
    private(set) var transcribeCalls: [(audioGCSUri: String, templatePrompt: String?)] = []
    var transcriptionToReturn: String = "mock-transcription"

    func transcribe(audioGCSUri: String, templatePrompt: String?) async throws -> String {
        transcribeCalls.append((audioGCSUri, templatePrompt))
        return transcriptionToReturn
    }
}

@Suite("OutboxSyncService incrementRetryCount Tests", .serialized)
struct OutboxSyncServiceTests {

    private static func makeService(
        container: ModelContainer,
        currentUidProvider: @escaping @Sendable @MainActor () -> String? = { "test-uid" }
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
        let container = try makeTestModelContainer()
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
        let container = try makeTestModelContainer()
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
        let container = try makeTestModelContainer()
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
        let container = try makeTestModelContainer()
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
        let container = try makeTestModelContainer()
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
        let container = try makeTestModelContainer()
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
        let container = try makeTestModelContainer()
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

    // MARK: - processItem 主経路テスト (issue #107 / I-Cdx-3)
    //
    // buildFirestoreRecording 直叩きテストは uid 変換ロジック単体を検証する。
    // 主経路テストは processQueueImmediately 経由で以下を検証する:
    //   - createRecording が呼ばれ createdBy が uid と一致 (AC1 主経路固定)
    //   - uid == nil/"" で uploadAudio が呼ばれない (C-Cdx-1 GCS orphan 防止の回帰)
    //   - Step 順序 (upload → create → transcribe → updateTranscription)

    /// 主経路: uid が取得できる場合に createRecording に createdBy=uid が渡る
    @Test @MainActor
    func processQueueImmediately_主経路_createRecordingに正しいuidが渡る_I_Cdx_3() async throws {
        let (container, audioPath) = try Self.setupContainerWithAudioFile()
        defer { try? FileManager.default.removeItem(atPath: audioPath) }

        let stubUploader = StubAudioUploader()
        await stubUploader.setGcsUri("gs://test-bucket/expected.m4a")
        let stubStore = StubRecordingStore()
        let stubTranscriber = StubTranscriber()

        let service = OutboxSyncService(
            modelContainer: container,
            storageService: stubUploader,
            firestoreService: stubStore,
            transcriptionService: stubTranscriber,
            tenantId: "test-tenant",
            currentUidProvider: { "test-uid-alpha" }
        )

        let recordingId = UUID()
        let context = container.mainContext
        context.insert(RecordingRecord(
            id: recordingId,
            clientId: "client-1",
            clientName: "テスト利用者",
            scene: RecordingScene.visit.rawValue,
            localAudioPath: audioPath
        ))
        context.insert(OutboxItem(recordingId: recordingId))
        try context.save()
        // H4 preflight (Issue #170) — removing this weakens diagnostic for #164-style regressions.
        try Self.assertPreflightState(context: context, audioPath: audioPath)

        try await service.processQueueImmediately()

        let uploadCalls = await stubUploader.uploadCalls
        let createCalls = await stubStore.createCalls
        let transcribeCalls = await stubTranscriber.transcribeCalls

        #expect(uploadCalls.count == 1)
        #expect(uploadCalls.first?.recordingId == recordingId.uuidString)
        #expect(createCalls.count == 1)
        #expect(createCalls.first?.createdBy == "test-uid-alpha")
        #expect(transcribeCalls.count == 1)
        #expect(transcribeCalls.first?.audioGCSUri == "gs://test-bucket/expected.m4a")
    }

    /// 回帰防止 (C-Cdx-1): uid==nil なら pre-flight check で早期 throw し、uploadAudio が呼ばれない
    @Test @MainActor
    func processQueueImmediately_uidNilでuploadAudioが呼ばれない_orphan防止_I_Cdx_3() async throws {
        let (container, audioPath) = try Self.setupContainerWithAudioFile()
        defer { try? FileManager.default.removeItem(atPath: audioPath) }

        let stubUploader = StubAudioUploader()
        let stubStore = StubRecordingStore()
        let stubTranscriber = StubTranscriber()

        let service = OutboxSyncService(
            modelContainer: container,
            storageService: stubUploader,
            firestoreService: stubStore,
            transcriptionService: stubTranscriber,
            tenantId: "test-tenant",
            currentUidProvider: { nil }
        )

        let recordingId = UUID()
        let context = container.mainContext
        context.insert(RecordingRecord(
            id: recordingId,
            clientId: "client-1",
            clientName: "テスト利用者",
            scene: RecordingScene.visit.rawValue,
            localAudioPath: audioPath
        ))
        context.insert(OutboxItem(recordingId: recordingId))
        try context.save()
        // H4 preflight (Issue #170) — removing this weakens diagnostic for #164-style regressions.
        try Self.assertPreflightState(context: context, audioPath: audioPath)

        await #expect(throws: OutboxSyncError.self) {
            try await service.processQueueImmediately()
        }

        let uploadCalls = await stubUploader.uploadCalls
        let createCalls = await stubStore.createCalls
        #expect(uploadCalls.isEmpty, "uid==nil 時は pre-flight check で throw され uploadAudio は呼ばれない (GCS orphan 回避)")
        #expect(createCalls.isEmpty)
    }

    /// 回帰防止 (C-Cdx-1): uid=="" でも pre-flight check で早期 throw し、uploadAudio が呼ばれない
    @Test @MainActor
    func processQueueImmediately_uid空文字でuploadAudioが呼ばれない_orphan防止_I_Cdx_3() async throws {
        let (container, audioPath) = try Self.setupContainerWithAudioFile()
        defer { try? FileManager.default.removeItem(atPath: audioPath) }

        let stubUploader = StubAudioUploader()
        let stubStore = StubRecordingStore()
        let stubTranscriber = StubTranscriber()

        let service = OutboxSyncService(
            modelContainer: container,
            storageService: stubUploader,
            firestoreService: stubStore,
            transcriptionService: stubTranscriber,
            tenantId: "test-tenant",
            currentUidProvider: { "" }
        )

        let recordingId = UUID()
        let context = container.mainContext
        context.insert(RecordingRecord(
            id: recordingId,
            clientId: "client-1",
            clientName: "テスト利用者",
            scene: RecordingScene.visit.rawValue,
            localAudioPath: audioPath
        ))
        context.insert(OutboxItem(recordingId: recordingId))
        try context.save()
        // H4 preflight (Issue #170) — removing this weakens diagnostic for #164-style regressions.
        try Self.assertPreflightState(context: context, audioPath: audioPath)

        await #expect(throws: OutboxSyncError.self) {
            try await service.processQueueImmediately()
        }

        let uploadCalls = await stubUploader.uploadCalls
        let createCalls = await stubStore.createCalls
        #expect(uploadCalls.isEmpty, "uid=='' 時も pre-flight check で throw され uploadAudio は呼ばれない")
        #expect(createCalls.isEmpty)
    }

    /// 回帰防止 (#145): Step 1 (uploadAudio) が throw した場合、
    /// createRecording / transcribe は呼ばれない。
    /// 将来「Firestore doc 先行作成 → URI 後埋め」構造への変更で Storage 失敗時に
    /// orphan Firestore doc が残る regression を早期に検知する。
    @Test @MainActor
    func processQueueImmediately_upload失敗時_createRecordingが呼ばれない_145() async throws {
        let (container, audioPath) = try Self.setupContainerWithAudioFile()
        defer { try? FileManager.default.removeItem(atPath: audioPath) }

        let stubUploader = StubAudioUploader()
        await stubUploader.setError(TestInjectedError(label: "upload-failed"))
        let stubStore = StubRecordingStore()
        let stubTranscriber = StubTranscriber()

        let service = OutboxSyncService(
            modelContainer: container,
            storageService: stubUploader,
            firestoreService: stubStore,
            transcriptionService: stubTranscriber,
            tenantId: "test-tenant",
            currentUidProvider: { "test-uid-upload-failed" }
        )

        let recordingId = UUID()
        let context = container.mainContext
        context.insert(RecordingRecord(
            id: recordingId,
            clientId: "client-1",
            clientName: "テスト利用者",
            scene: RecordingScene.visit.rawValue,
            localAudioPath: audioPath
        ))
        context.insert(OutboxItem(recordingId: recordingId))
        try context.save()
        // H4 preflight (Issue #170) — removing this weakens diagnostic for #164-style regressions.
        try Self.assertPreflightState(context: context, audioPath: audioPath)

        // OutboxSyncService は原因 error を `OutboxSyncError.uploadFailed(_)` で wrap して throw する。
        await #expect(throws: OutboxSyncError.self) {
            try await service.processQueueImmediately()
        }

        let uploadCalls = await stubUploader.uploadCalls
        let createCalls = await stubStore.createCalls
        let transcribeCalls = await stubTranscriber.transcribeCalls

        #expect(uploadCalls.count == 1, "upload は試行される（pre-flight を通過した後 Step 1 で throw）")
        #expect(createCalls.isEmpty, "upload 失敗時に Firestore doc が先行作成されないこと (orphan 防止)")
        #expect(transcribeCalls.isEmpty, "upload 失敗時は後続 Step の transcribe も実行されないこと")
    }

    // MARK: - Helpers for processItem 主経路テスト

    /// processQueueImmediately 経由テストのセットアップヘルパ。
    /// ダミー音声ファイルを作成し ModelContainer と pair で返す。
    /// - Note: ダミーファイルは OutboxSyncService.processQueueImmediately の
    ///   `FileManager.default.fileExists(atPath:)` ガード（stale item 除外）を
    ///   通過させるために必要。呼出側は `defer { try? FileManager.default.removeItem(atPath:) }`
    ///   でクリーンアップする。
    @MainActor
    private static func setupContainerWithAudioFile() throws -> (ModelContainer, String) {
        let container = try makeTestModelContainer()
        let audioPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-audio-\(UUID().uuidString).m4a").path
        try Data().write(to: URL(fileURLWithPath: audioPath))
        return (container, audioPath)
    }

    /// processQueueImmediately 直前の不変条件を確認する preflight 検査（Issue #170 H4）。
    /// 呼び出しは `try context.save()` の直後、`service.processQueueImmediately()` の直前。
    ///
    /// Fail したら test infra 側（cleanup 残留 / save 未 flush / audio file 欠落）の問題で、
    /// service 実装は無関係と切り分けられる — service 呼出後の assertion が fail した場合は
    /// service 実装（uid 分岐 / upload 順序 / throw 経路）側に絞り込める。
    ///
    /// `SharedTestModelContainer.cleanup()` の stderr diagnostic（PR #185）が CI 環境で
    /// 埋もれても、ここの count 検証で cleanup 残留（count > 1）を捕捉できる backup 経路。
    ///
    /// - Throws: `fetchCount` の失敗時のみ。assertion 失敗は `#expect` 経由で報告されるため
    ///   call site の `try` は fetch error 伝播のみを意味する。fetch error の場合も
    ///   `Issue.record` で「preflight が fetch 段階で壊れた」旨を残してから rethrow する。
    @MainActor
    private static func assertPreflightState(
        context: ModelContext,
        audioPath: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let outboxCount: Int
        let recordingCount: Int
        do {
            outboxCount = try context.fetchCount(FetchDescriptor<OutboxItem>())
            recordingCount = try context.fetchCount(FetchDescriptor<RecordingRecord>())
        } catch {
            Issue.record(
                "Preflight fetch failed — test infra broken (ModelContext unusable before service call): \(error)",
                sourceLocation: sourceLocation
            )
            throw error
        }
        #expect(
            outboxCount == 1,
            "Preflight: OutboxItem count == 1 expected, got \(outboxCount) (cleanup 残留 / save 未 flush)",
            sourceLocation: sourceLocation
        )
        #expect(
            recordingCount == 1,
            "Preflight: RecordingRecord count == 1 expected, got \(recordingCount) (cleanup 残留 / save 未 flush)",
            sourceLocation: sourceLocation
        )
        #expect(
            FileManager.default.fileExists(atPath: audioPath),
            "Preflight: audio file must exist at \(audioPath) (stale-item guard を通過させるため必須)",
            sourceLocation: sourceLocation
        )
    }
}
