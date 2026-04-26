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
    /// true: throws 経路（再試行可能）/ false: purge 失敗経路（アプリ削除が必要、再試行では解消しない）。
    @State private var deleteAccountIsRetryable: Bool = true

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

            if authViewModel.authState.isAdmin {
                Section {
                    NavigationLink {
                        AccountTransferView()
                    } label: {
                        Label("アカウント引き継ぎ", systemImage: "arrow.right.arrow.left")
                    }
                } header: {
                    Text("管理者メニュー")
                } footer: {
                    Text("メンバーが改姓等で uid が変わった際、旧アカウントの録音・テンプレートを新アカウントに引き継ぎます。")
                        .font(.caption2)
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
                        if deleteAccountIsRetryable {
                            Text("一度ログアウトしてから再度お試しください。\nPlease sign out and try again.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
        deleteAccountIsRetryable = true
        defer { isDeletingAccount = false }

        do {
            try await authViewModel.deleteAccount()
            // Auth 削除は成功、ただしローカル purge が失敗した場合は専用フラグが立つ（#157）。
            // アプリ再インストールが必要なため非再試行型として UI 案内する。
            if authViewModel.postDeletionPurgeFailed {
                deleteAccountError = AuthViewModel.postDeletionPurgeFailureMessage
                deleteAccountIsRetryable = false
            }
        } catch {
            deleteAccountError = "アカウント削除に失敗しました。\nFailed to delete account."
            deleteAccountIsRetryable = true
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
