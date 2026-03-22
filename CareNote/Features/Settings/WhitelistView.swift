import SwiftUI

// MARK: - WhitelistView

struct WhitelistView: View {
    @Bindable var viewModel: WhitelistViewModel

    @State private var entryToDelete: FirestoreWhitelistEntry?

    var body: some View {
        List {
            Section("メンバー追加") {
                VStack(spacing: 12) {
                    TextField("example@email.com", text: $viewModel.newEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    HStack {
                        Picker("ロール", selection: $viewModel.newRole) {
                            Text("一般ユーザー").tag("user")
                            Text("管理者").tag("admin")
                        }
                        .pickerStyle(.segmented)

                        Button {
                            Task { await viewModel.addEmail() }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                        .disabled(!viewModel.isValidEmail)
                    }
                }
            }

            Section {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                } else if viewModel.entries.isEmpty {
                    ContentUnavailableView(
                        "メンバーなし",
                        systemImage: "person.badge.plus",
                        description: Text("メールアドレスとロールを指定してメンバーを追加できます")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(viewModel.entries) { entry in
                        WhitelistRow(entry: entry) { newRole in
                            Task { await viewModel.updateRole(entry: entry, newRole: newRole) }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                entryToDelete = entry
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text("メンバー一覧（\(viewModel.entries.count)件）")
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("メンバー管理")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadWhitelist()
        }
        .alert("メンバーを削除", isPresented: Binding(
            get: { entryToDelete != nil },
            set: { if !$0 { entryToDelete = nil } }
        )) {
            Button("削除", role: .destructive) {
                if let entry = entryToDelete {
                    Task { await viewModel.removeEntry(entry) }
                    entryToDelete = nil
                }
            }
            Button("キャンセル", role: .cancel) {
                entryToDelete = nil
            }
        } message: {
            if let entry = entryToDelete {
                Text("「\(entry.email)」を削除しますか？このユーザーはサインインできなくなります。")
            }
        }
    }
}

// MARK: - WhitelistRow

private struct WhitelistRow: View {
    let entry: FirestoreWhitelistEntry
    let onRoleChange: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.email)
                    .font(.body)

                Spacer()

                Menu {
                    Button {
                        onRoleChange("user")
                    } label: {
                        Label("一般ユーザー", systemImage: entry.role == "user" ? "checkmark" : "")
                    }
                    Button {
                        onRoleChange("admin")
                    } label: {
                        Label("管理者", systemImage: entry.role == "admin" ? "checkmark" : "")
                    }
                } label: {
                    Text(entry.role == "admin" ? "管理者" : "ユーザー")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(entry.role == "admin" ? Color.blue.opacity(0.15) : Color.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(entry.role == "admin" ? .blue : .secondary)
                }
            }

            Text("追加日: \(entry.addedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
