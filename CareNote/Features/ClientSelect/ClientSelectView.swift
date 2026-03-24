import SwiftData
import SwiftUI

// MARK: - ClientSelectView

struct ClientSelectView: View {
    @Bindable var viewModel: ClientSelectViewModel

    var body: some View {
        List {
            ForEach(viewModel.filteredClients, id: \.id) { client in
                NavigationLink(value: client) {
                    ClientRow(client: client)
                }
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "名前・ふりがなで検索")
        .navigationTitle("利用者選択")
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            } else if viewModel.filteredClients.isEmpty && !viewModel.searchText.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchText)
            } else if viewModel.clients.isEmpty {
                ContentUnavailableView(
                    "利用者がいません",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Firestore から利用者データを同期してください")
                )
            }
        }
        .onAppear {
            Task {
                await viewModel.loadClients()
            }
        }
    }
}

// MARK: - ClientRow

private struct ClientRow: View {
    let client: ClientCache

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(client.name)
                .font(.body)
                .fontWeight(.medium)

            Text(client.furigana)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ClientSelectView(
            viewModel: {
                let vm = ClientSelectViewModel(
                    clientRepository: PreviewHelper.clientRepository
                )
                return vm
            }()
        )
    }
}

// MARK: - PreviewHelper

private enum PreviewHelper {
    @MainActor
    static var clientRepository: ClientRepository {
        ClientRepository(modelContext: PreviewModelContext.shared)
    }
}

private enum PreviewModelContext {
    @MainActor
    static let shared: SwiftData.ModelContext = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: RecordingRecord.self, ClientCache.self, OutboxItem.self,
            configurations: config
        )
        return container.mainContext
    }()
}
