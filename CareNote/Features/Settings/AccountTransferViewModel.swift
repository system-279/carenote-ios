import Foundation
import Observation

/// admin 専用「アカウント引き継ぎ」UI の状態機械。
///
/// `transferOwnership` Cloud Function (ADR-008 Phase 1) を 2 段階 (dryRun → confirm)
/// で呼び出し、各ステップの状態と入力 validation を保持する。
@MainActor
@Observable
final class AccountTransferViewModel {
    /// state machine の状態。
    /// `failed` 以外は遷移可能な経路が一意 (idle → dryRunInFlight → preview → confirmInFlight → completed)。
    enum State: Sendable, Equatable {
        case idle
        case dryRunInFlight
        case preview(dryRunId: String, counts: TransferOwnershipCounts)
        case confirmInFlight(dryRunId: String)
        case completed(updated: TransferOwnershipCounts)
        case failed(TransferOwnershipError)
    }

    var state: State = .idle
    var fromUidInput: String = ""
    var toUidInput: String = ""
    /// 二段階 confirm のチェックボックス。`preview` で `true` になって初めて
    /// `confirmTransfer()` の実行が許可される。
    var confirmCheckboxChecked: Bool = false

    private let service: any TransferOwnershipServicing

    init(service: any TransferOwnershipServicing) {
        self.service = service
    }

    /// preview 状態かつ checkbox チェック済の場合のみ true。UI 側は確定ボタンの enabled に bind する。
    var canConfirm: Bool {
        if case .preview = state, confirmCheckboxChecked { return true }
        return false
    }

    /// 入力検証 → dryRun 呼出。空文字 / 同一 uid は server へ行く前にローカルで弾く。
    /// (server 側 `transferOwnership.js` も同等の検証を持つが、UX 改善のため UI でも行う)
    func runDryRun() async {
        let from = fromUidInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = toUidInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty else {
            state = .failed(.invalidArgument("旧 uid を入力してください"))
            return
        }
        guard !to.isEmpty else {
            state = .failed(.invalidArgument("新 uid を入力してください"))
            return
        }
        guard from != to else {
            state = .failed(.invalidArgument("同一 uid は指定できません"))
            return
        }
        // 直前の preview / completed / failed で checkbox が true のまま残っていると、
        // 新しい preview で confirm ボタンが即時 enabled になり二段階 confirm が崩れる。
        // dryRun 開始時に必ずリセットする。
        confirmCheckboxChecked = false
        state = .dryRunInFlight
        do {
            let result = try await service.dryRun(fromUid: from, toUid: to)
            state = .preview(dryRunId: result.dryRunId, counts: result.counts)
        } catch let error as TransferOwnershipError {
            state = .failed(error)
        } catch {
            state = .failed(.unknown(error as NSError))
        }
    }

    /// preview 状態 + checkbox チェック済の場合のみ confirm を呼ぶ。
    /// それ以外で呼ばれた場合は no-op (UI 制約からの呼び出し漏れを構造的に無害化)。
    func confirmTransfer() async {
        guard case let .preview(dryRunId, _) = state, confirmCheckboxChecked else { return }
        state = .confirmInFlight(dryRunId: dryRunId)
        do {
            let result = try await service.confirm(dryRunId: dryRunId)
            state = .completed(updated: result.updated)
        } catch let error as TransferOwnershipError {
            state = .failed(error)
        } catch {
            state = .failed(.unknown(error as NSError))
        }
    }

    /// 入力と状態をすべてクリアして初期画面へ戻す。
    /// completed / failed 後の「もう一度」ボタンや、画面離脱時に呼ぶ。
    func reset() {
        state = .idle
        fromUidInput = ""
        toUidInput = ""
        confirmCheckboxChecked = false
    }
}
