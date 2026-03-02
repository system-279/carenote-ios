import AVFoundation
import Foundation
import Observation

// MARK: - RecordingConfirmViewModel

@Observable
final class RecordingConfirmViewModel {
    let audioURL: URL
    let clientId: String
    let clientName: String
    let scene: RecordingScene
    let duration: TimeInterval

    var isPlaying: Bool = false
    var isSaving: Bool = false
    var playbackProgress: Double = 0
    var errorMessage: String?

    private var audioPlayer: AVAudioPlayer?
    private var playbackTask: Task<Void, Never>?

    init(
        audioURL: URL,
        clientId: String,
        clientName: String,
        scene: RecordingScene,
        duration: TimeInterval
    ) {
        self.audioURL = audioURL
        self.clientId = clientId
        self.clientName = clientName
        self.scene = scene
        self.duration = duration
    }

    /// 録音された音声を再生する
    @MainActor
    func playAudio() async {
        guard !isPlaying else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true)

            audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
            audioPlayer?.play()
            isPlaying = true
            playbackProgress = 0

            startPlaybackTracking()
        } catch {
            errorMessage = "再生に失敗しました: \(error.localizedDescription)"
        }
    }

    /// 再生を停止する
    @MainActor
    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        playbackProgress = 0
        playbackTask?.cancel()
        playbackTask = nil
    }

    /// 録音を保存し文字起こしを開始する
    @MainActor
    func saveAndTranscribe() async throws {
        isSaving = true
        errorMessage = nil

        do {
            // TODO: RecordingRepository に保存
            // TODO: OutboxItem を作成してアップロードキューに追加
            // TODO: Cloud Functions 経由で文字起こし開始

            // MVP: 保存シミュレーション
            try await Task.sleep(for: .seconds(1))

            isSaving = false
        } catch {
            isSaving = false
            errorMessage = "保存に失敗しました: \(error.localizedDescription)"
            throw error
        }
    }

    /// 録音時間を MM:SS 形式でフォーマットする
    var formattedDuration: String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Private

    @MainActor
    private func startPlaybackTracking() {
        playbackTask?.cancel()
        playbackTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self else { break }
                guard let player = self.audioPlayer else {
                    self.isPlaying = false
                    break
                }
                if player.isPlaying {
                    self.playbackProgress = player.duration > 0
                        ? player.currentTime / player.duration
                        : 0
                } else {
                    self.isPlaying = false
                    self.playbackProgress = 0
                    break
                }
            }
        }
    }
}
