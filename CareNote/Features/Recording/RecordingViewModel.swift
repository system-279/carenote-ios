import Foundation
import Observation

// MARK: - RecordingState

enum RecordingState: Sendable, Equatable {
    case idle
    case recording
    case paused
    case stopped
}

// MARK: - RecordingViewModel

@Observable
final class RecordingViewModel {
    let clientId: String
    let clientName: String
    let scene: RecordingScene

    var recordingState: RecordingState = .idle
    var elapsedTime: TimeInterval = 0
    var audioURL: URL?
    var errorMessage: String?

    private let audioRecorder = AudioRecorderService()
    private var timerTask: Task<Void, Never>?

    init(clientId: String, clientName: String, scene: RecordingScene) {
        self.clientId = clientId
        self.clientName = clientName
        self.scene = scene
    }

    /// 録音を開始する
    @MainActor
    func startRecording() async throws {
        guard recordingState == .idle || recordingState == .stopped else { return }

        do {
            let url = try await audioRecorder.startRecording()
            audioURL = url
            recordingState = .recording
            elapsedTime = 0
            errorMessage = nil
            startTimer()
        } catch {
            errorMessage = "録音の開始に失敗しました: \(error.localizedDescription)"
            throw error
        }
    }

    /// 録音を停止する
    @MainActor
    func stopRecording() async throws {
        guard recordingState == .recording else { return }

        do {
            let result = try await audioRecorder.stopRecording()
            audioURL = result.url
            elapsedTime = result.duration
            recordingState = .stopped
            stopTimer()
        } catch {
            errorMessage = "録音の停止に失敗しました: \(error.localizedDescription)"
            throw error
        }
    }

    /// 経過時間を MM:SS 形式でフォーマットする
    func formatElapsedTime() -> String {
        let totalSeconds = Int(elapsedTime)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Private

    @MainActor
    private func startTimer() {
        stopTimer()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                if let self, let recorder = self.audioRecorder as AudioRecorderService? {
                    self.elapsedTime = await recorder.elapsedTime
                }
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }
}
