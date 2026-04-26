@testable import CareNote
import Foundation
import Testing

/// `AccountTransferView.message(for:)` の文言マッピング検証。
/// AC-B5 「管理者権限が必要です」を含む各エラー文言が回帰しないことを保証する。
/// 文言は admin への直接フィードバックなので、リファクタで揺れさせない。
@Suite("AccountTransferView.message(for:) mapping")
struct AccountTransferViewMessageTests {
    @Test func unauthenticated_message() {
        #expect(AccountTransferView.message(for: .unauthenticated)
            == "ログインが必要です。再ログインしてください。")
    }

    @Test func permissionDenied_message() {
        #expect(AccountTransferView.message(for: .permissionDenied)
            == "管理者権限が必要です。")
    }

    @Test func failedPrecondition_message() {
        #expect(AccountTransferView.message(for: .failedPrecondition)
            == "テナント情報が取得できません。サインアウトしてから再ログインしてください。")
    }

    @Test func invalidArgument_withMessage_returnsServerMessage() {
        #expect(AccountTransferView.message(for: .invalidArgument("同一 uid は指定できません"))
            == "同一 uid は指定できません")
    }

    @Test func invalidArgument_emptyMessage_fallsBackToGeneric() {
        #expect(AccountTransferView.message(for: .invalidArgument(""))
            == "入力内容に誤りがあります。")
    }

    @Test func notFound_message() {
        #expect(AccountTransferView.message(for: .notFound)
            == "対象の dryRunId が見つかりません。最初からやり直してください。")
    }

    @Test func alreadyExists_doesNotMisleadAsTransient() {
        // 過去版は「少し時間をおいて再度お試しください」と transient かのように
        // 誤誘導していたが、`alreadyExists` は permanent (同 dryRunId 2 重実行 guard) のため
        // 「最初からやり直す」を案内する文言に修正済み。
        let message = AccountTransferView.message(for: .alreadyExists)
        #expect(message.contains("最初からやり直す"))
        #expect(!message.contains("少し時間をおいて"))
    }

    @Test func internalError_withMessage_includesServerDetail() {
        let message = AccountTransferView.message(for: .internal("batch commit failed"))
        #expect(message.contains("サーバー内部エラー"))
        #expect(message.contains("batch commit failed"))
    }

    @Test func internalError_withNilMessage_doesNotShowNilLiteral() {
        let message = AccountTransferView.message(for: .internal(nil))
        #expect(!message.contains("nil"))
        #expect(message.contains("サーバー内部エラー"))
    }

    @Test func malformedResponse_message() {
        #expect(AccountTransferView.message(for: .malformedResponse)
            == "サーバーからの応答が不正です。アプリを最新版にアップデートしてください。")
    }

    @Test func transient_guidesToRetry() {
        let nsError = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        let message = AccountTransferView.message(for: .transient(nsError))
        #expect(message.contains("ネットワーク") || message.contains("一時"))
        #expect(message.contains("再度お試し"))
    }

    @Test func unknown_includesDomainAndCode() {
        let nsError = NSError(domain: "SomeDomain", code: 42)
        let message = AccountTransferView.message(for: .unknown(nsError))
        #expect(message.contains("SomeDomain"))
        #expect(message.contains("42"))
    }
}
