import SwiftData
import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthViewModel.self) private var authViewModel

    @State private var templateListViewModel: TemplateListViewModel?
    @State private var showSignOutConfirmation = false
    @State private var showDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?

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

                Button(role: .destructive) {
                    showDeleteAccountConfirmation = true
                } label: {
                    if isDeletingAccount {
                        HStack {
                            ProgressView()
                            Text("削除中...")
                        }
                    } else {
                        Label("アカウントを削除", systemImage: "trash")
                    }
                }
                .disabled(isDeletingAccount)

                if let message = deleteAccountError {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.red)
                        Text("一度ログアウトしてから再度お試しください。\nPlease sign out and try again.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
        .alert("アカウントを削除", isPresented: $showDeleteAccountConfirmation) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                Task {
                    await deleteAccount()
                }
            }
        } message: {
            Text("アカウントを完全に削除します。この操作は取り消せません。\n\nThis will permanently delete your account. This action cannot be undone.")
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

    private func deleteAccount() async {
        isDeletingAccount = true
        deleteAccountError = nil
        defer { isDeletingAccount = false }

        do {
            try await authViewModel.deleteAccount()
        } catch {
            deleteAccountError = "アカウント削除に失敗しました。\nFailed to delete account."
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
