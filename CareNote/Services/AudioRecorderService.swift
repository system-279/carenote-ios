import AVFoundation
import Foundation

// MARK: - AudioRecorderError

enum AudioRecorderError: Error, Sendable {
    case recordingInProgress
    case notRecording
    case audioSessionSetupFailed(Error)
    case recordingFailed(Error)
    case fileNotFound
}

// MARK: - AudioRecording Protocol

protocol AudioRecording: Actor {
    var isRecording: Bool { get }
    var isPaused: Bool { get }
    var elapsedTime: TimeInterval { get }
    func startRecording() async throws -> URL
    func pauseRecording() async throws
    func resumeRecording() async throws
    func stopRecording() async throws -> (url: URL, duration: TimeInterval)
}

// MARK: - AudioRecorderService

actor AudioRecorderService: AudioRecording {

    // MARK: - Properties

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var recordingStartTime: Date?
    private var timerTask: Task<Void, Never>?

    private(set) var isRecording: Bool = false
    private(set) var isPaused: Bool = false
    private(set) var elapsedTime: TimeInterval = 0
    private var accumulatedTime: TimeInterval = 0

    // MARK: - Recording Settings

    private var recordingSettings: [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
    }

    // MARK: - Public Methods

    /// Start recording audio in M4A/AAC format.
    /// - Returns: The file URL where audio is being recorded.
    func startRecording() async throws -> URL {
        guard !isRecording else {
            throw AudioRecorderError.recordingInProgress
        }

        // Configure audio session
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                options: [.defaultToSpeaker, .allowBluetoothA2DP]
            )
            try session.setActive(true)
        } catch {
            throw AudioRecorderError.audioSessionSetupFailed(error)
        }

        // Create file URL in Documents directory
        let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        let fileName = "\(UUID().uuidString).m4a"
        let fileURL = documentsURL.appendingPathComponent(fileName)

        // Create and start recorder
        do {
            let recorder = try AVAudioRecorder(url: fileURL, settings: recordingSettings)
            recorder.record()

            audioRecorder = recorder
            recordingURL = fileURL
            recordingStartTime = Date()
            isRecording = true
            isPaused = false
            elapsedTime = 0
            accumulatedTime = 0

            startElapsedTimeTimer()

            return fileURL
        } catch {
            throw AudioRecorderError.recordingFailed(error)
        }
    }

    /// Pause the current recording.
    func pauseRecording() async throws {
        guard isRecording, !isPaused, let recorder = audioRecorder else {
            throw AudioRecorderError.notRecording
        }

        recorder.pause()
        isPaused = true

        // Accumulate elapsed time and stop timer
        if let startTime = recordingStartTime {
            accumulatedTime += Date().timeIntervalSince(startTime)
        }
        stopElapsedTimeTimer()
    }

    /// Resume the current recording after pause.
    func resumeRecording() async throws {
        guard isRecording, isPaused, let recorder = audioRecorder else {
            throw AudioRecorderError.notRecording
        }

        recorder.record()
        isPaused = false
        recordingStartTime = Date()
        startElapsedTimeTimer()
    }

    /// Stop the current recording.
    /// - Returns: A tuple containing the file URL and the recording duration.
    func stopRecording() async throws -> (url: URL, duration: TimeInterval) {
        guard isRecording, let recorder = audioRecorder, let url = recordingURL else {
            throw AudioRecorderError.notRecording
        }

        recorder.stop()

        // Calculate total duration including accumulated paused segments
        let currentSegment: TimeInterval
        if isPaused {
            currentSegment = 0
        } else if let startTime = recordingStartTime {
            currentSegment = Date().timeIntervalSince(startTime)
        } else {
            currentSegment = 0
        }
        let duration = accumulatedTime + currentSegment

        stopElapsedTimeTimer()

        // Verify the file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AudioRecorderError.fileNotFound
        }

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        // Clean up state
        audioRecorder = nil
        recordingURL = nil
        recordingStartTime = nil
        isRecording = false
        isPaused = false
        accumulatedTime = 0

        return (url: url, duration: duration)
    }

    // MARK: - Private Methods

    private func startElapsedTimeTimer() {
        stopElapsedTimeTimer()

        let startTime = Date()
        let baseTime = accumulatedTime
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { break }
                await self?.updateElapsedTime(since: startTime, baseTime: baseTime)
            }
        }
    }

    private func updateElapsedTime(since startTime: Date, baseTime: TimeInterval) {
        elapsedTime = baseTime + Date().timeIntervalSince(startTime)
    }

    private func stopElapsedTimeTimer() {
        timerTask?.cancel()
        timerTask = nil
    }
}
