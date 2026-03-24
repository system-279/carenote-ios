import SwiftData
import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthViewModel.self) private var authViewModel

    @State private var templateListViewModel: TemplateListViewModel?
    @State private var clientManagementViewModel: ClientManagementViewModel?
    @State private var whitelistViewModel: WhitelistViewModel?

    var body: some View {
        List {
            if authViewModel.authState.isAdmin {
                Section("メンバー") {
                    NavigationLink {
                        if let vm = whitelistViewModel {
                            WhitelistView(viewModel: vm)
                        }
                    } label: {
                        Label("メンバー管理", systemImage: "person.badge.key")
                    }
                }
            }

            Section("利用者") {
                NavigationLink {
                    if let vm = clientManagementViewModel {
                        ClientManagementView(viewModel: vm)
                    }
                } label: {
                    Label("利用者管理", systemImage: "person.crop.rectangle.stack")
                }
            }

            Section("テンプレート") {
                NavigationLink {
                    TemplateListView(
                        viewModel: templateListViewModel
                            ?? TemplateListViewModel(modelContext: modelContext)
                    )
                } label: {
                    Label("テンプレート管理", systemImage: "doc.text")
                }
            }

            Section("アカウント") {
                Button(role: .destructive) {
                    authViewModel.signOut()
                } label: {
                    Label("ログアウト", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle("設定")
        .task {
            if templateListViewModel == nil {
                templateListViewModel = TemplateListViewModel(modelContext: modelContext)
            }
            if whitelistViewModel == nil,
               let tenantId = authViewModel.authState.tenantId,
               let userId = authViewModel.authState.userId
            {
                whitelistViewModel = WhitelistViewModel(
                    tenantId: tenantId,
                    userId: userId
                )
            }
            if clientManagementViewModel == nil, let tenantId = authViewModel.authState.tenantId {
                clientManagementViewModel = ClientManagementViewModel(
                    tenantId: tenantId,
                    cacheService: ClientCacheService(
                        firestoreService: FirestoreService(),
                        modelContainer: modelContext.container
                    )
                )
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let schema = Schema([RecordingRecord.self, ClientCache.self, OutboxItem.self, OutputTemplate.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])

    NavigationStack {
        SettingsView()
            .environment(AuthViewModel())
    }
    .modelContainer(container)
}
