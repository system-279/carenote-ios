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

    private let audioRecorder: any AudioRecording
    private var timerTask: Task<Void, Never>?
    private var accumulatedTime: TimeInterval = 0

    init(clientId: String, clientName: String, scene: RecordingScene, audioRecorder: any AudioRecording = AudioRecorderService()) {
        self.clientId = clientId
        self.clientName = clientName
        self.scene = scene
        self.audioRecorder = audioRecorder
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
            accumulatedTime = 0
            errorMessage = nil
            startTimer()
        } catch {
            errorMessage = "録音の開始に失敗しました: \(error.localizedDescription)"
            throw error
        }
    }

    /// 録音を一時停止する
    @MainActor
    func pauseRecording() async throws {
        guard recordingState == .recording else { return }

        do {
            try await audioRecorder.pauseRecording()
            recordingState = .paused
            accumulatedTime = elapsedTime
            stopTimer()
        } catch {
            errorMessage = "一時停止に失敗しました: \(error.localizedDescription)"
            throw error
        }
    }

    /// 録音を再開する
    @MainActor
    func resumeRecording() async throws {
        guard recordingState == .paused else { return }

        do {
            try await audioRecorder.resumeRecording()
            recordingState = .recording
            startTimer()
        } catch {
            errorMessage = "録音の再開に失敗しました: \(error.localizedDescription)"
            throw error
        }
    }

    /// 録音を停止する
    @MainActor
    func stopRecording() async throws {
        guard recordingState == .recording || recordingState == .paused else { return }

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
        formatMMSS(elapsedTime)
    }

    // MARK: - Private

    @MainActor
    private func startTimer() {
        stopTimer()
        let startTime = Date()
        let baseTime = accumulatedTime
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { break }
                if let self {
                    self.elapsedTime = baseTime + Date().timeIntervalSince(startTime)
                }
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }
}
