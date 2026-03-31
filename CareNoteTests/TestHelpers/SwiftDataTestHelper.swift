@testable import CareNote
import Foundation
import SwiftData

/// Create an in-memory ModelContainer for testing.
/// Each call creates an independent container to avoid cross-test state leaks.
@MainActor
func makeTestModelContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: RecordingRecord.self, OutboxItem.self, ClientCache.self, OutputTemplate.self,
        configurations: config
    )
}
