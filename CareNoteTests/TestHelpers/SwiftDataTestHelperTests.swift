@testable import CareNote
import Foundation
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
