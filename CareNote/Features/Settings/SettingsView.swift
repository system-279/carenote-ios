import SwiftData
import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthViewModel.self) private var authViewModel

    @State private var templateListViewModel: TemplateListViewModel?
    @State private var showSignOutConfirmation = false

    var body: some View {
        List {
            Section("テンプレート") {
                NavigationLink {
                    if let vm = templateListViewModel {
                        TemplateListView(viewModel: vm)
                    } else {
                        ProgressView()
                    }
                } label: {
                    Label("テンプレート管理", systemImage: "doc.text")
                }
            }

            Section("アカウント") {
                Button(role: .destructive) {
                    showSignOutConfirmation = true
                } label: {
                    Label("ログアウト", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .alert("ログアウト", isPresented: $showSignOutConfirmation) {
            Button("キャンセル", role: .cancel) {}
            Button("ログアウト", role: .destructive) {
                authViewModel.signOut()
            }
        } message: {
            Text("ログアウトしますか？")
        }
        .navigationTitle("設定")
        .task {
            if templateListViewModel == nil {
                templateListViewModel = TemplateListViewModel(
                    modelContext: modelContext,
                    tenantId: authViewModel.authState.tenantId,
                    isAdmin: authViewModel.authState.isAdmin
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
