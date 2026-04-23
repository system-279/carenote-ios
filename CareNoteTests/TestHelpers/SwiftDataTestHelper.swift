@testable import CareNote
import Foundation
import SwiftData

/// Process-wide shared ModelContainer for CareNoteTests.
///
/// Reuses one container for all tests because SwiftData SIGTRAPs when the
/// same `@Model` type is registered in multiple `ModelContainer`s within
/// one process (Issue #141). `cleanup()` empties the store between tests
/// instead of reallocating, which would re-trigger the SIGTRAP.
///
/// Diagnostic contract (Issue #170 H2/H3): container-init `fatalError` and
/// per-model `cleanup()` failures both route through `formatNSError` so the
/// `NSError` shape that names the offending `@Model` on schema drift is
/// never lost. Without this, a partial cleanup or a drift crash surfaces
/// only as `delete(model:)` / `ModelContainer(for:)` throwing — with no
/// indication of which type is at fault.
@MainActor
enum SharedTestModelContainer {
    static let shared: ModelContainer = {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftdata-test-shared-\(UUID().uuidString).sqlite")
        let config = ModelConfiguration(url: url)
        do {
            return try ModelContainer(
                for: RecordingRecord.self, OutboxItem.self, ClientCache.self, OutputTemplate.self,
                configurations: config
            )
        } catch {
            fatalError("Failed to create SharedTestModelContainer.\n\(formatNSError(error))")
        }
    }()

    static func cleanup() throws {
        let context = shared.mainContext
        try delete(RecordingRecord.self, in: context)
        try delete(OutboxItem.self, in: context)
        try delete(ClientCache.self, in: context)
        try delete(OutputTemplate.self, in: context)
        do {
            try context.save()
        } catch {
            reportCleanupFailure(model: "save()", error: error)
            throw error
        }
    }

    private static func delete<Model: PersistentModel>(
        _ type: Model.Type,
        in context: ModelContext
    ) throws {
        do {
            try context.delete(model: type)
        } catch {
            reportCleanupFailure(model: String(describing: type), error: error)
            throw error
        }
    }

    private static func reportCleanupFailure(model: String, error: Error) {
        let message = "SharedTestModelContainer.cleanup() failed for \(model).\n\(formatNSError(error))\n"
        FileHandle.standardError.write(Data(message.utf8))
    }

    private static func formatNSError(_ error: Error) -> String {
        let ns = error as NSError
        return """
              domain: \(ns.domain)
              code: \(ns.code)
              description: \(ns.localizedDescription)
              userInfo: \(ns.userInfo)
              raw: \(error)
            """
    }
}

/// Returns the process-wide shared ModelContainer after cleaning all records.
@MainActor
func makeTestModelContainer() throws -> ModelContainer {
    try SharedTestModelContainer.cleanup()
    return SharedTestModelContainer.shared
}
