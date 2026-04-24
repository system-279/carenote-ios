import FirebaseFirestore
import Foundation
import Testing

@testable import CareNote

/// FirestoreError.isTransient の分類ロジックを検証する。
///
/// `isTransient` は polling の silent catch 可視化（Issue #194）で追加された判定ロジック。
/// transient (deadlineExceeded / resourceExhausted / unavailable) のみ true を返し、
/// 他はすべて permanent 扱いで false を返す。
@Suite("FirestoreError.isTransient classification")
struct FirestoreErrorTests {
    // MARK: - Transient codes

    @Test(
        "Firestore SDK transient code は true を返す",
        arguments: [
            FirestoreErrorCode.deadlineExceeded.rawValue,
            FirestoreErrorCode.resourceExhausted.rawValue,
            FirestoreErrorCode.unavailable.rawValue,
        ]
    )
    func operationFailed_withTransientCode_isTransient(code: Int) {
        let underlying = NSError(domain: FirestoreErrorDomain, code: code)
        let error = FirestoreError.operationFailed(underlying)
        #expect(error.isTransient == true)
    }

    // MARK: - Permanent codes

    @Test(
        "Firestore SDK permanent code は false を返す",
        arguments: [
            FirestoreErrorCode.permissionDenied.rawValue,
            FirestoreErrorCode.unauthenticated.rawValue,
            FirestoreErrorCode.notFound.rawValue,
            FirestoreErrorCode.invalidArgument.rawValue,
            FirestoreErrorCode.internal.rawValue,
        ]
    )
    func operationFailed_withPermanentCode_isNotTransient(code: Int) {
        let underlying = NSError(domain: FirestoreErrorDomain, code: code)
        let error = FirestoreError.operationFailed(underlying)
        #expect(error.isTransient == false)
    }

    // MARK: - Wrong domain (load-bearing for typo-guard)

    @Test("FirestoreErrorDomain 以外のドメインは code が何であれ false を返す")
    func operationFailed_wrongDomain_isNotTransient() {
        // transient に該当するコード (14 = unavailable) でも、ドメインが違えば transient 扱いしない
        let underlying = NSError(domain: NSURLErrorDomain, code: 14)
        let error = FirestoreError.operationFailed(underlying)
        #expect(error.isTransient == false)
    }

    // MARK: - Non-operationFailed cases

    @Test("encodingFailed は permanent 扱い")
    func encodingFailed_isNotTransient() {
        let error = FirestoreError.encodingFailed(
            NSError(domain: "Test", code: 0)
        )
        #expect(error.isTransient == false)
    }

    @Test("decodingFailed は permanent 扱い")
    func decodingFailed_isNotTransient() {
        let error = FirestoreError.decodingFailed(
            NSError(domain: "Test", code: 0)
        )
        #expect(error.isTransient == false)
    }

    @Test("documentNotFound は permanent 扱い")
    func documentNotFound_isNotTransient() {
        let error = FirestoreError.documentNotFound("path/to/doc")
        #expect(error.isTransient == false)
    }
}

/// FirestoreError.map (Issue #193) の分類ロジックを検証する。
///
/// Firestore SDK が throw した NSError を `permissionDenied` / `notFound` /
/// `operationFailed` にマップする。UI 層で permissionDenied=管理者依頼、
/// notFound=idempotent success、transient=再試行ボタン付き alert、
/// その他 permanent=generic alert と分岐させる前提。
@Suite("FirestoreError.map classification (Issue #193)")
struct FirestoreErrorMapTests {
    // MARK: - Classified cases

    @Test("FirestoreErrorDomain + permissionDenied (7) → .permissionDenied")
    func map_permissionDenied() {
        let ns = NSError(
            domain: FirestoreErrorDomain,
            code: FirestoreErrorCode.permissionDenied.rawValue
        )
        let mapped = FirestoreError.map(ns)
        if case .permissionDenied = mapped {
            // pass
        } else {
            Issue.record("Expected .permissionDenied, got \(mapped)")
        }
    }

    @Test("FirestoreErrorDomain + notFound (5) → .notFound")
    func map_notFound() {
        let ns = NSError(
            domain: FirestoreErrorDomain,
            code: FirestoreErrorCode.notFound.rawValue
        )
        let mapped = FirestoreError.map(ns)
        if case .notFound = mapped {
            // pass
        } else {
            Issue.record("Expected .notFound, got \(mapped)")
        }
    }

    // MARK: - Fallthrough to operationFailed

    @Test(
        "FirestoreErrorDomain + transient code → .operationFailed (isTransient=true)",
        arguments: [
            FirestoreErrorCode.deadlineExceeded.rawValue,
            FirestoreErrorCode.resourceExhausted.rawValue,
            FirestoreErrorCode.unavailable.rawValue,
        ]
    )
    func map_transientCode_fallsThroughToOperationFailed(code: Int) {
        let ns = NSError(domain: FirestoreErrorDomain, code: code)
        let mapped = FirestoreError.map(ns)
        guard case .operationFailed = mapped else {
            Issue.record("Expected .operationFailed for transient code \(code), got \(mapped)")
            return
        }
        #expect(mapped.isTransient == true)
    }

    @Test(
        "FirestoreErrorDomain + permanent non-classified code → .operationFailed (isTransient=false)",
        arguments: [
            FirestoreErrorCode.internal.rawValue,
            FirestoreErrorCode.invalidArgument.rawValue,
            FirestoreErrorCode.unauthenticated.rawValue,
        ]
    )
    func map_permanentCode_fallsThroughToOperationFailed(code: Int) {
        let ns = NSError(domain: FirestoreErrorDomain, code: code)
        let mapped = FirestoreError.map(ns)
        guard case .operationFailed = mapped else {
            Issue.record("Expected .operationFailed for permanent code \(code), got \(mapped)")
            return
        }
        #expect(mapped.isTransient == false)
    }

    // MARK: - Wrong domain (load-bearing for typo-guard)

    @Test("FirestoreErrorDomain 以外のドメインは code に関わらず .operationFailed 扱い")
    func map_wrongDomain_fallsThroughToOperationFailed() {
        // permissionDenied に該当するコード (7) でも、ドメインが違えば .permissionDenied にしない
        let ns = NSError(
            domain: NSURLErrorDomain,
            code: FirestoreErrorCode.permissionDenied.rawValue
        )
        let mapped = FirestoreError.map(ns)
        if case .operationFailed = mapped {
            // pass
        } else {
            Issue.record("Expected .operationFailed for wrong domain, got \(mapped)")
        }
    }
}
