import SwiftUI

// MARK: - SceneSelectView

struct SceneSelectView: View {
    let viewModel: SceneSelectViewModel

    var body: some View {
        List {
            Section {
                ForEach(viewModel.scenes) { scene in
                    NavigationLink {
                        RecordingView(
                            viewModel: RecordingViewModel(
                                clientId: viewModel.selectedClient.id,
                                clientName: viewModel.selectedClient.name,
                                scene: scene
                            )
                        )
                    } label: {
                        SceneRow(scene: scene)
                    }
                }
            } header: {
                Text("記録シーンを選択")
            }
        }
        .navigationTitle(viewModel.selectedClient.name)
    }
}

// MARK: - SceneRow

private struct SceneRow: View {
    let scene: RecordingScene

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName(for: scene))
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(scene.displayName)
                    .font(.body)
                    .fontWeight(.medium)

                Text(scene.documentType)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func iconName(for scene: RecordingScene) -> String {
        switch scene {
        case .visit: return "figure.walk"
        case .meeting: return "person.3"
        case .conference: return "rectangle.3.group.bubble"
        case .intake: return "doc.text"
        case .assessment: return "checklist"
        case .other: return "ellipsis.circle"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SceneSelectView(
            viewModel: SceneSelectViewModel(
                selectedClient: ClientCache(
                    id: "preview-1",
                    name: "山田 太郎",
                    furigana: "やまだ たろう"
                )
            )
        )
    }
}
