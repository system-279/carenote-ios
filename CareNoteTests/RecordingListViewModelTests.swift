@testable import CareNote
import Foundation
import SwiftData
import Testing

@Suite("RecordingListViewModel Tests", .serialized)
struct RecordingListViewModelTests {

    private static func makeErrorRecording(id: UUID = UUID(), context: ModelContext) -> RecordingRecord {
        let recording = RecordingRecord(
            id: id,
            clientId: "client-1",
            clientName: "テスト利用者",
            scene: RecordingScene.visit.rawValue,
            recordedAt: Date(),
            durationSeconds: 30.0,
            localAudioPath: "/tmp/test.m4a",
            uploadStatus: UploadStatus.error.rawValue,
            transcription: "失敗したテキスト",
            transcriptionStatus: TranscriptionStatus.error.rawValue
        )
        context.insert(recording)
        return recording
    }

    /// Issue #182 delete sync のテストで使う柔軟な fixture。
    /// `firestoreId` / `uploadStatus` / `transcriptionStatus` を test ごとに変える必要がある。
    private static func makeRecording(
        id: UUID = UUID(),
        context: ModelContext,
        firestoreId: String? = nil,
        uploadStatus: UploadStatus = .pending,
        transcription: String? = nil,
        transcriptionStatus: TranscriptionStatus = .pending
    ) -> RecordingRecord {
        let recording = RecordingRecord(
            id: id,
            clientId: "client-1",
            clientName: "テスト利用者",
            scene: RecordingScene.visit.rawValue,
            localAudioPath: "/tmp/test.m4a",
            firestoreId: firestoreId,
            uploadStatus: uploadStatus.rawValue,
            transcription: transcription,
            transcriptionStatus: transcriptionStatus.rawValue
        )
        context.insert(recording)
        return recording
    }

    @Test @MainActor
    func retryRecordingでステータスがpendingにリセットされる() async throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let repo = RecordingRepository(modelContext: context)
        let vm = RecordingListViewModel(recordingRepository: repo)

        let recordingId = UUID()
        let recording = Self.makeErrorRecording(id: recordingId, context: context)

        // エラー状態の OutboxItem を作成（retryCount=3）
        let oldItem = OutboxItem(recordingId: recordingId, retryCount: 3)
        context.insert(oldItem)
        try context.save()

        #expect(recording.uploadStatus == UploadStatus.error.rawValue)
        #expect(recording.transcriptionStatus == TranscriptionStatus.error.rawValue)

        // retryRecording を実行
        try await vm.retryRecording(recording)

        // ステータスが pending にリセットされていること
        #expect(recording.uploadStatus == UploadStatus.pending.rawValue)
        #expect(recording.transcriptionStatus == TranscriptionStatus.pending.rawValue)
        #expect(recording.transcription == nil)

