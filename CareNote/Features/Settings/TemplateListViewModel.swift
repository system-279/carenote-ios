import Foundation
import Observation
import os.log
import SwiftData

// MARK: - TemplateListViewModel

@Observable
@MainActor
final class TemplateListViewModel {

    var templates: [OutputTemplate] = []
    var errorMessage: String?

    var presets: [OutputTemplate] { templates.filter(\.isPreset) }
    var customs: [OutputTemplate] { templates.filter { !$0.isPreset } }

    private let modelContext: ModelContext
    private static let logger = Logger(subsystem: "jp.carenote.app", category: "TemplateListVM")

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func loadTemplates() {
        let descriptor = FetchDescriptor<OutputTemplate>()
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        templates = fetched.sortedForDisplay()
    }

    func deleteTemplate(_ template: OutputTemplate) {
        guard !template.isPreset else { return }
        modelContext.delete(template)
        do {
            try modelContext.save()
        } catch {
            Self.logger.error("Failed to delete template: \(error.localizedDescription)")
            errorMessage = "削除に失敗しました: \(error.localizedDescription)"
        }
        templates.removeAll { $0.id == template.id }
    }
}
