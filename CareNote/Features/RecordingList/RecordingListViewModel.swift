import Foundation
import Observation
import SwiftData

// MARK: - RecordingListViewModel

@Observable
final class RecordingListViewModel {
    var recordings: [RecordingRecord] = []
    var isLoading: Bool = false
    var errorMessage: String?

    private let recordingRepository: RecordingRepository

    init(recordingRepository: RecordingRepository) {
        self.recordingRepository = recordingRepository
    }

    /// 録音一覧を読み込む
    @MainActor
    func loadRecordings() async {
        isLoading = true
        do {
            recordings = try recordingRepository.fetchAll()
        } catch {
            recordings = []
            errorMessage = "録音の読み込みに失敗しました"
        }
        isLoading = false
    }

    /// 録音の文字起こしを再試行する
    @MainActor
    func retryRecording(_ recording: RecordingRecord) async throws {
        // 既存の OutboxItem を削除して新規作成（retryCount リセット）
        try recordingRepository.resetOutboxItem(for: recording.id)

        // ステータスをリセット
        recording.uploadStatus = UploadStatus.pending.rawValue
        recording.transcriptionStatus = TranscriptionStatus.pending.rawValue
        recording.transcription = nil
        try recordingRepository.save()
    }

    /// 録音を削除する
    @MainActor
    func deleteRecording(_ recording: RecordingRecord) async throws {
        // ローカル音声ファイルを削除
        let audioPath = recording.localAudioPath
        if FileManager.default.fileExists(atPath: audioPath) {
            try? FileManager.default.removeItem(atPath: audioPath)
        }

        // SwiftData から削除（関連 OutboxItem も含む）
        try recordingRepository.delete(recording)

        // リストからも除外
        recordings.removeAll { $0.id == recording.id }
    }
}
