import SwiftData
import SwiftUI

// MARK: - TemplateListView

struct TemplateListView: View {
    @Bindable var viewModel: TemplateListViewModel

    @State private var showCreateSheet = false
    @State private var templateToDelete: OutputTemplate?

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
                if viewModel.customs.isEmpty {
                    ContentUnavailableView(
                        "カスタムテンプレートなし",
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
                Text("カスタム")
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
        }
        .sheet(isPresented: $showCreateSheet, onDismiss: {
            viewModel.loadTemplates()
        }) {
            TemplateCreateView()
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

// MARK: - Preview

#Preview {
    let schema = Schema([RecordingRecord.self, ClientCache.self, OutboxItem.self, OutputTemplate.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])

    NavigationStack {
        TemplateListView(
            viewModel: TemplateListViewModel(modelContext: container.mainContext)
        )
    }
}
