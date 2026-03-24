import SwiftUI

// MARK: - RecordingListView

struct RecordingListView: View {
    @Bindable var viewModel: RecordingListViewModel

    var body: some View {
        List {
            ForEach(viewModel.recordings, id: \.id) { recording in
                NavigationLink(value: recording.id) {
                    RecordingListRow(recording: recording)
                }
            }
            .onDelete { indexSet in
                Task {
                    for index in indexSet {
                        let recording = viewModel.recordings[index]
                        try? await viewModel.deleteRecording(recording)
                    }
                }
            }
        }
        .navigationTitle("録音一覧")
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            } else if viewModel.recordings.isEmpty {
                ContentUnavailableView(
                    "録音がありません",
                    systemImage: "waveform",
                    description: Text("新規録音ボタンから録音を開始してください")
                )
            }
        }
        .refreshable {
            await viewModel.loadRecordings()
        }
        .onAppear {
            Task {
                await viewModel.loadRecordings()
                viewModel.startPolling()
            }
        }
        .onDisappear {
            viewModel.stopPolling()
        }
        .navigationDestination(for: UUID.self) { recordingId in
            if let recording = viewModel.recordings.first(where: { $0.id == recordingId }) {
                RecordingDetailView(
                    recording: recording,
                    onRetry: {
                        try await viewModel.retryRecording(recording)
                    },
                    onSave: { text in
                        try await viewModel.saveTranscription(recording, text: text)
                    },
                    onExport: {
                        await viewModel.exportToGoogleDocs(
                            recording: recording,
                            authProvider: FirebaseGoogleAuthProvider()
                        )
                    },
                    exportedURL: viewModel.exportedURL,
                    exportError: viewModel.exportError
                )
                .onChange(of: viewModel.exportedURL) { _, _ in }
                .onChange(of: viewModel.exportError) { _, _ in }
            }
        }
    }
}

// MARK: - RecordingListRow

private struct RecordingListRow: View {
    let recording: RecordingRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(recording.clientName)
                    .font(.body)
                    .fontWeight(.medium)

                Spacer()

