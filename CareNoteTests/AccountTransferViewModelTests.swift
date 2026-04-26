@testable import CareNote
import Foundation
import Testing

/// `AccountTransferViewModel` の状態遷移と入力 validation を検証する。
@Suite("AccountTransferViewModel state machine", .serialized)
struct AccountTransferViewModelTests {
    // MARK: - Stub service

    private final class StubTransferOwnershipService: TransferOwnershipServicing, @unchecked Sendable {
        var dryRunResult: Result<TransferOwnershipDryRunResult, TransferOwnershipError>?
        var confirmResult: Result<TransferOwnershipConfirmResult, TransferOwnershipError>?
        private(set) var dryRunCalls: [(fromUid: String, toUid: String)] = []
        private(set) var confirmCalls: [String] = []

        func dryRun(fromUid: String, toUid: String) async throws -> TransferOwnershipDryRunResult {
            dryRunCalls.append((fromUid, toUid))
            switch dryRunResult {
            case let .success(value):
                return value
            case let .failure(error):
                throw error
            case .none:
                Issue.record("dryRunResult not set on stub")
                throw TransferOwnershipError.malformedResponse
            }
        }

        func confirm(dryRunId: String) async throws -> TransferOwnershipConfirmResult {
            confirmCalls.append(dryRunId)
            switch confirmResult {
            case let .success(value):
                return value
            case let .failure(error):
                throw error
            case .none:
                Issue.record("confirmResult not set on stub")
                throw TransferOwnershipError.malformedResponse
            }
        }
    }

    private static let sampleCounts = TransferOwnershipCounts(recordings: 12, templates: 3, whitelist: 1)
    private static let sampleDryRunId = "abc123"

    // MARK: - Initial state

    @Test @MainActor
    func 初期状態はidle() {
        let stub = StubTransferOwnershipService()
        let vm = AccountTransferViewModel(service: stub)
        #expect(vm.state == .idle)
        #expect(vm.fromUidInput == "")
        #expect(vm.toUidInput == "")
        #expect(vm.confirmCheckboxChecked == false)
        #expect(vm.canConfirm == false)
    }

    // MARK: - Input validation

    @Test @MainActor
    func 旧uidが空文字の場合invalidArgumentで停止() async {
        let stub = StubTransferOwnershipService()
        let vm = AccountTransferViewModel(service: stub)
        vm.fromUidInput = "  "
        vm.toUidInput = "newUid"
        await vm.runDryRun()
        if case let .failed(error) = vm.state, case .invalidArgument = error {
            // OK
        } else {
            Issue.record("Expected .failed(.invalidArgument), got \(vm.state)")
        }
        #expect(stub.dryRunCalls.isEmpty)
    }

    @Test @MainActor
    func 新uidが空文字の場合invalidArgumentで停止() async {
        let stub = StubTransferOwnershipService()
        let vm = AccountTransferViewModel(service: stub)
        vm.fromUidInput = "oldUid"
        vm.toUidInput = ""
        await vm.runDryRun()
        if case let .failed(error) = vm.state, case .invalidArgument = error {
            // OK
        } else {
            Issue.record("Expected .failed(.invalidArgument), got \(vm.state)")
        }
        #expect(stub.dryRunCalls.isEmpty)
    }

    @Test @MainActor
    func fromUidとtoUidが同一だとinvalidArgumentで停止() async {
        let stub = StubTransferOwnershipService()
        let vm = AccountTransferViewModel(service: stub)
        vm.fromUidInput = "sameUid"
        vm.toUidInput = "sameUid"
        await vm.runDryRun()
        // 文言は admin への直接的なフィードバック。リファクタで揺れさせない。
        #expect(vm.state == .failed(.invalidArgument("同一 uid は指定できません")))
        #expect(stub.dryRunCalls.isEmpty)
    }

    @Test @MainActor
    func 入力前後の空白はtrimしてサービスへ渡す() async {
        let stub = StubTransferOwnershipService()
        stub.dryRunResult = .success(
            TransferOwnershipDryRunResult(dryRunId: Self.sampleDryRunId, counts: Self.sampleCounts)
        )
        let vm = AccountTransferViewModel(service: stub)
        vm.fromUidInput = "  oldUid  "
        vm.toUidInput = "\tnewUid\n"
        await vm.runDryRun()
        #expect(stub.dryRunCalls.count == 1)
        #expect(stub.dryRunCalls.first?.fromUid == "oldUid")
        #expect(stub.dryRunCalls.first?.toUid == "newUid")
    }

    // MARK: - dryRun success / failure

    @Test @MainActor
    func dryRun成功でpreview状態に遷移する() async {
        let stub = StubTransferOwnershipService()
        stub.dryRunResult = .success(
            TransferOwnershipDryRunResult(dryRunId: Self.sampleDryRunId, counts: Self.sampleCounts)
        )
        let vm = AccountTransferViewModel(service: stub)
        vm.fromUidInput = "oldUid"
        vm.toUidInput = "newUid"
        await vm.runDryRun()
        #expect(vm.state == .preview(dryRunId: Self.sampleDryRunId, counts: Self.sampleCounts))
    }

