import Foundation

/// TimeInterval を MM:SS 形式にフォーマットする
func formatMMSS(_ time: TimeInterval) -> String {
    let totalSeconds = Int(time)
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%02d:%02d", minutes, seconds)
}
