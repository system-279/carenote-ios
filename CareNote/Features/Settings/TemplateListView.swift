import SwiftData
import SwiftUI

// MARK: - TemplateListView

struct TemplateListView: View {
    @Bindable var viewModel: TemplateListViewModel

    @State private var showCreateSheet = false
    @State private var templateToDelete: OutputTemplate?
    @State private var tenantTemplateToDelete: FirestoreTemplate?
    @State private var tenantTemplateToEdit: FirestoreTemplate?

    var body: some View {
        List {
            if !viewModel.presets.isEmpty {
                Section("プリセット") {
                    ForEach(viewModel.presets) { template in
                        TemplateRow(template: template)
                    }
                }
            }

            Section {
                if viewModel.isLoadingTenantTemplates {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if viewModel.tenantTemplates.isEmpty {
                    ContentUnavailableView(
                        "共有テンプレートなし",
                        systemImage: "person.2.badge.gearshape",
                        description: Text(viewModel.isAdmin
                            ? "「＋新規作成」から組織共有テンプレートを作成できます"
                            : "管理者が作成した共有テンプレートがここに表示されます")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(viewModel.tenantTemplates) { template in
                        TenantTemplateRow(template: template)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if viewModel.isAdmin {
                                    tenantTemplateToEdit = template
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if viewModel.isAdmin {
                                    Button(role: .destructive) {
                                        tenantTemplateToDelete = template
                                    } label: {
                                        Label("削除", systemImage: "trash")
                                    }
                                }
                            }
                    }
                }
            } header: {
                HStack {
                    Text("テナント共有")
                    Image(systemName: "building.2")
                        .font(.caption2)
                }
            }

            Section {
                if viewModel.customs.isEmpty {
                    ContentUnavailableView(
                        "個人テンプレートなし",
                        systemImage: "doc.badge.plus",
                        description: Text("「＋新規作成」からオリジナルのプロンプトを作成できます")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(viewModel.customs) { template in
                        TemplateRow(template: template)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    templateToDelete = template
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                    }
                }
            } header: {
                HStack {
                    Text("個人")
                    Image(systemName: "person")
                        .font(.caption2)
                }
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("テンプレート管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task {
            viewModel.loadTemplates()
            await viewModel.loadTenantTemplates()
        }
        .sheet(isPresented: $showCreateSheet, onDismiss: {
            viewModel.loadTemplates()
            Task { await viewModel.loadTenantTemplates() }
        }) {
            TemplateCreateView(
                tenantId: viewModel.tenantId,
                isAdmin: viewModel.isAdmin
            )
        }
        .alert("テンプレートを削除", isPresented: Binding(
            get: { templateToDelete != nil },
            set: { if !$0 { templateToDelete = nil } }
        )) {
            Button("削除", role: .destructive) {
                if let template = templateToDelete {
                    viewModel.deleteTemplate(template)
                    templateToDelete = nil
                }
            }
            Button("キャンセル", role: .cancel) {
                templateToDelete = nil
            }
        } message: {
            if let template = templateToDelete {
                Text("「\(template.name)」を削除しますか？この操作は取り消せません。")
            }
        }
        .alert("共有テンプレートを削除", isPresented: Binding(
            get: { tenantTemplateToDelete != nil },
            set: { if !$0 { tenantTemplateToDelete = nil } }
        )) {
            Button("削除", role: .destructive) {
                if let template = tenantTemplateToDelete {
                    Task {
                        await viewModel.deleteTenantTemplate(template)
                        tenantTemplateToDelete = nil
                    }
                }
            }
            Button("キャンセル", role: .cancel) {
                tenantTemplateToDelete = nil
            }
        } message: {
            if let template = tenantTemplateToDelete {
                Text("「\(template.name)」をテナント全体から削除しますか？この操作は取り消せません。")
            }
        }
        .sheet(item: $tenantTemplateToEdit) { template in
            TemplateCreateView(
                tenantId: viewModel.tenantId,
                isAdmin: viewModel.isAdmin,
                editingTemplate: template
            )
        }
        .onChange(of: tenantTemplateToEdit) {
            if tenantTemplateToEdit == nil {
                Task { await viewModel.loadTenantTemplates() }
            }
        }
    }
}

// MARK: - TemplateRow

private struct TemplateRow: View {
    let template: OutputTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(template.name)
                    .font(.body)
                    .fontWeight(.medium)

                Spacer()

                Text(template.outputType)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            Text(template.prompt)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - TenantTemplateRow

private struct TenantTemplateRow: View {
    let template: FirestoreTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(template.name)
                    .font(.body)
                    .fontWeight(.medium)

                Spacer()

                Text(template.outputType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            Text(template.prompt)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if !template.createdByName.isEmpty {
                Text("作成者: \(template.createdByName)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    let schema = Schema([RecordingRecord.self, ClientCache.self, OutboxItem.self, OutputTemplate.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])

    NavigationStack {
        TemplateListView(
            viewModel: TemplateListViewModel(
                modelContext: container.mainContext,
                tenantId: "preview-tenant",
                isAdmin: true
            )
        )
    }
}
