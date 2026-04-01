@testable import CareNote
import Foundation
import SwiftData

/// Create a ModelContainer backed by a unique temporary file for testing.
/// Each call creates an independent store to avoid cross-test SwiftData conflicts.
/// NOTE: Add new `@Model` types here when introduced to the schema.
@MainActor
func makeTestModelContainer() throws -> ModelContainer {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftdata-test-\(UUID().uuidString).sqlite")
    let config = ModelConfiguration(url: url)
    return try ModelContainer(
        for: RecordingRecord.self, OutboxItem.self, ClientCache.self, OutputTemplate.self,
        configurations: config
    )
}

/// Create a minimal ModelContainer with only ClientCache for lightweight tests.
@MainActor
func makeClientOnlyTestModelContainer() throws -> ModelContainer {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftdata-test-\(UUID().uuidString).sqlite")
    let config = ModelConfiguration(url: url)
    return try ModelContainer(
        for: ClientCache.self,
        configurations: config
    )
}
