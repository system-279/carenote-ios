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
    @State private var confirmViewModel: RecordingConfirmViewModel?

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
                .foregroundStyle(timerColor)

            // Pulse Animation & Buttons
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

                HStack(spacing: 40) {
                    // Main Button: Start / Pause / Resume
                    Button {
                        Task {
                            await handleMainButtonTap()
                        }
                    } label: {
                        Circle()
                            .fill(mainButtonColor)
                            .frame(width: 80, height: 80)
                            .overlay {
                                mainButtonIcon
                            }
                            .shadow(color: .red.opacity(0.3), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)

                    // Stop Button (visible during recording or paused)
                    if viewModel.recordingState == .recording || viewModel.recordingState == .paused {
                        Button {
                            Task {
                                try? await viewModel.stopRecording()
                            }
                        } label: {
                            Circle()
                                .fill(.gray.opacity(0.2))
                                .frame(width: 56, height: 56)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(.red)
                                        .frame(width: 20, height: 20)
                                }
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .frame(height: 180)
            .animation(.easeInOut(duration: 0.2), value: viewModel.recordingState)

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
        .navigationBarBackButtonHidden(viewModel.recordingState == .recording || viewModel.recordingState == .paused)
        .navigationDestination(isPresented: $navigateToConfirm) {
            if let vm = confirmViewModel {
                RecordingConfirmView(viewModel: vm)
            }
        }
        .onChange(of: viewModel.recordingState) { _, newState in
            if newState == .recording {
                pulseAnimation = true
            } else {
                pulseAnimation = false
            }

            if newState == .stopped, let url = viewModel.audioURL {
                confirmViewModel = RecordingConfirmViewModel(
                    audioURL: url,
                    clientId: viewModel.clientId,
                    clientName: viewModel.clientName,
                    scene: viewModel.scene,
                    duration: viewModel.elapsedTime,
                    modelContext: modelContext,
                    tenantId: authViewModel.authState.tenantId ?? ""
                )
                navigateToConfirm = true
            }
        }
    }

    // MARK: - Private

    private var timerColor: Color {
        switch viewModel.recordingState {
        case .recording: return .red
        case .paused: return .orange
        default: return .primary
        }
    }

    private var stateLabel: String {
        switch viewModel.recordingState {
        case .idle: return "タップして録音開始"
        case .recording: return "録音中..."
        case .paused: return "一時停止中"
        case .stopped: return "録音完了"
        }
    }

    private var mainButtonColor: Color {
        switch viewModel.recordingState {
        case .idle, .stopped: return .red.opacity(0.85)
        case .recording: return .red
        case .paused: return .green
        }
    }

    @ViewBuilder
    private var mainButtonIcon: some View {
        switch viewModel.recordingState {
        case .idle, .stopped:
            Circle()
                .fill(.white)
                .frame(width: 28, height: 28)
        case .recording:
            Image(systemName: "pause.fill")
                .font(.title2)
                .foregroundStyle(.white)
        case .paused:
            Image(systemName: "play.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .offset(x: 2)
        }
    }

    @MainActor
    private func handleMainButtonTap() async {
        switch viewModel.recordingState {
        case .idle, .stopped:
            try? await viewModel.startRecording()
        case .recording:
            try? await viewModel.pauseRecording()
        case .paused:
            try? await viewModel.resumeRecording()
        }
    }
}

// MARK: - Preview

#Preview {
    let schema = Schema([RecordingRecord.self, ClientCache.self, OutboxItem.self, OutputTemplate.self])
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
