import SwiftData
import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthViewModel.self) private var authViewModel

    let tenantId: String
    let isAdmin: Bool

    @State private var templateListViewModel: TemplateListViewModel?
    @State private var whitelistViewModel: WhitelistViewModel?

    var body: some View {
        List {
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

            if isAdmin {
                Section("管理") {
                    NavigationLink {
                        if let vm = whitelistViewModel {
                            WhitelistView(viewModel: vm)
                        }
                    } label: {
                        Label("メンバー管理", systemImage: "person.2")
                    }
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
            if isAdmin, whitelistViewModel == nil {
                whitelistViewModel = WhitelistViewModel(
                    tenantId: tenantId,
                    userId: authViewModel.authState.userId ?? ""
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
        SettingsView(tenantId: "test-tenant-1", isAdmin: true)
            .environment(AuthViewModel())
    }
    .modelContainer(container)
}
