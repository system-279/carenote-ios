@testable import CareNote
import Foundation

// MARK: - MockTemplateService

final class MockTemplateService: @unchecked Sendable, TemplateManaging {
    var fetchResult: [FirestoreTemplate] = []
    var fetchError: Error?
    var createCalledWith: (tenantId: String, name: String, prompt: String, outputType: String, createdBy: String, createdByName: String)?
    var createResult: String = "new-template-id"
    var createError: Error?
    var updateCalledWith: (tenantId: String, templateId: String, name: String, prompt: String, outputType: String)?
    var updateError: Error?
    var deleteCalledWith: (tenantId: String, templateId: String)?
    var deleteError: Error?

    func fetchTemplates(tenantId: String) async throws -> [FirestoreTemplate] {
        if let error = fetchError { throw error }
        return fetchResult
    }

    func createTemplate(tenantId: String, name: String, prompt: String, outputType: String, createdBy: String, createdByName: String) async throws -> String {
        createCalledWith = (tenantId, name, prompt, outputType, createdBy, createdByName)
        if let error = createError { throw error }
        return createResult
    }

    func updateTemplate(tenantId: String, templateId: String, name: String, prompt: String, outputType: String) async throws {
        updateCalledWith = (tenantId, templateId, name, prompt, outputType)
        if let error = updateError { throw error }
    }

    func deleteTemplate(tenantId: String, templateId: String) async throws {
        deleteCalledWith = (tenantId, templateId)
        if let error = deleteError { throw error }
    }
}
