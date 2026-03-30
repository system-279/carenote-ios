import SwiftData
import SwiftUI

// MARK: - TemplateCreateView

struct TemplateCreateView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthViewModel.self) private var authViewModel

    let tenantId: String?
    let isAdmin: Bool
    let editingTemplate: FirestoreTemplate?

    @State private var viewModel: TemplateCreateViewModel?

    init(tenantId: String? = nil, isAdmin: Bool = false, editingTemplate: FirestoreTemplate? = nil) {
        self.tenantId = tenantId
        self.isAdmin = isAdmin
        self.editingTemplate = editingTemplate
    }

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    TemplateCreateForm(viewModel: viewModel, dismiss: dismiss)
                } else {
                    ProgressView()
                }
            }
            .task {
                if viewModel == nil {
                    viewModel = TemplateCreateViewModel(
                        modelContext: modelContext,
                        tenantId: tenantId,
                        isAdmin: isAdmin,
                        userId: authViewModel.authState.userId,
                        userName: authViewModel.displayName,
                        editingTemplate: editingTemplate
                    )
                }
            }
            .navigationTitle(editingTemplate != nil ? "テンプレート編集" : "テンプレート作成")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - TemplateCreateForm

private struct TemplateCreateForm: View {
    @Bindable var viewModel: TemplateCreateViewModel
    let dismiss: DismissAction

    private let outputTypes: [OutputType] = OutputType.allCases

    var body: some View {
        Form {
            if viewModel.canSelectTenantScope && !viewModel.isEditing {
                Section {
                    Picker("保存先", selection: $viewModel.scope) {
                        ForEach(TemplateScope.allCases) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("保存先")
                } footer: {
                    Text(viewModel.scope == .tenant
                        ? "テナント全メンバーが利用できるテンプレートとして保存します"
                        : "このデバイスでのみ利用できる個人テンプレートとして保存します")
                }
            }

            Section("基本情報") {
                TextField("テンプレート名", text: $viewModel.name)

                Picker("出力タイプ", selection: $viewModel.selectedOutputType) {
                    ForEach(outputTypes) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
            }

            Section {
                TextEditor(text: $viewModel.prompt)
                    .frame(minHeight: 200)
                    .font(.body)
            } header: {
                Text("プロンプト")
            } footer: {
                Text("AIへの指示文を記述します。「以下の音声から〇〇を作成してください」のように具体的に記述すると精度が向上します。")
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            Section {
                Button {
                    Task {
                        if await viewModel.save() {
                            dismiss()
                        }
                    }
                } label: {
                    if viewModel.isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("保存")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                    }
                }
                .disabled(!viewModel.isValid || viewModel.isSaving)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    TemplateCreateView(tenantId: "preview-tenant", isAdmin: true)
        .environment(AuthViewModel())
}