        // OutboxItem が retryCount=0 で再作成されていること
        let descriptor = FetchDescriptor<OutboxItem>(
            predicate: #Predicate { $0.recordingId == recordingId }
        )
        let items = try context.fetch(descriptor)
        #expect(items.count == 1)
        #expect(items.first?.retryCount == 0)
    }

    @Test @MainActor
    func saveTranscriptionでテキストがSwiftDataに保存される() async throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let repo = RecordingRepository(modelContext: context)
        let vm = RecordingListViewModel(recordingRepository: repo)

        let recording = RecordingRecord(
            id: UUID(),
            clientId: "client-1",
            clientName: "テスト利用者",
            scene: RecordingScene.visit.rawValue,
            localAudioPath: "/tmp/test.m4a",
            transcription: "元のテキスト",
            transcriptionStatus: TranscriptionStatus.done.rawValue
        )
        context.insert(recording)
        try context.save()

        try await vm.saveTranscription(recording, text: "修正後のテキスト")

        #expect(recording.transcription == "修正後のテキスト")

        // SwiftData に永続化されていることを確認
        let fetched = try repo.findById(recording.id)
        #expect(fetched?.transcription == "修正後のテキスト")
    }

    @Test @MainActor
    func deleteRecordingでリストから除外される() async throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let repo = RecordingRepository(modelContext: context)
        let vm = RecordingListViewModel(recordingRepository: repo)

        let recording = Self.makeErrorRecording(context: context)
        try context.save()

        // loadRecordings でリストに読み込む
        await vm.loadRecordings()
        #expect(vm.recordings.count == 1)

        // 削除
        try await vm.deleteRecording(recording)
        #expect(vm.recordings.isEmpty)
    }

    // MARK: - Issue #182 delete Firestore sync

    /// AC4/AC9-1: firestoreId == nil (Outbox 未処理の新規録音) は Firestore を呼ばず local のみ削除する。
    /// AC6: 関連 OutboxItem も cascade で削除されること（RecordingRepository.delete の既存挙動）を検証。
    @Test @MainActor
    func deleteRecording_firestoreIdなしなら_ローカルのみ削除されFirestoreは呼ばれない() async throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let repo = RecordingRepository(modelContext: context)
        // firestoreService 未指定 = nil。firestoreId == nil パスなので Firestore は呼ばれない
        let vm = RecordingListViewModel(recordingRepository: repo)

        let recordingId = UUID()
        _ = Self.makeRecording(id: recordingId, context: context, firestoreId: nil)
        // AC6: OutboxItem を同時投入し、cascade 削除されることを検証
        context.insert(OutboxItem(recordingId: recordingId))
        try context.save()

        await vm.loadRecordings()
        #expect(vm.recordings.count == 1)

        // fetch and delete the same instance from the test's view (loadRecordings may replace)
        let target = try #require(try repo.findById(recordingId))
        try await vm.deleteRecording(target)

        // ローカルから削除されている
        #expect(vm.recordings.isEmpty)
        #expect(try repo.findById(recordingId) == nil)

        // AC6: 関連 OutboxItem も削除されている（RecordingRepository.delete の cascade）
        let outboxDescriptor = FetchDescriptor<OutboxItem>(
            predicate: #Predicate { $0.recordingId == recordingId }
        )
        #expect(try context.fetch(outboxDescriptor).isEmpty)
    }

    /// AC5/AC9-2: firestoreId != nil で firestoreService == nil の場合、
    /// local-only 削除を行わず fail させる（Issue #182 再発防止）。
    /// 同期済み録音を local だけ消すと「再読込で復活」が再発するため。
    /// AC6: guard 発動時は OutboxItem も削除せず保持されること。
    @Test @MainActor
    func deleteRecording_同期済みなのにfirestoreServiceなしならエラー投げローカルは残す() async throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let repo = RecordingRepository(modelContext: context)
        let vm = RecordingListViewModel(
            recordingRepository: repo,
            firestoreService: nil,
            tenantId: "tenant-1"
        )

        let recordingId = UUID()
        let recording = Self.makeRecording(
            id: recordingId,
            context: context,
            firestoreId: "firestore-doc-abc",
            uploadStatus: .done,
            transcription: "文字起こし結果",
            transcriptionStatus: .done
        )
        // AC6: guard throw 時に cascade 削除が走らないことを検証するため OutboxItem も投入
        context.insert(OutboxItem(recordingId: recordingId))
        try context.save()

        await #expect(throws: RecordingDeleteError.self) {
            try await vm.deleteRecording(recording)
        }

        // ローカル側は削除されずに残っている（再読込復活防止のガード）
        #expect(try repo.findById(recordingId) != nil)

        // AC6: 関連 OutboxItem も残っている（guard throw は cascade 削除も止める）
        let outboxDescriptor = FetchDescriptor<OutboxItem>(
            predicate: #Predicate { $0.recordingId == recordingId }
        )
        #expect(try context.fetch(outboxDescriptor).count == 1)
    }

    /// AC5/AC9-3: firestoreId != nil で tenantId == nil の場合も fail。
    @Test @MainActor
    func deleteRecording_同期済みなのにtenantIdなしならエラー投げローカルは残す() async throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let repo = RecordingRepository(modelContext: context)
        // firestoreService は non-nil だが tenantId == nil のケース。
        // guard は `let firestoreService, let tenantId, !tenantId.isEmpty` の順で左から
        // 評価されるため、firestoreService の non-nil check は通り、tenantId の non-nil
        // check で fail する。この test path では `db` プロパティへアクセスしないため
        // Firebase の接続は発生しない（FirestoreService.init は _firestore の格納のみ）。
        let firestore = FirestoreService()
        let vm = RecordingListViewModel(
            recordingRepository: repo,
            firestoreService: firestore,
            tenantId: nil
        )

        let recordingId = UUID()
        let recording = Self.makeRecording(
            id: recordingId,
            context: context,
            firestoreId: "firestore-doc-xyz",
            uploadStatus: .done
        )
        try context.save()

        await #expect(throws: RecordingDeleteError.self) {
            try await vm.deleteRecording(recording)
        }

        #expect(try repo.findById(recordingId) != nil)
    }

    /// AC5: firestoreId != nil で tenantId が空文字列の場合も fail。
    /// Firebase Auth の custom claim 未反映 / signin 直後の race 対策。
    @Test @MainActor
    func deleteRecording_同期済みなのにtenantIdが空文字ならエラー投げローカルは残す() async throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let repo = RecordingRepository(modelContext: context)
        let firestore = FirestoreService()
        let vm = RecordingListViewModel(
            recordingRepository: repo,
            firestoreService: firestore,
            tenantId: ""
        )

        let recordingId = UUID()
        let recording = Self.makeRecording(
            id: recordingId,
            context: context,
            firestoreId: "firestore-doc-empty-tenant",
            uploadStatus: .done
        )
        try context.save()

        await #expect(throws: RecordingDeleteError.self) {
            try await vm.deleteRecording(recording)
        }

        #expect(try repo.findById(recordingId) != nil)
    }
}
