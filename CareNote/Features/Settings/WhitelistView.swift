import SwiftUI

// MARK: - WhitelistView

struct WhitelistView: View {
    @Bindable var viewModel: WhitelistViewModel

    @State private var entryToDelete: FirestoreWhitelistEntry?

    var body: some View {
        List {
            Section("メールアドレス追加") {
                HStack {
                    TextField("example@email.com", text: $viewModel.newEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Button {
                        Task { await viewModel.addEmail() }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                    .disabled(!viewModel.isValidEmail)
                }
            }

            Section {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                } else if viewModel.entries.isEmpty {
                    ContentUnavailableView(
                        "許可済みメールなし",
                        systemImage: "person.badge.plus",
                        description: Text("メールアドレスを追加すると、そのユーザーがサインインできるようになります")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(viewModel.entries) { entry in
                        WhitelistRow(entry: entry)
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
                Text("許可済みメールアドレス（\(viewModel.entries.count)件）")
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
        .alert("メールアドレスを削除", isPresented: Binding(
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.email)
                .font(.body)

            Text("追加日: \(entry.addedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
