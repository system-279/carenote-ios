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
                Text(formatTime(currentTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Spacer()

                Text(formatTime(totalDuration))
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
        }
        .onAppear {
            prepareDuration()
        }
        .onDisappear {
            stopPlayback()
        }
    }

    // MARK: - Private

    private func prepareDuration() {
        guard let p = try? AVAudioPlayer(contentsOf: audioURL) else { return }
        totalDuration = p.duration
    }

    private func startPlayback() {
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
            // 再生エラーは静かに無視
        }
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
        progress = 0
        currentTime = 0
        trackingTask?.cancel()
        trackingTask = nil
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

    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