                TranscriptionStatusBadge(status: recording.transcriptionStatus)
            }

            HStack {
                Text(recording.scene)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(recording.recordedAt.formatted(
                    .dateTime.month().day().hour().minute()
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if recording.transcriptionStatus == TranscriptionStatus.done.rawValue,
               let transcription = recording.transcription
            {
                Text(transcription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - TranscriptionStatusBadge

private struct TranscriptionStatusBadge: View {
    let status: String

    var body: some View {
        Text(displayText)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(backgroundColor, in: Capsule())
            .foregroundStyle(foregroundColor)
    }

    private var displayText: String {
        switch status {
        case TranscriptionStatus.pending.rawValue: return "待機中"
        case TranscriptionStatus.processing.rawValue: return "処理中"
        case TranscriptionStatus.done.rawValue: return "完了"
        case TranscriptionStatus.error.rawValue: return "エラー"
        default: return status
        }
    }

    private var backgroundColor: Color {
        switch status {
        case TranscriptionStatus.done.rawValue: return .green.opacity(0.15)
        case TranscriptionStatus.processing.rawValue: return .blue.opacity(0.15)
        case TranscriptionStatus.error.rawValue: return .red.opacity(0.15)
        default: return .gray.opacity(0.15)
        }
    }

    private var foregroundColor: Color {
        switch status {
        case TranscriptionStatus.done.rawValue: return .green
        case TranscriptionStatus.processing.rawValue: return .blue
        case TranscriptionStatus.error.rawValue: return .red
        default: return .gray
        }
    }
}

// MARK: - RecordingDetailView

struct RecordingDetailView: View {
    let recording: RecordingRecord
    var onRetry: (() async throws -> Void)?
    var onSave: ((String) async throws -> Void)?
    var onExport: (() async -> Void)?
    var exportedURL: URL?
    var exportError: String?
    @State private var isRetrying = false
    @State private var isEditing = false
    @State private var editedText = ""
    @State private var isSaving = false
    @State private var hasLocalAudio = false
    @State private var isExporting = false
    @State private var showExportSuccess = false
    @State private var localExportURL: URL?
    @State private var localExportError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Info Section
                VStack(alignment: .leading, spacing: 8) {
                    DetailRow(label: "利用者", value: recording.clientName)
                    DetailRow(label: "シーン", value: recording.scene)
                    DetailRow(
                        label: "録音日時",
                        value: recording.recordedAt.formatted(
                            .dateTime.year().month().day().hour().minute()
                        )
                    )
                    DetailRow(
                        label: "録音時間",
                        value: formatMMSS(recording.durationSeconds)
                    )
                    if let templateName = recording.templateNameSnapshot {
                        DetailRow(label: "出力形式", value: templateName)
                    }
                    if let docsUrlString = recording.googleDocsUrl,
                       let docsUrl = URL(string: docsUrlString)
                    {
                        HStack {
                            Text("Google Docs")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .leading)
                            Button {
                                UIApplication.shared.open(docsUrl)
                            } label: {
                                Label("開く", systemImage: "doc.text")
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

                // Playback Section
                if hasLocalAudio {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("再生")
                            .font(.headline)

                        AudioPlayerView(audioURL: URL(fileURLWithPath: recording.localAudioPath))
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }

                // Transcription Section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("文字起こし")
                            .font(.headline)

                        Spacer()

                        if recording.transcriptionStatus == TranscriptionStatus.done.rawValue,
                           recording.transcription != nil, !isEditing
                        {
                            Button {
                                editedText = recording.transcription ?? ""
                                isEditing = true
                            } label: {
                                Label("編集", systemImage: "pencil")
                                    .font(.subheadline)
                            }
                        }
                    }

                    if isEditing {
                        TextEditor(text: $editedText)
                            .font(.body)
                            .frame(minHeight: 200)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.secondary.opacity(0.3))
                            )

                        HStack {
                            Button("キャンセル") {
                                isEditing = false
                            }
                            .buttonStyle(.bordered)

                            Spacer()

                            Button {
                                Task {
                                    isSaving = true
                                    try? await onSave?(editedText)
                                    isEditing = false
                                    isSaving = false
                                }
                            } label: {
                                if isSaving {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text("保存")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isSaving)
                        }
                    } else if recording.transcriptionStatus == TranscriptionStatus.done.rawValue,
                              let transcription = recording.transcription
                    {
                        Text(transcription)
                            .font(.body)
                            .textSelection(.enabled)
                    } else if recording.transcriptionStatus
                        == TranscriptionStatus.processing.rawValue
                    {
                        HStack {
                            ProgressView()
                            Text("文字起こし処理中...")
                                .foregroundStyle(.secondary)
                        }
                    } else if recording.transcriptionStatus == TranscriptionStatus.error.rawValue {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("文字起こしに失敗しました")
                                .foregroundStyle(.red)

                            if let onRetry {
                                Button {
                                    Task {
                                        isRetrying = true
                                        try? await onRetry()
                                        isRetrying = false
                                    }
                                } label: {
                                    HStack {
                                        if isRetrying {
                                            ProgressView()
                                                .controlSize(.small)
                                        } else {
                                            Image(systemName: "arrow.clockwise")
                                        }
                                        Text("再試行")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)
                                .disabled(isRetrying)
                            }
                        }
                    } else {
                        Text("文字起こし待機中")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding()
        }
        .navigationTitle("録音詳細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if recording.transcriptionStatus == TranscriptionStatus.done.rawValue,
               recording.transcription != nil
            {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            isExporting = true
                            await onExport?()
                            isExporting = false
                        }
                    } label: {
                        if isExporting {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("エクスポート", systemImage: "doc.text")
                        }
                    }
                    .disabled(isExporting || isEditing)
                }
            }
        }
        .onAppear {
            hasLocalAudio = FileManager.default.fileExists(atPath: recording.localAudioPath)
        }
        .onChange(of: exportedURL) { _, newURL in
            if let url = newURL {
                localExportURL = url
                showExportSuccess = true
            }
        }
        .onChange(of: exportError) { _, newError in
            if let error = newError {
                localExportError = error
            }
        }
        .alert("エクスポート完了", isPresented: $showExportSuccess) {
            if let url = localExportURL {
                Button("Google Docsで開く") { UIApplication.shared.open(url) }
            }
            Button("閉じる", role: .cancel) {}
        } message: {
            Text("Google Docsにエクスポートしました")
        }
        .alert("エクスポートエラー", isPresented: .init(
            get: { localExportError != nil },
            set: { if !$0 { localExportError = nil } }
        )) {
            Button("OK") { localExportError = nil }
        } message: {
            Text(localExportError ?? "")
        }
    }
}

// MARK: - DetailRow

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(.subheadline)
        }
    }
}
