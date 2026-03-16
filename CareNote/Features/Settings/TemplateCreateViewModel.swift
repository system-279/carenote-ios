import Foundation
import Observation
import SwiftData

// MARK: - TemplateCreateViewModel

@Observable
@MainActor
final class TemplateCreateViewModel {

    var name: String = ""
    var selectedOutputType: OutputType = .custom
    var prompt: String = ""
    var errorMessage: String?

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    var isValid: Bool {
        !name.isEmpty && !prompt.isEmpty
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func save() -> Bool {
        guard isValid else {
            errorMessage = "名前とプロンプトを入力してください"
            return false
        }

        let template = OutputTemplate(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            outputType: selectedOutputType.rawValue,
            isPreset: false
        )
        modelContext.insert(template)

        do {
            try modelContext.save()
            return true
        } catch {
            errorMessage = "保存に失敗しました: \(error.localizedDescription)"
            return false
        }
    }
}
