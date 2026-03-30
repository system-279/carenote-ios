import Foundation
import Observation
import os.log
import SwiftData

// MARK: - TemplateListViewModel

@Observable
@MainActor
final class TemplateListViewModel {

    var templates: [OutputTemplate] = []
    var tenantTemplates: [FirestoreTemplate] = []
    var errorMessage: String?
    var isLoadingTenantTemplates = false

    var presets: [OutputTemplate] { templates.filter(\.isPreset) }
    var customs: [OutputTemplate] { templates.filter { !$0.isPreset } }

    let tenantId: String?
    let isAdmin: Bool

    private let modelContext: ModelContext
    private let firestoreService: any TemplateManaging
    private static let logger = Logger(subsystem: "jp.carenote.app", category: "TemplateListVM")

    init(modelContext: ModelContext, tenantId: String? = nil, isAdmin: Bool = false, firestoreService: any TemplateManaging = FirestoreService()) {
        self.modelContext = modelContext
        self.tenantId = tenantId
        self.isAdmin = isAdmin
        self.firestoreService = firestoreService
    }

    func loadTemplates() {
        let descriptor = FetchDescriptor<OutputTemplate>()
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        templates = fetched.sortedForDisplay()
    }

    func loadTenantTemplates() async {
        guard let tenantId else { return }
        isLoadingTenantTemplates = true
        defer { isLoadingTenantTemplates = false }

        do {
            tenantTemplates = try await firestoreService.fetchTemplates(tenantId: tenantId)
        } catch {
            Self.logger.error("Failed to load tenant templates: \(error.localizedDescription)")
            errorMessage = "共有テンプレートの読み込みに失敗しました"
        }
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

    func deleteTenantTemplate(_ template: FirestoreTemplate) async {
        guard let tenantId, isAdmin else { return }
        do {
            try await firestoreService.deleteTemplate(tenantId: tenantId, templateId: template.id)
            tenantTemplates.removeAll { $0.id == template.id }
        } catch {
            Self.logger.error("Failed to delete tenant template: \(error.localizedDescription)")
            errorMessage = "共有テンプレートの削除に失敗しました"
        }
    }
}
