# Handoff Archive — 2026-04

LATEST.md の 500 行制限 (handoff skill archive-procedure.md) に従い、古いセッション詳細をここに退避している。参照は過去の設計判断の追跡時のみ想定。

---

## 前セッション成果（2026-04-22 夕方、参考保持）

## セッション成果サマリ（2026-04-22 夕方セッション）

2026-04-22 遅延セッション末に残っていた P2 follow-up 2 件を消化。**2 PR merge / 2 Issue close**。あわせて Issue #141（全体テスト実行クラッシュ）を深掘りし、**真の根本原因を特定**して Issue コメントに記録。

| PR | 内容 | Issue |
|----|------|-------|
| #153 | OutboxSyncService: upload 失敗時に `createRecording` が呼ばれないこと検証 test 追加（orphan Firestore doc regression gate） | **#145 closed** |
| #154 | delete-account: partial-failure & auth error code の 5 分岐テスト追加 + `installMocks({...})` refactor（handler 差し込み構造） | **#102 closed** |

### Issue #141 の根本原因特定（open 維持、調査結果は Issue コメント追記）

当初の仮説「Firebase configure 未実行」ではなく、**SwiftData の挙動** が真の原因と判明。

- **root cause**: 同一プロセス内で同じ `@Model` 型（`ClientCache` 等）を 2 つの異なる `ModelContainer` に登録すると SwiftData が SIGTRAP (`EXC_BREAKPOINT`) で terminate。crash log の `x2` register が `type metadata for ClientCache` を指していたことで確定。
- **検証した 3 つの対症療法（いずれも無効）**:
  1. `FirebaseTestBootstrap` で dummy `FirebaseOptions` configure → Firebase 警告は消えるがクラッシュ継続
  2. schema を揃えて `makeClientOnlyTestModelContainer` を `makeTestModelContainer` に alias → crash 継続
  3. `CareNoteApp.init` で test 時 dummy configure + `isStoredInMemoryOnly: CareNoteApp.isRunningTests` → 52→37 failed に改善するも依然 crash
- **根本解決の選択肢（いずれも影響範囲大、未着手）**:
  - A. test target から host app 依存を外す（XcodeGen project.yml 全面見直し）
  - B. `CareNoteApp.modelContainer` を test 時 `nil` にする（production code に test 分岐）
  - C. test で app host の既存 ModelContainer を再利用（test 分離性喪失、fixture clean 機構要）
- **open 維持**: 根本解決は設計変更を要するため本セッションでは着手見送り。再開時は Xcode / SwiftData のバージョン変化も踏まえて再確認すること。
- 詳細: [#141 issue comment](https://github.com/system-279/carenote-ios/issues/141#issuecomment-4292636150)

### 本セッション適用した運用ルール
- 過剰起票防止（新規 Issue 起票ゼロ）
- test 変更は single-file / 小規模のためセルフレビュー止まり（`/review-pr` 6 agent 並列・`/codex review` は閾値未満でスキップ）
- Issue #141 深掘りは production code revert で clean state 維持（影響範囲大の変更をセッション内で独断実装しない）

Issue 数推移: セッション開始時 open 10 → 終了時 **8**（net -2、#145 / #102 close）。

前セッションまでに完了した Node.js 22 upgrade / admin ID token helper / Phase 0.9 RUNBOOK / 遅延セッションの Codex follow-up 2 PR は変更なし。prod deploy と iOS 実機 smoke test は引き続きユーザー作業待ち。

---

## 前セッション成果（2026-04-22 遅延、参考保持）

2026-04-22 昼セッションで scope 絞りした Codex follow-up 双子 Issue (#127 / #120) を消化。**2 PR merge / 2 Issue close**。

| PR | 内容 | Issue |
|----|------|-------|
| #150 | audit-createdby per-tenant 部分結果保持 + testable `auditCreatedBy` export (DI 化、9 test) | **#127 closed** |
| #151 | transferOwnership errorId 付与 + err.stack 構造化ログ + HttpsError.details enrich (8 test) | **#120 closed** |

---

## 前々セッション成果（2026-04-22 昼、参考保持）

**7 PR merge / 10 Issue close / 3 Issue scope 絞り**を実施。Codex セカンドオピニオンに基づき「過剰起票」を防ぐ運用ルールを確立した。セッション開始時 open 16 件 → 終了時 12 件（net -4、PR merge 7 件）。

### マージ済み PR（前セッション昼分、参考保持）

| PR | 内容 | Issue |
|----|------|-------|
| #138 | delete-account.test.js mock の深いサブコレクション偽陽性修正 | **#104 closed** |
| #139 | Firestore Rules エッジケーステスト part 2（role 値バリエーション + createdBy 書換防止 + 型崩れ）9 件追加 | **#135 closed** |
| #142 | `currentUidProvider` の @MainActor 越境を型で明示（@preconcurrency 削除） | **#106 closed** |
| #144 | `processItem` 主経路統合テスト 3 件追加（AC1 + C-Cdx-1 regression gate） | **#107 closed** |
| #146 | firebase.json の重複 hosting キーを削除 | **#131 closed** |
| #147 | upload-testflight.sh に entitlements 検証ステップ追加 | **#71 closed** |
| #126 | audit-createdby.mjs 堅牢性強化（token cache / pagination guard / retry） | **#103 closed** |

### Issue 整理（過剰起票防止ルール適用）

Codex セカンドオピニオン（下記運用ルール参照）に基づき以下を整理:

| # | 処置 | 理由 |
|---|------|------|
| #114 | **close** | backfill 専用の throwaway tool、dev/prod 両 backfill 実行済、統合テスト追加の ROI 不整合 |
| #140 | **close（本セッション中に起票したのを撤回）** | rating 5-6 の「regression gate 対称性向上」で実害ゼロ |
| #143 | **close（本セッション中に起票したのを撤回）** | silent-failure-hunter confidence 55、uid 失敗ログ欠落の実害なし |
| #120 | **scope 絞り** | 多段レビュー follow-up を全て Issue 化していた。errorId 付与（実運用での追跡性）のみ残す |
| #127 | **scope 絞り** | 4 項目 → per-tenant 部分結果保持（実害ベース）のみ残す |
| #145 | **scope 絞り** | 4 項目 → I-1 upload 失敗時 createRecording 未呼出 regression gate のみ残す |

### 本セッション起票（実バグのみ）

| # | タイトル | Priority | 状態 |
|---|---------|---------|------|
| #141 | テストスイート: ClientRepositoryTests.fetchAll で Firebase configure 未実行によるクラッシュ | P2 bug | 原因候補コメント追加（Swift Testing runner と CareNoteApp.isRunningTests の相互作用）、深掘り未了 |

