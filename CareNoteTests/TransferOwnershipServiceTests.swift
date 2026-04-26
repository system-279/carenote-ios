import FirebaseFunctions
import Foundation
import Testing

@testable import CareNote

/// `TransferOwnershipError.map(_:)` の HttpsError → 内部エラー型 mapping を検証する。
///
/// Cloud Function `transferOwnership` (functions/src/transferOwnership.js) が throw する
/// 各 HttpsError code を、UI で表示分岐できる内部エラー型にマッピングする。
@Suite("TransferOwnershipError.map mapping")
struct TransferOwnershipErrorMapTests {
    // MARK: - Functions SDK code mapping

    @Test("unauthenticated code → .unauthenticated")
    func map_unauthenticated() {
        let error = makeFunctionsError(code: .unauthenticated, message: "ログインが必要です")
        #expect(TransferOwnershipError.map(error) == .unauthenticated)
    }

    @Test("permissionDenied code → .permissionDenied")
    func map_permissionDenied() {
        let error = makeFunctionsError(code: .permissionDenied, message: "管理者のみ実行可能です")
        #expect(TransferOwnershipError.map(error) == .permissionDenied)
    }

    @Test("failedPrecondition code → .failedPrecondition")
    func map_failedPrecondition() {
        let error = makeFunctionsError(code: .failedPrecondition, message: "tenantId 不在")
        #expect(TransferOwnershipError.map(error) == .failedPrecondition)
    }

    @Test("invalidArgument code → .invalidArgument(message)")
    func map_invalidArgument() {
        let error = makeFunctionsError(code: .invalidArgument, message: "fromUid must differ from toUid")
        let mapped = TransferOwnershipError.map(error)
        #expect(mapped == .invalidArgument("fromUid must differ from toUid"))
    }

    @Test("notFound code → .notFound")
    func map_notFound() {
        let error = makeFunctionsError(code: .notFound, message: "dryRunId 該当なし")
        #expect(TransferOwnershipError.map(error) == .notFound)
    }

    @Test("alreadyExists code → .alreadyExists")
    func map_alreadyExists() {
        let error = makeFunctionsError(code: .alreadyExists, message: "同じ dryRunId が既に完了")
        #expect(TransferOwnershipError.map(error) == .alreadyExists)
    }

    @Test("internal code → .internal(message)")
    func map_internalError() {
        let error = makeFunctionsError(code: .internal, message: "batch commit failed")
        #expect(TransferOwnershipError.map(error) == .internal("batch commit failed"))
    }

    // MARK: - Non-Functions error

    @Test("Functions 以外の error は .unknown でラップする")
    func map_nonFunctionsError() {
        let error = NSError(domain: "SomeOtherDomain", code: -1, userInfo: nil)
        let mapped = TransferOwnershipError.map(error)
        if case .unknown = mapped {
            // OK
        } else {
            Issue.record("Expected .unknown, got \(mapped)")
        }
    }

    // MARK: - Transient classification (network / quota / SDK unavailable)

    @Test(
        "transient な FunctionsErrorCode は .transient に分類される",
        arguments: [
            FunctionsErrorCode.deadlineExceeded.rawValue,
            FunctionsErrorCode.unavailable.rawValue,
            FunctionsErrorCode.resourceExhausted.rawValue,
            FunctionsErrorCode.cancelled.rawValue,
        ]
    )
    func map_transientFunctionsCode(code: Int) {
        let error = NSError(
            domain: FunctionsErrorDomain,
            code: code,
            userInfo: [NSLocalizedDescriptionKey: "transient"]
        )
        let mapped = TransferOwnershipError.map(error)
        if case .transient = mapped {
            #expect(mapped.isTransient == true)
        } else {
            Issue.record("Expected .transient, got \(mapped)")
        }
    }

    @Test("NSURLErrorDomain (オフライン等) は .transient に分類される")
    func map_urlErrorIsTransient() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let mapped = TransferOwnershipError.map(error)
        if case .transient = mapped {
            #expect(mapped.isTransient == true)
        } else {
            Issue.record("Expected .transient, got \(mapped)")
        }
    }

    @Test("permanent エラーは isTransient == false")
    func permanentErrorsAreNotTransient() {
        let cases: [TransferOwnershipError] = [
            .unauthenticated,
            .permissionDenied,
            .failedPrecondition,
            .invalidArgument("x"),
            .notFound,
            .alreadyExists,
            .internal("y"),
            .malformedResponse,
            .unknown(NSError(domain: "d", code: 1)),
        ]
        for c in cases {
            #expect(c.isTransient == false, "Expected \(c) to be non-transient")
        }
    }

    // MARK: - Helpers

    /// `Functions.functions().httpsCallable(...).call(...)` が throw する形式の
    /// NSError を再現する。実 SDK は domain="com.firebase.functions"、
    /// userInfo に NSLocalizedDescriptionKey でメッセージを格納する。
    private func makeFunctionsError(code: FunctionsErrorCode, message: String) -> NSError {
        NSError(
            domain: FunctionsErrorDomain,
            code: code.rawValue,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
