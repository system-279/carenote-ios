import SwiftUI

/// admin 専用「アカウント引き継ぎ」UI。
///
/// `AccountTransferViewModel` の state machine に bind して、入力 → dryRun → preview →
/// 二段階 confirm → 結果表示の 1 画面を提供する。
struct AccountTransferView: View {
    @State private var viewModel: AccountTransferViewModel

    init(service: any TransferOwnershipServicing = TransferOwnershipService()) {
        self._viewModel = State(initialValue: AccountTransferViewModel(service: service))
    }

    var body: some View {
        Form {
            Section {
                Text("旧アカウントの録音・テンプレート・ホワイトリスト登録を新アカウントに引き継ぎます。改姓等で uid が変わったメンバーが対象です。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("引き継ぎ元・先 (uid)") {
                TextField("旧 uid (Firebase Auth uid)", text: $viewModel.fromUidInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(isInputDisabled)
                    .accessibilityLabel("旧アカウントの UID")
                TextField("新 uid (Firebase Auth uid)", text: $viewModel.toUidInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(isInputDisabled)
                    .accessibilityLabel("新アカウントの UID")
            }

            Section {
                Button {
                    Task { await viewModel.runDryRun() }
                } label: {
                    if case .dryRunInFlight = viewModel.state {
                        HStack {
                            ProgressView()
                            Text("件数を確認中…")
                        }
                    } else {
                        Label("件数プレビュー (dryRun)", systemImage: "magnifyingglass")
                    }
                }
                .disabled(isInputDisabled)
            }

            previewSection
            completedSection
            failedSection
        }
        .navigationTitle("アカウント引き継ぎ")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Conditional sections

    @ViewBuilder
    private var previewSection: some View {
        if case let .preview(_, counts) = viewModel.state {
            Section("引き継ぎ対象の件数") {
                LabeledContent("録音 (recordings)") { Text("\(counts.recordings) 件") }
                LabeledContent("テンプレート (templates)") { Text("\(counts.templates) 件") }
                LabeledContent("ホワイトリスト (whitelist)") { Text("\(counts.whitelist) 件") }
            }
            Section {
                Toggle(
                    "上記の件数で引き継ぎを実行することを確認しました",
                    isOn: $viewModel.confirmCheckboxChecked
                )
                Button(role: .destructive) {
                    Task { await viewModel.confirmTransfer() }
                } label: {
                    Label("引き継ぎを実行", systemImage: "arrow.right.arrow.left")
                }
                .disabled(!viewModel.canConfirm)
            } header: {
                Text("最終確認")
            } footer: {
                Text("実行後、旧 uid の所有データは新 uid へ書き換わります。書き換えはチェックポイント方式で中断再開可能です。")
                    .font(.caption2)
            }
        } else if case let .confirmInFlight(dryRunId) = viewModel.state {
            Section {
                HStack {
                    ProgressView()
                    Text("引き継ぎを実行中… (id: \(dryRunId))")
                }
            }
        }
    }

    @ViewBuilder
    private var completedSection: some View {
        if case let .completed(updated) = viewModel.state {
            Section {
                LabeledContent("録音") { Text("\(updated.recordings) 件 更新") }
                LabeledContent("テンプレート") { Text("\(updated.templates) 件 更新") }
                LabeledContent("ホワイトリスト") { Text("\(updated.whitelist) 件 更新") }
                Button {
                    viewModel.reset()
                } label: {
                    Label("画面をリセット", systemImage: "arrow.counterclockwise")
                }
            } header: {
                Text("引き継ぎ完了")
            } footer: {
                Text("migrationLogs に実行記録が保存されました。新 uid で改めてログインすると引き継いだデータが表示されます。")
                    .font(.caption2)
            }
        }
    }

    @ViewBuilder
    private var failedSection: some View {
        if case let .failed(error) = viewModel.state {
            Section("エラー") {
                Label(Self.message(for: error), systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
                Button {
                    viewModel.reset()
                } label: {
                    Label("最初からやり直す", systemImage: "arrow.counterclockwise")
                }
            }
        }
    }

    // MARK: - Helpers

    /// 実行中・preview/completed/failed 状態では入力ロック。
    /// 特に preview 状態で uid を編集できると、表示中の counts と confirm 実行内容が
    /// ズレる (二段階 confirm の安全性違反)。idle に戻すには「最初からやり直す」/「画面をリセット」を経由させる。
    private var isInputDisabled: Bool {
        switch viewModel.state {
        case .idle:
            return false
        case .dryRunInFlight, .confirmInFlight, .preview, .completed, .failed:
            return true
        }
    }

    /// `TransferOwnershipError` をユーザー向け文言にマップする。
    /// SwiftUI `View` は `@MainActor` 隔離されるが、本関数は pure function (state 非依存) のため
    /// `nonisolated` で外部 (テスト等) から MainActor 跨ぎでも呼び出せるようにする。
    nonisolated static func message(for error: TransferOwnershipError) -> String {
        switch error {
        case .unauthenticated:
            return "ログインが必要です。再ログインしてください。"
        case .permissionDenied:
            return "管理者権限が必要です。"
        case .failedPrecondition:
            return "テナント情報が取得できません。サインアウトしてから再ログインしてください。"
        case let .invalidArgument(message):
            return message.isEmpty ? "入力内容に誤りがあります。" : message
        case .notFound:
            return "対象の dryRunId が見つかりません。最初からやり直してください。"
        case .alreadyExists:
            return "この dryRun は既に処理されています。「最初からやり直す」を選んで新しい操作として再開してください。"
        case let .internal(message):
            let detail = (message?.isEmpty == false) ? "\n\(message!)" : ""
            return "サーバー内部エラーが発生しました。\(detail)\nしばらく時間をおいて再度お試しください。"
        case .malformedResponse:
            return "サーバーからの応答が不正です。アプリを最新版にアップデートしてください。"
        case .transient:
            return "ネットワークまたはサーバーが一時的に応答していません。電波状況を確認のうえ、少し時間をおいて再度お試しください。"
        case let .unknown(nsError):
            return "想定外のエラーが発生しました (\(nsError.domain) code: \(nsError.code))。"
        }
    }
}

#Preview {
    NavigationStack {
        AccountTransferView(service: PreviewTransferOwnershipService())
    }
}

private final class PreviewTransferOwnershipService: TransferOwnershipServicing {
    func dryRun(fromUid: String, toUid: String) async throws -> TransferOwnershipDryRunResult {
        try await Task.sleep(nanoseconds: 300_000_000)
        return TransferOwnershipDryRunResult(
            dryRunId: "preview-dry-run-id",
            counts: TransferOwnershipCounts(recordings: 12, templates: 3, whitelist: 1)
        )
    }

    func confirm(dryRunId: String) async throws -> TransferOwnershipConfirmResult {
        try await Task.sleep(nanoseconds: 500_000_000)
        return TransferOwnershipConfirmResult(
            updated: TransferOwnershipCounts(recordings: 12, templates: 3, whitelist: 1)
        )
    }
}
