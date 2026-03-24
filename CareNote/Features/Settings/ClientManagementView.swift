import SwiftUI

// MARK: - ClientManagementView

struct ClientManagementView: View {
    @Bindable var viewModel: ClientManagementViewModel

    @State private var clientToDelete: FirestoreClient?
    @State private var editingClient: FirestoreClient?

    var body: some View {
        List {
            Section("利用者追加") {
                VStack(spacing: 12) {
                    TextField("名前", text: $viewModel.newName)
                        .autocorrectionDisabled()

                    HStack {
                        TextField("ふりがな", text: $viewModel.newFurigana)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        Button {
                            Task { await viewModel.addClient() }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                        .disabled(!viewModel.isValidInput)
                    }
                }
            }

            Section {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                } else if viewModel.clients.isEmpty {
                    ContentUnavailableView(
                        "利用者がいません",
                        systemImage: "person.crop.rectangle.stack"
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(viewModel.clients) { client in
                        ClientManagementRow(client: client)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingClient = client
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    clientToDelete = client
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                    }
                }
            } header: {
                Text("利用者一覧（\(viewModel.clients.count)件）")
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("利用者管理")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadClients()
        }
        .alert("利用者を削除", isPresented: Binding(
            get: { clientToDelete != nil },
            set: { if !$0 { clientToDelete = nil } }
        )) {
            Button("削除", role: .destructive) {
                if let client = clientToDelete {
                    Task { await viewModel.deleteClient(client) }
                    clientToDelete = nil
                }
            }
            Button("キャンセル", role: .cancel) {
                clientToDelete = nil
            }
        } message: {
            if let client = clientToDelete {
                Text("「\(client.name)」を削除しますか？")
            }
        }
        .sheet(item: $editingClient) { client in
            EditClientSheet(client: client) { name, furigana in
                Task { await viewModel.updateClient(clientId: client.id, name: name, furigana: furigana) }
            }
        }
    }
}

// MARK: - ClientManagementRow

private struct ClientManagementRow: View {
    let client: FirestoreClient

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(client.name)
                .font(.body)
            if !client.furigana.isEmpty {
                Text(client.furigana)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - EditClientSheet

private struct EditClientSheet: View {
    let client: FirestoreClient
    let onSave: (String, String) -> Void

    @State private var name: String
    @State private var furigana: String
    @Environment(\.dismiss) private var dismiss

    init(client: FirestoreClient, onSave: @escaping (String, String) -> Void) {
        self.client = client
        self.onSave = onSave
        _name = State(initialValue: client.name)
        _furigana = State(initialValue: client.furigana)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名前", text: $name)
                        .autocorrectionDisabled()
                    TextField("ふりがな", text: $furigana)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("利用者を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(name.trimmingCharacters(in: .whitespaces),
                               furigana.trimmingCharacters(in: .whitespaces))
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}
