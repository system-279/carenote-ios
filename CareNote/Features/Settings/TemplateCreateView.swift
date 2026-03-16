import SwiftData
import SwiftUI

// MARK: - TemplateCreateView

struct TemplateCreateView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: TemplateCreateViewModel?

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
                    viewModel = TemplateCreateViewModel(modelContext: modelContext)
                }
            }
            .navigationTitle("テンプレート作成")
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
                    if viewModel.save() {
                        dismiss()
                    }
                } label: {
                    Text("保存")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .disabled(!viewModel.isValid)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    TemplateCreateView()
}
