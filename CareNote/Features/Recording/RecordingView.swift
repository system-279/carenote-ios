import SwiftData
import SwiftUI

// MARK: - RecordingView

struct RecordingView: View {
    @Bindable var viewModel: RecordingViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthViewModel.self) private var authViewModel

    @State private var pulseAnimation = false
    @State private var navigateToConfirm = false

    var body: some View {
        VStack(spacing: 32) {
            // Header: Client name & Scene
            VStack(spacing: 4) {
                Text(viewModel.clientName)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(viewModel.scene.rawValue)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 40)

            Spacer()

            // Timer Display
            Text(viewModel.formatElapsedTime())
                .font(.system(size: 72, weight: .light, design: .monospaced))
                .foregroundStyle(viewModel.recordingState == .recording ? .red : .primary)

            // Pulse Animation
            ZStack {
                if viewModel.recordingState == .recording {
                    Circle()
                        .fill(.red.opacity(0.15))
                        .frame(width: 160, height: 160)
                        .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                        .opacity(pulseAnimation ? 0 : 0.6)
                        .animation(
                            .easeInOut(duration: 1.2).repeatForever(autoreverses: false),
                            value: pulseAnimation
                        )

                    Circle()
                        .fill(.red.opacity(0.1))
                        .frame(width: 140, height: 140)
                        .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                        .opacity(pulseAnimation ? 0.2 : 0.5)
                        .animation(
                            .easeInOut(duration: 1.2).repeatForever(autoreverses: false).delay(0.3),
                            value: pulseAnimation
                        )
                }

                // Record Button
                Button {
                    Task {
                        await handleRecordButtonTap()
                    }
                } label: {
                    Circle()
                        .fill(viewModel.recordingState == .recording ? .red : .red.opacity(0.85))
                        .frame(width: 80, height: 80)
                        .overlay {
                            if viewModel.recordingState == .recording {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.white)
                                    .frame(width: 28, height: 28)
                            } else {
                                Circle()
                                    .fill(.white)
                                    .frame(width: 28, height: 28)
                            }
                        }
                        .shadow(color: .red.opacity(0.3), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
            }
            .frame(height: 180)

            // State Label
            Text(stateLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            // Error Message
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding()
        .navigationBarBackButtonHidden(viewModel.recordingState == .recording)
        .navigationDestination(isPresented: $navigateToConfirm) {
            if let url = viewModel.audioURL {
                RecordingConfirmView(
                    viewModel: RecordingConfirmViewModel(
                        audioURL: url,
                        clientId: viewModel.clientId,
                        clientName: viewModel.clientName,
                        scene: viewModel.scene,
                        duration: viewModel.elapsedTime,
                        modelContext: modelContext,
                        tenantId: authViewModel.authState.tenantId ?? ""
                    )
                )
            }
        }
        .onChange(of: viewModel.recordingState) { _, newState in
            if newState == .recording {
                pulseAnimation = true
            } else {
                pulseAnimation = false
            }

            if newState == .stopped {
                navigateToConfirm = true
            }
        }
    }

    // MARK: - Private

    private var stateLabel: String {
        switch viewModel.recordingState {
        case .idle: return "タップして録音開始"
        case .recording: return "録音中..."
        case .paused: return "一時停止中"
        case .stopped: return "録音完了"
        }
    }

    @MainActor
    private func handleRecordButtonTap() async {
        switch viewModel.recordingState {
        case .idle, .stopped:
            try? await viewModel.startRecording()
        case .recording:
            try? await viewModel.stopRecording()
        case .paused:
            break
        }
    }
}

// MARK: - Preview

#Preview {
    let schema = Schema([RecordingRecord.self, ClientCache.self, OutboxItem.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])

    NavigationStack {
        RecordingView(
            viewModel: RecordingViewModel(
                clientId: "preview-1",
                clientName: "山田 太郎",
                scene: .visit
            )
        )
    }
    .modelContainer(container)
    .environment(AuthViewModel())
}
