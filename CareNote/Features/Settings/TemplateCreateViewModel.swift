import Foundation
import Observation
import os.log
import SwiftData

// MARK: - TemplateScope

enum TemplateScope: String, CaseIterable, Identifiable {
    case personal = "個人"
    case tenant = "テナント共有"

    var id: String { rawValue }
}

// MARK: - TemplateCreateViewModel

@Observable
@MainActor
final class TemplateCreateViewModel {

    var name: String = ""
    var selectedOutputType: OutputType = .custom
    var prompt: String = ""
    var scope: TemplateScope = .personal
    var errorMessage: String?
    var isSaving = false

    let tenantId: String?
    let isAdmin: Bool

    /// 編集モード: 既存テナントテンプレートのID（nilなら新規作成）
    private let editingTemplateId: String?

    private let modelContext: ModelContext
    private let firestoreService: any TemplateManaging
    private let userId: String?
    private let userName: String?
    private static let logger = Logger(subsystem: "jp.carenote.app", category: "TemplateCreateVM")

    init(
        modelContext: ModelContext,
        tenantId: String? = nil,
        isAdmin: Bool = false,
        userId: String? = nil,
        userName: String? = nil,
        firestoreService: any TemplateManaging = FirestoreService(),
        editingTemplate: FirestoreTemplate? = nil
    ) {
        self.modelContext = modelContext
        self.tenantId = tenantId
        self.isAdmin = isAdmin
        self.userId = userId
        self.userName = userName
        self.firestoreService = firestoreService
        self.editingTemplateId = editingTemplate?.id

        if let template = editingTemplate {
            self.name = template.name
            self.prompt = template.prompt
            self.selectedOutputType = OutputType(rawValue: template.outputType) ?? .custom
            self.scope = .tenant
        }
    }

    var isEditing: Bool { editingTemplateId != nil }

    var canSelectTenantScope: Bool { isAdmin && tenantId != nil }

    var isValid: Bool {
        !name.isEmpty && !prompt.isEmpty
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func save() async -> Bool {
        guard isValid else {
            errorMessage = "名前とプロンプトを入力してください"
            return false
        }

        isSaving = true
        defer { isSaving = false }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        if scope == .tenant, let tenantId, isAdmin {
            guard let userId, !userId.isEmpty else {
                errorMessage = "ユーザー情報が取得できません。再度サインインしてください。"
                return false
            }

            do {
                if let editingId = editingTemplateId {
                    // 既存テナントテンプレートの更新
                    try await firestoreService.updateTemplate(
                        tenantId: tenantId,
                        templateId: editingId,
                        name: trimmedName,
                        prompt: trimmedPrompt,
                        outputType: selectedOutputType.rawValue
                    )
                } else {
                    // 新規テナントテンプレートの作成
                    _ = try await firestoreService.createTemplate(
                        tenantId: tenantId,
                        name: trimmedName,
                        prompt: trimmedPrompt,
                        outputType: selectedOutputType.rawValue,
                        createdBy: userId,
                        createdByName: userName ?? ""
                    )
                }
                return true
            } catch {
                Self.logger.error("Failed to save tenant template: \(error.localizedDescription)")
                errorMessage = "共有テンプレートの保存に失敗しました: \(error.localizedDescription)"
                return false
            }
        } else {
            let template = OutputTemplate(
                name: trimmedName,
                prompt: trimmedPrompt,
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
}