    @Test @MainActor
    func dryRun失敗でfailed状態に遷移する() async {
        let stub = StubTransferOwnershipService()
        stub.dryRunResult = .failure(.permissionDenied)
        let vm = AccountTransferViewModel(service: stub)
        vm.fromUidInput = "oldUid"
        vm.toUidInput = "newUid"
        await vm.runDryRun()
        #expect(vm.state == .failed(.permissionDenied))
    }

    // MARK: - Two-step confirm

    @Test @MainActor
    func preview状態でcheckbox未チェックだとcanConfirmはfalse() async {
        let stub = StubTransferOwnershipService()
        stub.dryRunResult = .success(
            TransferOwnershipDryRunResult(dryRunId: Self.sampleDryRunId, counts: Self.sampleCounts)
        )
        let vm = AccountTransferViewModel(service: stub)
        vm.fromUidInput = "oldUid"
        vm.toUidInput = "newUid"
        await vm.runDryRun()
        #expect(vm.canConfirm == false)
        vm.confirmCheckboxChecked = true
        #expect(vm.canConfirm == true)
    }

    @Test @MainActor
    func checkbox未チェックでconfirmTransferを呼んでも状態変化しない() async {
        let stub = StubTransferOwnershipService()
        stub.dryRunResult = .success(
            TransferOwnershipDryRunResult(dryRunId: Self.sampleDryRunId, counts: Self.sampleCounts)
        )
        stub.confirmResult = .success(
            TransferOwnershipConfirmResult(updated: Self.sampleCounts)
        )
        let vm = AccountTransferViewModel(service: stub)
        vm.fromUidInput = "oldUid"
        vm.toUidInput = "newUid"
        await vm.runDryRun()
        // checkbox 未チェックで confirm
        await vm.confirmTransfer()
        #expect(vm.state == .preview(dryRunId: Self.sampleDryRunId, counts: Self.sampleCounts))
        #expect(stub.confirmCalls.isEmpty)
    }

    @Test @MainActor
    func checkboxチェック済でconfirm成功するとcompletedに遷移する() async {
        let stub = StubTransferOwnershipService()
        stub.dryRunResult = .success(
            TransferOwnershipDryRunResult(dryRunId: Self.sampleDryRunId, counts: Self.sampleCounts)
        )
        stub.confirmResult = .success(
            TransferOwnershipConfirmResult(updated: Self.sampleCounts)
        )
        let vm = AccountTransferViewModel(service: stub)
        vm.fromUidInput = "oldUid"
        vm.toUidInput = "newUid"
        await vm.runDryRun()
        vm.confirmCheckboxChecked = true
        await vm.confirmTransfer()
        #expect(vm.state == .completed(updated: Self.sampleCounts))
        #expect(stub.confirmCalls == [Self.sampleDryRunId])
    }

    @Test @MainActor
    func confirm失敗でfailedに遷移する() async {
        let stub = StubTransferOwnershipService()
        stub.dryRunResult = .success(
            TransferOwnershipDryRunResult(dryRunId: Self.sampleDryRunId, counts: Self.sampleCounts)
        )
        stub.confirmResult = .failure(.alreadyExists)
        let vm = AccountTransferViewModel(service: stub)
        vm.fromUidInput = "oldUid"
        vm.toUidInput = "newUid"
        await vm.runDryRun()
        vm.confirmCheckboxChecked = true
        await vm.confirmTransfer()
        #expect(vm.state == .failed(.alreadyExists))
    }

    // MARK: - Reset

    // MARK: - Two-step confirm safety: re-run dryRun must reset checkbox

    /// preview 状態で checkbox を true にした後、入力を変えて再 dryRun した時、
    /// checkbox が true のまま残ると新しい preview で confirm ボタンが即時 enabled になり
    /// 二段階 confirm の不変条件 (preview ∧ checkbox=true) が崩れる。
    /// dryRun 開始時に必ずリセットすることを構造的に固定する。
    @Test @MainActor
    func dryRunを再実行するとconfirmCheckboxはリセットされる() async {
        let stub = StubTransferOwnershipService()
        stub.dryRunResult = .success(
            TransferOwnershipDryRunResult(dryRunId: Self.sampleDryRunId, counts: Self.sampleCounts)
        )
        let vm = AccountTransferViewModel(service: stub)
        vm.fromUidInput = "oldUid"
        vm.toUidInput = "newUid"
        await vm.runDryRun()
        vm.confirmCheckboxChecked = true
        #expect(vm.canConfirm == true)

        // 入力を変えて再 dryRun
        vm.toUidInput = "anotherNewUid"
        await vm.runDryRun()
        // 新しい preview で checkbox はリセットされ、canConfirm は false に戻る
        #expect(vm.confirmCheckboxChecked == false)
        #expect(vm.canConfirm == false)
    }

    @Test @MainActor
    func resetでidle状態に戻り入力もクリアされる() async {
        let stub = StubTransferOwnershipService()
        stub.dryRunResult = .success(
            TransferOwnershipDryRunResult(dryRunId: Self.sampleDryRunId, counts: Self.sampleCounts)
        )
        let vm = AccountTransferViewModel(service: stub)
        vm.fromUidInput = "oldUid"
        vm.toUidInput = "newUid"
        vm.confirmCheckboxChecked = true
        await vm.runDryRun()
        vm.reset()
        #expect(vm.state == .idle)
        #expect(vm.fromUidInput == "")
        #expect(vm.toUidInput == "")
        #expect(vm.confirmCheckboxChecked == false)
    }
}
