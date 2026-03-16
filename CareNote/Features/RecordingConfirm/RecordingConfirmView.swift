import SwiftData
import SwiftUI

// MARK: - RecordingConfirmView

struct RecordingConfirmView: View {
    @Bindable var viewModel: RecordingConfirmViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showSaveSuccess = false

    var body: some View {
        VStack(spacing: 24) {
            // Recording Info Card
            VStack(spacing: 12) {
                InfoRow(label: "利用者", value: viewModel.clientName)
                InfoRow(label: "シーン", value: viewModel.scene.rawValue)
                InfoRow(label: "録音時間", value: viewModel.formattedDuration)
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.top, 16)

            // Playback Section
            AudioPlayerView(audioURL: viewModel.audioURL)
                .padding(.horizontal)

            // Template Selection
            VStack(alignment: .leading, spacing: 8) {
                Text("出力形式")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.templates) { template in
                            TemplateChip(
                                name: template.name,
                                isSelected: viewModel.selectedTemplate?.id == template.id
                            ) {
                                viewModel.selectedTemplate = template
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }

            Spacer()

            // Error Message
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Action Buttons
            VStack(spacing: 12) {
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
                        Text("保存して文字起こし")
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
            .padding(.bottom, 24)
        }
        .navigationTitle("録音確認")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(viewModel.isSaving)
        .onAppear {
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

// MARK: - TemplateChip

private struct TemplateChip: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    isSelected ? Color.accentColor : Color(.systemGray5),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
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
