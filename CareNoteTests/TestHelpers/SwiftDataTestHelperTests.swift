@testable import CareNote
import Foundation
import SwiftData
import Testing

/// Pins the diagnostic string shape produced by `SharedTestModelContainer.formatNSError`.
///
/// A typo in the interpolation template (missing key, wrong label) would
/// silently degrade the very signal Issue #170 H2/H3 adds: the offending
/// `@Model` type name + `NSError` shape on cleanup failure / schema drift.
/// Integration tests that inject a cleanup failure live in the H5
/// follow-up PR — the format function itself is pure and pinned here.
@MainActor
@Suite("SharedTestModelContainer formatNSError")
struct SwiftDataTestHelperTests {

    @Test("formatNSError surfaces domain, code, description, and userInfo")
    func formatNSError_includesAllNSErrorFields() {
        let error = NSError(
            domain: "TestDomain.SchemaDrift",
            code: 4242,
            userInfo: [
                NSLocalizedDescriptionKey: "model registration mismatch",
                "NSUnderlyingError": "stub-underlying",
                "offendingModel": "OutboxItem"
            ]
        )

        let formatted = SharedTestModelContainer.formatNSError(error)

        #expect(formatted.contains("TestDomain.SchemaDrift"))
        #expect(formatted.contains("4242"))
        #expect(formatted.contains("model registration mismatch"))
        #expect(formatted.contains("offendingModel"))
        #expect(formatted.contains("OutboxItem"))
        #expect(formatted.contains("stub-underlying"))
    }

    @Test("formatNSError labels every NSError field for grep-ability")
    func formatNSError_hasLabeledFields() {
        let error = NSError(domain: "X", code: 0, userInfo: [:])

        let formatted = SharedTestModelContainer.formatNSError(error)

        #expect(formatted.contains("domain:"))
        #expect(formatted.contains("code:"))
        #expect(formatted.contains("description:"))
        #expect(formatted.contains("userInfo:"))
        #expect(formatted.contains("raw:"))
    }
}

/// Pins the behavioral invariants that the rest of the test suite relies on
/// without stating them (Issue #170 H5):
///   - `SharedTestModelContainer.shared` is a process-wide singleton —
///     reallocating would reproduce the SIGTRAP from Issue #141.
///   - `cleanup()` actually empties every `@Model` type, not just a subset —
///     adding a new `@Model` without updating `cleanup()` fails `cleanupEmptiesAll4Models`.
///   - `makeTestModelContainer()` guarantees an empty store on every call,
///     regardless of what the previous caller left behind.
///
/// These tests act as a regression net for PR #185's cleanup hardening and
/// for any future refactor of the helper.
///
/// **Requires non-parallelized test execution** (PR #173 pins
/// `parallelizable=NO` on the scheme + `lint-scheme-parallel.sh`). If that
/// setting is removed, `cleanupEmptiesAll4Models` and
/// `makeTestModelContainerClearsLeftoverBeforeReturn` will produce race-
/// induced false positives because the shared container is mutated from
/// multiple test contexts concurrently.
@MainActor
@Suite("SharedTestModelContainer invariants (Issue #170 H5)")
struct SharedTestModelContainerInvariantsTests {

    @Test("shared is a process-wide singleton (static-let stability)")
    func sharedReturnsSameInstance() {
        let first = SharedTestModelContainer.shared
        let second = SharedTestModelContainer.shared
        #expect(
            first === second,
            "shared must be a singleton; flipping `static let` to `static var`/factory reintroduces the Issue #141 SIGTRAP"
        )
    }

    @Test("cleanup empties all 4 @Model types registered in the shared container")
    func cleanupEmptiesAll4Models() async throws {
        // `makeTestModelContainer()` internally calls cleanup(), so this test
        // always starts from an empty store regardless of what the previous
        // test inside this process left behind.
        let container = try makeTestModelContainer()
        let context = container.mainContext

        let recordingId = UUID()
        context.insert(RecordingRecord(
            id: recordingId,
            clientId: "client-1",
            clientName: "テスト利用者",
            scene: RecordingScene.visit.rawValue,
            localAudioPath: "/tmp/invariant-test.m4a"
        ))
        context.insert(OutboxItem(recordingId: recordingId))
        context.insert(ClientCache(id: "client-1", name: "テスト利用者", furigana: "テスト"))
        context.insert(OutputTemplate(name: "テストテンプレ", prompt: "要約して"))
        try context.save()

        try SharedTestModelContainer.cleanup()

        try expectEmpty(RecordingRecord.self, in: context)
        try expectEmpty(OutboxItem.self, in: context)
        try expectEmpty(ClientCache.self, in: context)
        try expectEmpty(OutputTemplate.self, in: context)
    }

    @Test("makeTestModelContainer returns an empty store even when the previous caller left data (sequential round-trip)")
    func makeTestModelContainerClearsLeftoverBeforeReturn() throws {
        // 1st use: leave data behind without calling cleanup() — this is the
        // exact state the shared container would be in if a previous suite
        // forgot to tear down before the next suite started. Swift Testing
        // does not provide deterministic ordering between `@Suite`s, so we
        // simulate "the next consumer arrives" with a sequential round-trip
        // inside a single test instead of a literal cross-suite fixture.
        let firstContainer = SharedTestModelContainer.shared
        firstContainer.mainContext.insert(OutboxItem(recordingId: UUID()))
        try firstContainer.mainContext.save()

        // 2nd use: a subsequent caller must get an empty store regardless of
        // what the previous consumer left.
        let secondContainer = try makeTestModelContainer()
        #expect(
            firstContainer === secondContainer,
            "Must return the same process-wide singleton (reallocation would hit Issue #141)"
        )
        #expect(
            try secondContainer.mainContext.fetchCount(FetchDescriptor<OutboxItem>()) == 0,
            "makeTestModelContainer() must clean the store before returning"
        )
    }

    /// Asserts the given `@Model` type has zero rows. Hoists the model name
    /// from compile-time type info (avoiding a Stringly-typed failure message
    /// that would silently rot on a model rename).
    private func expectEmpty<Model: PersistentModel>(
        _ type: Model.Type,
        in context: ModelContext,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let count = try context.fetchCount(FetchDescriptor<Model>())
        #expect(
            count == 0,
            "cleanup() must delete \(String(describing: type)) (forgotten → cross-suite contamination)",
            sourceLocation: sourceLocation
        )
    }
}
