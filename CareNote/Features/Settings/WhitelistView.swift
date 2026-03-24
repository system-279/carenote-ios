import SwiftUI

// MARK: - WhitelistView

struct WhitelistView: View {
    @Bindable var viewModel: WhitelistViewModel

    var body: some View {
        List {
            // 許可ドメイン一覧
            Section {
                if viewModel.allowedDomains.isEmpty {
                    Text("許可ドメインはありません")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.allowedDomains, id: \.self) { domain in
                        HStack {
                            Label(domain, systemImage: "globe")
                            Spacer()
                            Button(role: .destructive) {
                                Task { await viewModel.removeDomain(domain) }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red.opacity(0.7))
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            } header: {
                Text("許可ドメイン")
            } footer: {
                if viewModel.allowedDomains.isEmpty {
                    Text("ドメインを追加すると、そのドメインのメールアドレスは自動的にサインインが許可されます")
                } else {
                    Text("\(viewModel.allowedDomains.joined(separator: ", ")) のメールアドレスは自動的にサインインが許可されます")
                }
            }

            // ドメイン追加
            Section("ドメイン追加") {
                TextField("例: 279279.net", text: $viewModel.newDomain)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    Task { await viewModel.addDomain() }
                } label: {
                    Label("ドメインを追加", systemImage: "plus.circle.fill")
                }
                .disabled(!viewModel.isValidDomain)
            }

            // メンバー一覧
            Section {
                if viewModel.entries.isEmpty {
                    Text("登録メンバーはいません")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.entries) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.email)
                                    .font(.subheadline)
                                Text(entry.role)
                                    .font(.caption)
                                    .foregroundStyle(entry.role == "admin" ? .orange : .secondary)
                            }

                            Spacer()

                            Button {
                                Task { await viewModel.toggleRole(entry) }
                            } label: {
                                Text(entry.role == "admin" ? "admin" : "user")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        entry.role == "admin" ? Color.orange.opacity(0.2) : Color.secondary.opacity(0.2),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.borderless)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { await viewModel.removeEntry(entry) }
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text("メンバー")
            }

            // メンバー追加
            Section("メンバー追加") {
                TextField("メールアドレス", text: $viewModel.newEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Picker("ロール", selection: $viewModel.newRole) {
                    Text("user").tag("user")
                    Text("admin").tag("admin")
                }

                Button {
                    Task { await viewModel.addEmail() }
                } label: {
                    Label("メンバーを追加", systemImage: "person.badge.plus")
                }
                .disabled(!viewModel.isValidEmail)
            }
        }
        .navigationTitle("メンバー管理")
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .alert("エラー", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onAppear {
            Task { await viewModel.load() }
        }
    }
}
