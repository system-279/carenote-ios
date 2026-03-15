@testable import CareNote
import Foundation
import Testing

// MARK: - MockAudioRecorder

actor MockAudioRecorder: AudioRecording {
    var isRecording: Bool = false
    var isPaused: Bool = false
    var elapsedTime: TimeInterval = 0
    var urlToReturn: URL = URL(fileURLWithPath: "/tmp/test.m4a")
    var startError: Error?
    var stopError: Error?
    var pauseError: Error?
    var resumeError: Error?

    func startRecording() async throws -> URL {
        if let error = startError {
            throw error
        }
        isRecording = true
        isPaused = false
        return urlToReturn
    }

    func pauseRecording() async throws {
        if let error = pauseError {
            throw error
        }
        isPaused = true
    }

    func resumeRecording() async throws {
        if let error = resumeError {
            throw error
        }
        isPaused = false
    }

    func stopRecording() async throws -> (url: URL, duration: TimeInterval) {
        if let error = stopError {
            throw error
        }
        isRecording = false
        isPaused = false
        return (url: urlToReturn, duration: elapsedTime)
    }

    func setElapsedTime(_ time: TimeInterval) {
        elapsedTime = time
    }
}

// MARK: - RecordingViewModelTests

@Suite("RecordingViewModel Tests")
struct RecordingViewModelTests {

    @Test @MainActor
    func 初期状態はidle() {
        let vm = RecordingViewModel(
            clientId: "client-1",
            clientName: "テスト利用者",
            scene: .visit,
            audioRecorder: MockAudioRecorder()
        )

        #expect(vm.recordingState == .idle)
        #expect(vm.elapsedTime == 0)
        #expect(vm.audioURL == nil)
        #expect(vm.errorMessage == nil)
    }

    @Test @MainActor
    func 録音開始でrecordingになる() async throws {
        let mock = MockAudioRecorder()
        let vm = RecordingViewModel(
            clientId: "client-1",
            clientName: "テスト利用者",
            scene: .visit,
            audioRecorder: mock
        )

        try await vm.startRecording()

        #expect(vm.recordingState == .recording)
        #expect(vm.audioURL != nil)
    }

    @Test @MainActor
    func 録音停止でstoppedになる() async throws {
        let mock = MockAudioRecorder()
        await mock.setElapsedTime(10.5)
        let vm = RecordingViewModel(
            clientId: "client-1",
            clientName: "テスト利用者",
            scene: .visit,
            audioRecorder: mock
        )

        try await vm.startRecording()
        try await vm.stopRecording()

        #expect(vm.recordingState == .stopped)
    }

    @Test @MainActor
    func recording中に録音開始はガード() async throws {
        let mock = MockAudioRecorder()
        let vm = RecordingViewModel(
            clientId: "client-1",
            clientName: "テスト利用者",
            scene: .visit,
            audioRecorder: mock
        )

        try await vm.startRecording()
        #expect(vm.recordingState == .recording)

        // recording中に再度startRecordingを呼んでも状態は変わらない
        try await vm.startRecording()
        #expect(vm.recordingState == .recording)
    }

    @Test @MainActor
    func idle状態から停止はガード() async throws {
        let mock = MockAudioRecorder()
        let vm = RecordingViewModel(
            clientId: "client-1",
            clientName: "テスト利用者",
            scene: .visit,
            audioRecorder: mock
        )

        #expect(vm.recordingState == .idle)

        // idle状態でstopRecordingを呼んでも何も起きない
        try await vm.stopRecording()
        #expect(vm.recordingState == .idle)
    }

    @Test @MainActor
    func 録音一時停止でpausedになる() async throws {
        let mock = MockAudioRecorder()
        let vm = RecordingViewModel(
            clientId: "client-1",
            clientName: "テスト利用者",
            scene: .visit,
            audioRecorder: mock
        )

        try await vm.startRecording()
        #expect(vm.recordingState == .recording)

        try await vm.pauseRecording()
        #expect(vm.recordingState == .paused)
    }

    @Test @MainActor
    func 一時停止から再開でrecordingになる() async throws {
        let mock = MockAudioRecorder()
        let vm = RecordingViewModel(
            clientId: "client-1",
            clientName: "テスト利用者",
            scene: .visit,
            audioRecorder: mock
        )

        try await vm.startRecording()
        try await vm.pauseRecording()
        #expect(vm.recordingState == .paused)

        try await vm.resumeRecording()
        #expect(vm.recordingState == .recording)
    }

    @Test @MainActor
    func 一時停止中に停止でstoppedになる() async throws {
        let mock = MockAudioRecorder()
        await mock.setElapsedTime(15.0)
        let vm = RecordingViewModel(
            clientId: "client-1",
            clientName: "テスト利用者",
            scene: .visit,
            audioRecorder: mock
        )

        try await vm.startRecording()
        try await vm.pauseRecording()
        #expect(vm.recordingState == .paused)

        try await vm.stopRecording()
        #expect(vm.recordingState == .stopped)
    }

    @Test @MainActor
    func idle状態から一時停止はガード() async throws {
        let mock = MockAudioRecorder()
        let vm = RecordingViewModel(
            clientId: "client-1",
            clientName: "テスト利用者",
            scene: .visit,
            audioRecorder: mock
        )

        #expect(vm.recordingState == .idle)
        try await vm.pauseRecording()
        #expect(vm.recordingState == .idle)
    }

    @Test @MainActor
    func idle状態から再開はガード() async throws {
        let mock = MockAudioRecorder()
        let vm = RecordingViewModel(
            clientId: "client-1",
            clientName: "テスト利用者",
            scene: .visit,
            audioRecorder: mock
        )

        #expect(vm.recordingState == .idle)
        try await vm.resumeRecording()
        #expect(vm.recordingState == .idle)
    }

    @Test @MainActor
    func formatElapsedTimeのフォーマット() {
        let vm = RecordingViewModel(
            clientId: "client-1",
            clientName: "テスト利用者",
            scene: .visit,
            audioRecorder: MockAudioRecorder()
        )

        vm.elapsedTime = 0
        #expect(vm.formatElapsedTime() == "00:00")

        vm.elapsedTime = 65
        #expect(vm.formatElapsedTime() == "01:05")

        vm.elapsedTime = 3599
        #expect(vm.formatElapsedTime() == "59:59")

        vm.elapsedTime = 3600
        #expect(vm.formatElapsedTime() == "60:00")
    }
}
