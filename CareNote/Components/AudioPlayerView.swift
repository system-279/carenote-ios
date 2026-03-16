import AVFoundation
import SwiftUI

// MARK: - AudioPlayerView

/// 再利用可能な音声プレーヤーコンポーネント（Slider シーク + 時刻表示 + 再生/停止）
struct AudioPlayerView: View {
    let audioURL: URL

    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var progress: Double = 0
    @State private var currentTime: TimeInterval = 0
    @State private var totalDuration: TimeInterval = 0
    @State private var isDragging = false
    @State private var trackingTask: Task<Void, Never>?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 8) {
            Slider(value: $progress, in: 0...1) { editing in
                isDragging = editing
                if !editing {
                    seekTo(progress: progress)
                }
            }
            .tint(.accentColor)

            HStack {
                Text(formatMMSS(currentTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Spacer()

                Text(formatMMSS(totalDuration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Button {
                if isPlaying {
                    stopPlayback()
                } else {
                    startPlayback()
                }
            } label: {
                Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onDisappear {
            stopPlayback()
        }
    }

    // MARK: - Private

    private func startPlayback() {
        errorMessage = nil
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true)

            let p = try AVAudioPlayer(contentsOf: audioURL)
            p.play()
            player = p
            isPlaying = true
            totalDuration = p.duration
            startTracking()
        } catch {
            errorMessage = "再生に失敗しました"
        }
    }

    private func stopPlayback() {
        trackingTask?.cancel()
        trackingTask = nil
        player?.stop()
        player = nil
        isPlaying = false
        progress = 0
        currentTime = 0
    }

    private func seekTo(progress: Double) {
        guard let player else { return }
        let newTime = player.duration * progress
        player.currentTime = newTime
        currentTime = newTime
    }

    private func startTracking() {
        trackingTask?.cancel()
        trackingTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let player else { break }
                if player.isPlaying {
                    if !isDragging {
                        currentTime = player.currentTime
                        progress = player.duration > 0
                            ? player.currentTime / player.duration
                            : 0
                    }
                } else {
                    isPlaying = false
                    progress = 0
                    currentTime = 0
                    break
                }
            }
        }
    }
}
