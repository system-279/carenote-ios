import SwiftData
import SwiftUI

// MARK: - RecordingConfirmView

struct RecordingConfirmView: View {
    @Bindable var viewModel: RecordingConfirmViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showSaveSuccess = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Recording Info Card
                VStack(spacing: 12) {
                    InfoRow(label: "利用者", value: viewModel.clientName)
                    InfoRow(label: "シーン", value: viewModel.scene.rawValue)
                    InfoRow(label: "録音時間", value: viewModel.formattedDuration)
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

                // Playback Section
                AudioPlayerView(audioURL: viewModel.audioURL)

                // Template Selection
                VStack(alignment: .leading, spacing: 12) {
                    Label("出力形式を選択", systemImage: "doc.text")
                        .font(.headline)

                    VStack(spacing: 8) {
                        ForEach(viewModel.templates) { template in
                            TemplateOptionRow(
                                template: template,
                                isSelected: viewModel.selectedTemplate?.id == template.id
                            ) {
                                viewModel.selectedTemplate = template
                            }
                        }
                    }
                }

                // Error Message
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .safeAreaInset(edge: .bottom) {
            // Action Buttons
            VStack(spacing: 10) {
                Button {
                    Task {
                        do {
                            try await viewModel.saveAndTranscribe()
                            showSaveSuccess = true
                        } catch {
                            // errorMessage is set by viewModel
                        }
                    }
                } label: {
                    if viewModel.isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(height: 20)
                    } else {
                        Label("保存して文字起こし", systemImage: "arrow.up.doc")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.isSaving)

                Button {
                    dismiss()
                } label: {
                    Text("やり直し")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(viewModel.isSaving)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
        .navigationTitle("録音確認")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(viewModel.isSaving)
        .task {
            viewModel.loadTemplates()
        }
        .alert("保存完了", isPresented: $showSaveSuccess) {
            Button("OK") {
                NotificationCenter.default.post(name: .navigateToRecordingList, object: nil)
            }
        } message: {
            Text("文字起こしが完了するまでしばらくお待ちください。")
        }
    }
}

// MARK: - InfoRow

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

// MARK: - TemplateOptionRow

private struct TemplateOptionRow: View {
    let template: OutputTemplate
    let isSelected: Bool
    let action: () -> Void

    private var description: String {
        switch OutputType(rawValue: template.outputType) {
        case .transcription:
            return "音声をそのままテキストに変換"
        case .visitRecord:
            return "訪問記録フォーマットで整理"
        case .meetingMinutes:
            return "議題・決定事項を構造化"
        case .summary:
            return "要点を簡潔にまとめる"
        case .custom, .none:
            return "カスタムテンプレート"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(template.name): \(description)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Preview

#Preview {
    let schema = Schema([RecordingRecord.self, ClientCache.self, OutboxItem.self, OutputTemplate.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])

    NavigationStack {
        RecordingConfirmView(
            viewModel: RecordingConfirmViewModel(
                audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
                clientId: "preview-1",
                clientName: "山田 太郎",
                scene: .visit,
                duration: 125,
                modelContext: container.mainContext,
                tenantId: "preview-tenant"
            )
        )
    }
}
