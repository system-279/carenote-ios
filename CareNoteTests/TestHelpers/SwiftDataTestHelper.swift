@testable import CareNote
import Foundation
import SwiftData

/// Process-wide shared ModelContainer for CareNoteTests.
///
/// SwiftData SIGTRAPs when the same `@Model` type is registered in multiple
/// `ModelContainer`s within one process. Per-test containers therefore cannot
/// coexist with the host app's container (Issue #141). This shared container
/// is created lazily once per process and reused by every test; isolation is
/// provided by `cleanup()` which removes all records before each test.
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
            fatalError("Failed to create SharedTestModelContainer: \(error)")
        }
    }()

    /// Reset to an empty store without reallocating the container itself —
    /// reallocation would trigger the SIGTRAP this helper exists to avoid.
    static func cleanup() throws {
        let context = shared.mainContext
        try context.delete(model: RecordingRecord.self)
        try context.delete(model: OutboxItem.self)
        try context.delete(model: ClientCache.self)
        try context.delete(model: OutputTemplate.self)
        try context.save()
    }
}

/// Returns the process-wide shared ModelContainer after cleaning all records.
@MainActor
func makeTestModelContainer() throws -> ModelContainer {
    try SharedTestModelContainer.cleanup()
    return SharedTestModelContainer.shared
}
