# Handoff — 2026-04-22 夜セッション: #165 Schema drift lint merge

## セッション成果サマリ（2026-04-22 夜セッション）

前セッション (2026-04-22 日中、PR #163) で起票した **Issue #165 (Schema drift risk) を最小対応で close**。`@Model` 型追加時の drift を CI で機械的に検知する lint を導入し、PR #163 の `SharedTestModelContainer` 方式を regression gate で保護した。加えて、初版 lint のレビュー過程で **line-oriented grep が multi-line `ModelContainer(for:` を silent pass する重大欠陥** を発見・修正。修正後の lint が既存の `OutboxSyncServiceTests.swift` violation を正しく検出し、Issue #164 追跡箇所として暫定許可（依存関係を #164 へ記録）。

| PR | 内容 | Issue |
|----|------|-------|
| #167 | `scripts/lint-model-container.sh` + CI step + `SwiftDataModels.swift` drift checklist | **#165 closed** |

### 設計判断のハイライト

- **PM/PL 判断で A 最小対応採用、B postpone**: Issue #165 本文に A (lint + doc comment) / B (`AppSchema.allModelTypes` 単一ソース化) の 2 案が提示されていたが、B は 8-10 ファイル改修で Evaluator 分離対象、直近 PR #163 でテスト基盤を触ったばかりで regression risk 高い。現状 4 `@Model` 型安定・新規追加予定なしで A の detection gate で十分と判断
- **初版 lint の C1 欠陥発見**: `/review-pr` 6 並列レビューで silent-failure-hunter + pr-test-analyzer が独立で指摘、pr-test-analyzer は fabricated input で実証確認。grep の `\s` は newline にマッチせず、**`SharedTestModelContainer` 自身が multi-line style** のため、同 style のコピペ violation を全て silent pass する致命的欠陥。`perl -0777` slurp mode で修正し、generic + whitespace variants も同時に catch
- **隠れ violation 顕在化**: 修正後 lint を走らせたら `OutboxSyncServiceTests.swift:84-87` の既存 `ModelContainer(for:)` を検出（PR #163 で Issue #164 追跡中の per-suite container 局所 rollback）。旧 lint が silent pass していた実証 → **C1 修正の正当性が現物で証明された**。`ALLOWED_TEST_FILES` 配列化で Issue #164 参照付き暫定許可、#164 close 時に削除する依存関係を script 内コメント + #164 Issue コメントに記録
- **Positive pre-flight assertion 追加**: 許可ファイルの existence + pattern 含有を事前検証。helper 削除/rename や regex 破損でも silent pass しない（silent-failure-hunter H1/H2 対応）

### レビュー運用

- `/review-pr` 6 並列（type-design は新規型なしでスキップ、5 並列実動）:
  - code-reviewer / comment-analyzer / code-simplifier: Approve
  - **silent-failure-hunter: Critical 1 (C1 conf 95) + High 2 (H1 conf 90, H2 conf 85)**
  - **pr-test-analyzer: Important 1 (rating 7、実証済)**
- 初版 C1/H1/H2/Important を 1 commit で同時修正（commit `5ff4bf7`）、再 push で CI green
- Evaluator 分離プロトコル (5 files+) は該当せず（3 ファイル +77 行の小規模 PR）

### 本セッション起票（実害ベース）

なし。Issue #164 への暫定許可クロス参照はコメント追加のみで新規 Issue 化せず（triage rule #5 未該当）。

### Issue 数推移

セッション開始時 open 8 → 終了時 **7**（net **-1**、#165 close）。

| 動き | 件数 | Open 数推移 |
|------|------|------------|
| 開始時 | — | 8 |
| #165 close (PR #167) | -1 | **7** |

> CLAUDE.md KPI「Issue は net で減らすべき」達成。rating ≥ 7 の指摘を全て対応済、rating 5-6 の「production-side Schema lint 拡張」は Issue #165 option B 相当で postpone（triage rule 遵守）。

### CI の現状

- PR #167 feature branch (`5ff4bf7`) 最終 CI で iOS Tests job が **36m54s で green**（全 135 tests PASS、macOS runner の初期 cold start 込み）
- 新 lint step `Lint - SwiftData schema drift guard (Issue #165)` が CI 環境（macOS 15、bsd grep、macOS 標準 perl）で期待通り動作確認: `lint-model-container: OK (2 approved file(s) register @Model types)`
- 本 handoff PR push 時点で main `73fd304` (squash merge commit) の CI は進行中。設定/docs のみの変更で regression リスクなし

### 次セッション推奨アクション（本セッション反映後、優先順）

1. **審査アカウント whitelist 登録確認**（Firestore Console で `tenants/279/whitelist` に `demo-reviewer@carenote.jp` 確認 — Phase 0.9 前提ゲート、前セッションから継続）
2. **iOS 実機 smoke test**（Phase 0.5 / Phase 1 / Node 22 統合動作確認、前セッションから継続）
3. **Day 1-3 prod deploy 段階実施**（Node 22 → Phase 0.5 Rules → Phase 1 transferOwnership、各単独、24h 監視。`docs/runbook/prod-deploy-smoke-test.md` 使用）
4. **#164 OutboxSyncServiceTests shared container 真因調査**（本セッションで新 lint が既存 violation を現物検出したことで調査優先度が上がった。ALLOWED_TEST_FILES 暫定許可削除が close 条件。Issue 本文 4 仮説を `/impl-plan` で順序立てて検証推奨）
5. **#105 deleteAccount E2E Emulator Suite テスト**（時間確保セッションで）
6. **Phase 0.9 dev 先行検証 → prod 実施**（審査通過後、#111 close）

> 本セッションで lint が OutboxSyncServiceTests violation を catch した事実は、#164 の per-suite container が「意図的な rollback」として構造化されたことを意味する。#164 真因調査の副産物として lint の ALLOWED_TEST_FILES 削除 + doc comment 更新が連動する依存関係を持つ。

### 参考資料（本セッション = 2026-04-22 夜）

- [PR #167 Schema drift lint + CI gate](https://github.com/system-279/carenote-ios/pull/167)
- [Issue #164 OutboxSync 暫定許可クロス参照コメント](https://github.com/system-279/carenote-ios/issues/164#issuecomment-4294661569)

---

# Handoff — 2026-04-22 日中セッション: #141 SwiftData SIGTRAP 根本解決 merge

## セッション成果サマリ（2026-04-22 日中セッション）

前セッション (2026-04-23 早朝) で Postpone 判定していた **Issue #141 (SwiftData 同一プロセス複数 ModelContainer SIGTRAP) を案 C' で根本解決**。全体テスト実行時の crash ゼロを達成し、CareNote iOS の test suite 安定性を回復。

| PR | 内容 | Issue |
|----|------|-------|
| #163 | SharedTestModelContainer 導入 + 9 test files 統一 + `.serialized` 適用 | **#141 closed** |

### 設計判断のハイライト

- **案 C' の 1 ファイル収束**: 当初見積もり「9 files 変更」だったが、helper 側で `SharedTestModelContainer` + 自動 cleanup を仕掛けることで呼び出し側の変更を回避しようとした。しかし `/simplify` の reuse agent が「per-suite `makeContainer()` 残存で SIGTRAP 再発リスク」を指摘し、7 files の per-suite container を一括 shared 化。最終 10 files / +95/-124（-29 行の純減）
- **`.serialized` 全面適用**: Swift Testing の default parallel 実行が shared container 上で競合し `OutboxSyncServiceTests` が回帰 (uploadCalls.count が 3 倍に膨らむ) → SwiftData-backed 7 suites に `.serialized` 付与で解消
- **OutboxSyncServiceTests のみ per-suite 維持**: `.serialized` 後も 2 test が `uploadCalls.count → 0` で回帰。当初「service が独自 ModelContext 派生」と推測したが `/review-pr` 6 agent の grep で **全て `modelContainer.mainContext`** 使用と判明 → 真因未確定のまま per-suite container に局所 rollback、Issue #164 で調査継続

### レビュー運用

- `/simplify` 3 並列: reuse agent の scope 拡張指摘で 1 file → 10 files に拡大（Issue #141 再発ガードを担保）
- `/review-pr` 6 並列: Critical 2 件検出
  - C1: OutboxSync コメント factually 誤り → commit c2f3e60 で訂正
  - C2: Schema drift risk (`@Model` 型 hard-code 3 箇所) → Issue #165 で follow-up
- Evaluator 分離プロトコル (5 files+) は `/review-pr` 6 並列で代替と判断

### 本セッション起票（実害ベース）

| # | タイトル | 優先度 | 根拠 |
|---|---------|-------|------|
| #164 | OutboxSyncServiceTests が SharedTestModelContainer と相性が悪く回帰する（真因未確定） | P2 bug | triage #2 再現可能なバグ、PR 作成時点で .serialized + shared で 2 test が `uploadCalls.count == 0` を再現 |
| #165 | Schema drift risk: `@Model` 型を SharedTestModelContainer と LocalDataCleaner で hard-code | P2 bug | triage #2 実害シナリオ明確（新 `@Model` 追加時の LocalDataCleaner 漏れ = #91 type regression）+ review 5 agent 合議指摘 |

### Issue 数推移

セッション開始時 open 7 → 終了時 **8**（net **+1**、#141 close / #164 #165 起票）。

| 動き | 件数 | Open 数推移 |
|------|------|------------|
| 開始時 | — | 7 |
| #141 close (PR #163) | -1 | 6 |
| #164 起票（OutboxSync 真因調査） | +1 | 7 |
| #165 起票（Schema drift） | +1 | **8** |

> **注**: net +1 だが、#141 の SIGTRAP crash という既存の実害を解消した上で、調査過程で発見した 2 件の潜在リスクを可視化した結果。triage 基準に照らすと #164/#165 共に「再現可能な bug / 明確な実害シナリオ」で起票条件を満たす。レビュー agent の rating 7-9 指摘のみ採用、rating 5-6 の「改善提案」は全て PR コメント or 却下（triage rule 遵守）。

### CI の現状

- main 最新 (`589b87f`, PR #163) で iOS Tests job が **23m55s で green**。PR #161 の retry logic が実効することも実証（simulator runtime install の retry 発動なし）
- 全 18 suites / 135 tests PASS

---

> **Note (2026-04-22 日中追記)**: 以下 2026-04-23 早朝セッションの記録内で扱った **#141 Postpone 判定は PR #163 で覆り、close 済**。「再開時のアクションメモ」「再開条件」等の Postpone 前提記述は履歴保存目的で残すが、次セッションの参照対象ではない。

# Handoff — 2026-04-23 早朝セッション: #159 CI retry fix merge / #141 真因確定 + Postpone

## セッション成果サマリ（2026-04-23 早朝セッション）

2026-04-22 夜セッションで起票された #159 (iOS Tests CI flaky) を解消。加えて #141 (SwiftData ModelContainer 重複クラッシュ) を再現検証し、**案 B (ModelContainer Optional 化) が効果なし**と確認。真の解決策 = **案 C' (test 全体で shared container)** を特定して Issue に追記し、本セッションでは Postpone (open 維持)。

| PR | 内容 | Issue |
|----|------|-------|
| #160 | docs/handoff 2026-04-22 夜セッション成果反映 + Issue 推移計算ミス修正 | — |
| #161 | iOS Simulator Runtime install の retry logic 追加 (最大 3 回 + `set -euo pipefail`) | **#159 closed** |

### 設計判断のハイライト

- **PR #161 Review 反映で fallback 削除**: 初版は「既存 iOS runtime が利用可能なら warning で継続」の fallback path を含んでいたが、code-reviewer + silent-failure-hunter の 2 エージェント並列レビューが共通で Critical 指摘 (`'iOS' in identifier` は iOS 16 等古い runtime も通過 → Boot Simulator が `iPhone 16 Pro` を見つけられず silent skip)。最小 scope (retry のみ) に絞って再コミット
- **#141 は対症療法不能と確定**: `ModelContainer` を Optional 化して body 副作用 (`PresetTemplates seedIfNeeded`) を遮断しても、test helper 側で毎 test 新 container 生成するため SIGTRAP 継続。`test 全体で shared container` に切替える大規模 test refactor (12+ files) が唯一の根本解決
- **#141 は Postpone (open 維持)**: 再開条件を明記 (Xcode/iOS 更新での挙動変化再検証 / 全体テスト実行の必要性高まり / 新規 `@Model` 型追加との合流)

### レビュー運用

- PR #161: 2 エージェント並列レビュー（code-reviewer / silent-failure-hunter）。小規模 PR (1 file +20/-1 最終 diff) なので 6 エージェントは過剰
- #141 の案 B 実装は検証で効果なしと判明 → commit せず rollback (production code を dirty に残さない)

### 本セッション起票（実害ベース）

なし。

### Issue 数推移

セッション開始時 open 8 → 終了時 **7**（net **-1**、#159 close）。

| 動き | 件数 | Open 数推移 |
|------|------|------------|
| 開始時 | — | 8 |
| #159 close (PR #161) | -1 | **7** |

### #141 再開時のアクションメモ

- `CareNoteTests/TestHelpers/SwiftDataTestHelper.swift` に `SharedTestModelContainer` (static let) 追加
- `makeTestModelContainer` / `makeClientOnlyTestModelContainer` を `SharedTestModelContainer.shared` に統合
- 各 test の setUp で `context.delete(model:)` による事前 cleanup で分離性を代替
- 影響範囲: CareNoteTests 配下の 15 test ファイルのうち ModelContainer 生成ロジックを持つもの (明示列挙: `ClientRepositoryTests`, `ClientSelectViewModelTests`, `ClientCacheServiceTests`, `RecordingListViewModelTests`, `RecordingRepositoryTests`, `TemplateCreateViewModelTests`, `TemplateListViewModelTests`, `OutboxSyncServiceTests`, `RecordingConfirmViewModelTests` の 9 件。残りは `@Model` を touch しない可能性)
- Quality Gate (Evaluator 分離プロトコル) 対象
- 再現コマンド: `xcodebuild test -project CareNote.xcodeproj -scheme CareNote -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:CareNoteTests/ClientRepositoryTests`

### CI の現状

- main 最新 (`9a177fe`, PR #161) は `.github/**` のみの変更で iOS Tests job が `paths-ignore` により trigger されない
- **次の substantive PR (Swift コード変更を含む) で retry 効果の実効検証が必要**
- それまで main iOS Tests CI 最新失敗は 24760085320 (2026-04-22 04:24Z, commit 506f4e8) のまま残る

---

# Handoff — 2026-04-22 夜セッション: #91 本体対応完了（2 PR merge、レビュー指摘構造的解消）

## セッション成果サマリ（2026-04-22 夜セッション）

Issue #91（アカウント削除後のローカル SwiftData / Outbox クリーンアップ、実セキュリティリスク）を本対応 + レビュー指摘 silent-failure C1 の follow-up まで一気通貫で実施。**2 PR merge / 2 Issue close / 2 Issue 起票**（#157 は同セッション内 close、#159 は CI infra flaky）。

| PR | 内容 | Issue |
|----|------|-------|
| #156 | LocalDataCleaning protocol + SwiftDataLocalDataCleaner (atomic purge + rollback) / deleteAccount 後に purge 呼出 / behavioral test 3 件 / 構造化 NSError ログ | **#91 closed** |
| #158 | purge 失敗時の UI 通知（専用 flag `postDeletionPurgeFailed` 導入で errorMessage 兼用を構造的排除） | **#157 closed** |

### 設計判断のハイライト

- **errorMessage 兼用問題の根本解消**: PR #158 初版は `AuthViewModel.errorMessage` を SettingsView 側で転記する設計だったが、4 エージェント並列レビューの 3 エージェント（code-review / silent-failure / simplify）が合意で Critical 指摘。専用 flag `postDeletionPurgeFailed` に置換することで sign-in / sign-out 系との race / silent corruption を型レベルで排除
- **purge の atomic 化**: PR #156 初版は個別 `try context.delete(model:)` チェーンで partial failure のリスクがあったが、silent-failure C2 指摘を受けて個別 do-catch + rollback + `LocalDataCleanerError.partialFailure` throw に変更。OutboxItem だけ残って別 tenant 誤送信（#91 最大リスク）を防止
- **Firebase 非依存メソッド抽出**: `deleteAccount()` 全体は Firebase (`Auth.auth().revokeToken` / `Functions.httpsCallable`) 依存で unit test 不能だが、purge 呼出部分を `performPostDeletionCleanup()` internal method に抽出して behavioral test 可能に

### レビュー運用

- PR #156: 6 エージェント並列レビュー（code-reviewer / pr-test / comment / silent-failure / type-design / simplify）
- PR #158: 4 エージェント並列レビュー（code-reviewer / pr-test / silent-failure / simplify、type-design は新規型なしでスキップ）
- 指摘重複が高い問題 (errorMessage 兼用) を専用 flag で一発解消 → 複数 Critical を同時クローズ
- 別 Issue 化判定は慎重: silent-failure C1 (SettingsView unmount) / pr-test G2 (isRetryable 抽出) / silent-failure I1 (DI 未注入 critical 分離) / silent-failure I2 (enum 化) はいずれも起票せず（推測起票 / インフラ要 / スコープ超 / 合流候補）

### 本セッション起票（実害ベース）

| # | タイトル | 優先度 | 理由 |
|---|---------|-------|------|
| #157 | アカウント削除後のローカル purge 失敗を UI/ユーザーに通知する | P2 | silent-failure C1 Conf 0.90、本セッション中に #158 で close |
| #159 | CI: iOS Tests ワークフローが main push 後に 3 連続 failure | P2 | main CI green の担保不能、regression detection が実質壊れている |

### 別 Issue 化しなかった指摘（過剰起票防止）

| 指摘 | 理由 |
|------|------|
| silent-failure C1 (SettingsView unmount 時の UI 消失) | Conf 0.75 で「実機検証要」レベル、推測起票は triage rule 違反。次回 smoke test 時に確認 |
| pr-test G2 (deleteAccountIsRetryable 分岐抽出) | testability 向上のみ、実バグなし（rating 8 review 提案） |
| silent-failure I1 (DI 未注入と I/O 失敗の critical 分離) | error tracking 基盤 (Crashlytics 等) 未整備が前提条件、インフラ変更伴う |
| silent-failure I2 (DeleteAccountError enum 化) | API 境界変更、#102 partial-failure 設計と合流候補で個別起票不要 |

### Issue 数推移

セッション開始時 open 8 → 終了時 **8**（net **0**）。

| 動き | 件数 | Open 数推移 |
|------|------|------------|
| 開始時 | — | 8 |
| #91 close (PR #156) | -1 | 7 |
| #157 起票 → 同セッション close (PR #158) | ±0 | 7 |
| #159 起票（CI iOS Tests flaky） | +1 | **8** |

> **注**: net 0 だが進捗ゼロではない — PR merge 2 件で実装前進 (#91 のセキュリティリスク本対応完了)。#159 は CI インフラ問題で CLAUDE.md triage 基準「CI/リリース判断を壊す」該当のため起票必須（推測起票ではなく 3 連続再現済の実害）。triage rule に照らせば「Issue net ゼロの実装進捗」は許容範囲内。

---

## 過去セッション詳細（アーカイブ）

2026-04-22 夕方 / 遅延 / 昼 セッションの詳細は [archive/2026-04-history.md](./archive/2026-04-history.md) に退避。主な完了内容: Phase 0.5 Rules / Phase 1 transferOwnership / Node 22 upgrade / audit-createdby / 関連 follow-up PR 群。設計判断の追跡時のみ参照。

---

## 確立した運用ルール（Codex セカンドオピニオン 2026-04-22）

**「過剰起票」防止のため、次セッション以降も継続適用推奨。**

1. **新規 Issue 起票は原則禁止、例外は実バグのみ**
2. **review agent の rating 5-6 提案は Issue 化しない**（PR コメント / 既存 Issue 追記 / TODO コメントで扱う）
3. **Issue 化する条件**: 実害あり / 再現可能なバグ / ユーザー影響 / CI・リリース判断を壊す / 将来の重大 regression を低コストで防げる
4. **review agent 提案は triage inbox に溜め、セッション末にまとめて Issue 化判断**（自動起票しない）
5. **Issue は net で減らす KPI** — close 4 + 起票 4 = net 0 は進捗ゼロ扱い

## 現在の状態

- **ブランチ**: main（clean、CI green）
- **ビルド**: Build 35（App Store Connect 審査中、2026-04-16 提出）
- **審査通過見込み**: 90%+（deleteAccount が実データで機能する状態を確立済み）
- **アカウント移行機能**: **Phase -1 / 0 / 0.5 / 1 完了**、dev Node 22 完了、prod deploy 待ち
- **Phase 0.9**: RUNBOOK draft merged、dev 先行検証 + prod 実施はユーザー作業待ち

## アカウント移行機能 + Node upgrade の Phase 構成

| Phase | 内容 | 状態 |
|---|---|---|
| Phase -1 | `createdBy` 正常保存 + 監査 + deleteAccount テスト | ✅ PR #101 マージ済 |
| Phase -1 A3 dev | dev 21 件バックフィル削除 | ✅ PR #112 |
| Phase -1 A3 prod | prod 8 件バックフィル削除 | ✅ 実施済 + PR #117 |
| Phase 0 | uid 参照棚卸し (ADR-008) | ✅ PR #109 |
| Phase 0.5 | Firestore Rules 強化 + migrationLogs + rules-unit-testing + CI 組込 | ✅ PR #115 merged + dev deploy 完了、**prod deploy 残** |
| Phase 0.5 拡充 | エッジケーステスト 20 件追加（55→64 tests、本セッション PR #139 含む） | ✅ PR #134 + #139 |
| Phase 0.9 | RUNBOOK draft | ✅ PR #133 merged、**実施は smoke test 後** |
| Phase 0.9 実施 | prod `tenants/279.allowedDomains = ["279279.net"]` 有効化 | ⏳ **ユーザー作業待ち** |
| Phase 1 | `transferOwnership` Callable Function 実装 | ✅ PR #119 merged + dev deploy 完了、**prod deploy 残** |
| Phase 1 helper | admin ID token helper + RUNBOOK | ✅ PR #128 / #132（Issue #120 part 1 + #129） |
| Node 22 upgrade | dev deploy | ✅ PR #130 merged + dev 3 関数 nodejs22 ACTIVE (2026-04-21) |
| Node 22 upgrade | **prod deploy** | ⏳ **ユーザー承認待ち**（期限 2026-04-30） |
| Phase 2 | 本人主導 UI（移行コード方式） | 🔒 スコープ外（頻度低 × コスト高） |

## ユーザー作業依頼（次セッション再開時の重要項目、優先順）

> **2026-04-22 更新**: Codex セカンドオピニオンに基づき、deploy を**段階実施**に変更。Node 22 を最優先・単独 deploy、Phase 0.9 は 4/30 期限から切り離す。
> 詳細チェックリスト: [`docs/runbook/prod-deploy-smoke-test.md`](../runbook/prod-deploy-smoke-test.md)

### マスタースケジュール（Day 0 = 2026-04-22）

| Day | 作業 | 判定 |
|-----|------|------|
| 0（今日） | smoke test RUNBOOK 整備 + 審査アカウント影響調査（whitelist 登録確認） | ✅ 本セッションで完了 |
| 1 | iOS 実機 smoke test → **Node 22 prod deploy**（最優先・単独） | PASS → Day 2 |
| 2 | **Phase 0.5 Rules prod deploy**（Node 22 安定後、単独） | PASS → Day 3 → Issue #100 close candidate |
| 3 | **Phase 1 transferOwnership prod deploy**（単独） | PASS → 24h 監視開始 |
| 3-4 | 24h 安定監視 | GO/NO-GO 判定 |
| 4-5 | Phase 0.9 dev 先行検証（`docs/runbook/phase-0-9-allowed-domains.md` § A） | PASS → Day 6+ |
| 6+ | **Phase 0.9 prod 実施**（4/30 期限から切離、審査通過後推奨） | → Issue #111 close |

### 1. 事前必須: 審査アカウント影響調査（Phase 0.9 の前提ゲート）

**Firestore Console で `tenants/279/whitelist` に `demo-reviewer@carenote.jp` が登録されているか確認**:

```
https://console.firebase.google.com/project/carenote-prod-279/firestore/data/~2Ftenants~2F279~2Fwhitelist
```

- 登録あり: Phase 0.9 有効化後も whitelist 優先仕様で影響なし（`beforeSignIn` の分岐順で検証済、`functions/index.js:39-57`）
- 登録なし: Phase 0.9 prod 実施前に登録必須（詳細手順 `docs/runbook/prod-deploy-smoke-test.md` § 審査アカウント確認）

### 2. iOS 実機 smoke test（全 prod deploy の前提ゲート）

**目的**: Phase 0.5 Rules + Phase 1 transferOwnership + Node 22 runtime の統合動作確認

検証動線（iOS 実機、dev build）:
- Apple Sign-In → `beforeSignIn` が `nodejs22` で起動し、`tenantId` custom claim 取得
- 新規録音作成 → Firestore に `createdBy=自分のuid` で保存
- 自分の録音の transcription 編集 → 成功
- RecordingList 表示 → 他人の録音も read 可で従来通り
- （可能なら）テストアカウントで `deleteAccount` callable 呼出、自データ削除 + Auth user 削除確認

**Node 22 起動確認のヒント**: Cloud Logging で `beforeSignIn` / `deleteAccount` / `transferOwnership` の container 起動ログに `nodejs22` が記録される。初回は cold start でやや遅延することあり（想定内）。

**失敗時の rollback**: `docs/runbook/prod-deploy-smoke-test.md` § 失敗時エスカレーション を参照。

> **注意**: 以下の prod deploy コマンドはすべて `firebase` CLI で `--project=carenote-prod-279` を明示する。`firebase` CLI は `gcloud` と別系統のため `CLOUDSDK_ACTIVE_CONFIG_NAME` は不要。ただし同じターミナルで `gcloud` を使う場合は `CLOUDSDK_ACTIVE_CONFIG_NAME=carenote-prod` の invocation 前置きを使うこと（CLAUDE.md 規範）。

### 3. Node 22 runtime prod deploy（Day 1、最優先、**期限 2026-04-30**）

```
firebase deploy --only functions --project carenote-prod-279
```

- prod 操作のため ユーザー確認必須
- Node 20 は 2026-04-30 deprecated、2026-10-30 decommissioned
- deploy 後 `firebase functions:list --project=carenote-prod-279` で 3 関数が `nodejs22` ACTIVE 確認
- 詳細手順: `docs/runbook/prod-deploy-smoke-test.md` § Day 1

### 4. Phase 0.5 Rules prod deploy（Day 2、Node 22 安定後、単独）

```
firebase deploy --only firestore:rules --project carenote-prod-279
```

- prod 操作のため CLAUDE.md MUST に従いユーザー確認必須
- deploy 完了後 Issue #100 close 判定
- 詳細手順: `docs/runbook/prod-deploy-smoke-test.md` § Day 2

### 5. Phase 1 transferOwnership prod deploy（Day 3、Rules 安定後、単独）

```
firebase deploy --only functions:transferOwnership --project carenote-prod-279
```

- prod 操作のため ユーザー確認必須
- 詳細手順: `docs/runbook/prod-deploy-smoke-test.md` § Day 3

### 6. Phase 0.9 `allowedDomains` 有効化（Day 6+、**4/30 期限から切離**）

> **Codex セカンドオピニオン 2026-04-22**: Phase 0.9 を焦って本番反映しログイン障害を起こす方がリスク高。Node 22 期限と切り離し、App Store 審査通過後の安定期に実施推奨。

- RUNBOOK: `docs/runbook/phase-0-9-allowed-domains.md`
- 先に dev 先行検証（手順 A、4 パターン動作確認）
- 審査アカウント whitelist 登録確認済（上記 § 1）必須
- prod 実施はユーザー明示承認必須

## Open Issue（優先度順、2026-04-22 夕方セッション末時点 8 件）

### P0（要対応、open 継続中）

| # | タイトル | 状態 |
|---|---------|------|
| #100 | Firestore Rules の recordings 権限が過剰 | **実装は PR #115 で完了、dev deploy 済、prod deploy 完了後に close 予定** |

### bug（追跡中、2026-04-22 日中更新）

| # | タイトル | 状態 |
|---|---------|------|
| #164 | OutboxSyncServiceTests が SharedTestModelContainer と相性が悪く回帰する（真因未確定） | **2026-04-22 起票、未着手**。PR #163 で per-suite container に局所 rollback 済（CI green）、真因調査は別セッション |
| #165 | Schema drift risk: `@Model` 型を SharedTestModelContainer と LocalDataCleaner で hard-code | **2026-04-22 起票、未着手**。grep lint or `AppSchema.allModelTypes` 単一ソース化で解消 |

> **消化済 (2026-04-22 日中)**: #141 (→ PR #163 で根本解決)、#91 は PR #156 / #158 (2026-04-22 夜) で close 済。

### P2 機能・テスト拡張（残り 2 件）

| # | タイトル |
|---|---------|
| #105 | deleteAccount E2E を Firebase Emulator Suite で実装 |
| #111 | Phase 0.9: prod allowedDomains 有効化（RUNBOOK merged、実施待ち） |

> **消化済**: #120 (→ PR #151)、#127 (→ PR #150) は 2026-04-22 遅延セッションで close。#145 (→ PR #153)、#102 (→ PR #154) は 2026-04-22 夕方セッションで close。

### 機能拡張（別セッション候補）

| # | タイトル |
|---|---------|
| #65 | Apple ID アカウントリンク |
| #90 | Guest Tenant (demo-guest) スパム対策 |
| #92 | Guest Tenant 本番ログイン不可案内UI |

## 次セッション推奨アクション（優先度順、2026-04-22 Codex 推奨に準拠）

1. **審査アカウント whitelist 登録確認**（Firestore Console で `tenants/279/whitelist` に `demo-reviewer@carenote.jp` 確認 — Phase 0.9 前提ゲート）
2. **iOS 実機 smoke test を済ませる**（Phase 0.5 / Phase 1 / Node 22 の統合動作確認、`docs/runbook/prod-deploy-smoke-test.md` 使用）
3. **Day 1: Node 22 runtime prod deploy（最優先・単独、期限 2026-04-30）**（ユーザー承認 → 全 functions deploy）
4. **Day 2: Phase 0.5 Rules prod deploy（単独）**（ユーザー承認 → Rules apply → #100 close）
5. **Day 3: Phase 1 transferOwnership prod deploy（単独）**（ユーザー承認 → Cloud Function deploy）
6. **Day 3-4: 24h 安定監視**（エラー急増なし確認）
7. **Day 4-5: Phase 0.9 dev 先行検証**（RUNBOOK `docs/runbook/phase-0-9-allowed-domains.md` § 手順 A）
8. **Day 6+: Phase 0.9 prod 実施**（4/30 期限から切離、審査通過後推奨 → #111 close）
9. **#164 OutboxSyncServiceTests shared container 互換性調査** — PR #163 で局所 rollback 済。真因候補は `.serialized` + async hop race / cleanup timing / cross-suite pollution。bisect で特定
10. **#165 Schema drift 防止**（grep lint 追加または `AppSchema.allModelTypes` 単一ソース化）
11. **#105 deleteAccount E2E Emulator Suite テスト**（時間確保セッションで、#102 の追加 branch coverage は PR #154 で closed）

> **Codex セカンドオピニオン要点（2026-04-22）**: (1) 一括 deploy 禁止（原因切り分け不能化）、(2) Node 22 を最優先・単独、(3) Phase 0.9 を 4/30 期限から切離、(4) 各 deploy 後は即時 smoke test + 数時間エラー監視、最後にまとめて 24h 監視、(5) 軽量 smoke test チェックリストで十分（過剰ドキュメント化回避）。

### deleteOldAuthUser 分離 Function（Phase 1 残件）

Issue #110 本体は transferOwnership のみ。旧 Auth user 削除は別 Function として残してあるため、将来独立 Issue 化して実装する（ロールバック余地を Phase 1 完了後に評価）。

## 既知の警告

### Cloud Functions Node.js 22 runtime（Issue #124 / #108 解消済み、先行セッション）

- dev 3 関数は 2026-04-21 時点で nodejs22 ACTIVE、deprecation warning 消滅
- prod は未 deploy（ユーザー承認必要、期限 2026-04-30）

### CI Workflow

- `.github/workflows/test.yml` (iOS Tests) は paths-ignore で `firestore.rules` / `functions/**` / `docs/**` / `.github/**` 等を除外
- `.github/workflows/functions-test.yml` (Functions & Rules Tests) が Firestore + Auth emulator で全テストスイート（`npm test` = 5 ファイル合計）を実行（Node 22）。本セッション末時点で Firestore Rules 64 tests + functions 系で合計 130 件前後。正確な件数は CI ログで確認。

### Swift Testing: SwiftData SIGTRAP（#141、2026-04-22 日中 PR #163 で解消）

- **解消**: `SharedTestModelContainer` (static let) + `cleanup()` で process 内 1 container に統一、`.serialized` で parallel race 防止。全 18 suites / 135 tests が CI green
- **残存リスク**: `SwiftDataTestHelper.shared` init と `cleanup()` が `@Model` 型を hard-code（新規 `@Model` 追加時の drift → Issue #165 で対応）
- **OutboxSyncServiceTests のみ per-suite container**: shared 化で 2 test が回帰、真因未確定のため Issue #164 で追跡

## ADR

- [ADR-007](../adr/ADR-007-guest-tenant-for-apple-signin.md) — Apple Sign-In 用 Guest Tenant 自動プロビジョニング。Status: 採用。
- [ADR-008](../adr/ADR-008-account-ownership-transfer.md) — アカウント所有権移行方式。Phase 0 棚卸し + Phase 1 実装詳細（状態遷移図、エラーマッピング、チェックポイント、監査ログスキーマ、Partial Update 不変性、入力検証、運用呼出フロー、count drift 仕様）まで記載。Status: Accepted。

## RUNBOOK

- [phase-1-admin-id-token.md](../runbook/phase-1-admin-id-token.md) — admin ID token 発行 + cleanup 手順（`get-admin-id-token.mjs --cleanup-uid` 使用）
- [phase-0-9-allowed-domains.md](../runbook/phase-0-9-allowed-domains.md) — Phase 0.9 allowedDomains 有効化手順（draft、ユーザー作業待ち）
- [prod-deploy-smoke-test.md](../runbook/prod-deploy-smoke-test.md) — prod deploy 統合 smoke test チェックリスト（2026-04-22 新設、Codex 推奨段階 deploy 方針に対応）

## 参考資料（本セッション = 2026-04-22 日中）

- [PR #163 SharedTestModelContainer 導入 + 9 test files 統一](https://github.com/system-279/carenote-ios/pull/163)
- [Issue #164 OutboxSyncService shared container 互換性](https://github.com/system-279/carenote-ios/issues/164)
- [Issue #165 Schema drift risk](https://github.com/system-279/carenote-ios/issues/165)

## 参考資料（前セッション = 2026-04-22 夕方）

- [PR #153 OutboxSyncService upload 失敗時 createRecording 未呼出検証](https://github.com/system-279/carenote-ios/pull/153)
- [PR #154 delete-account partial-failure & auth error code の 5 分岐追加](https://github.com/system-279/carenote-ios/pull/154)
- [Issue #141 根本原因特定コメント](https://github.com/system-279/carenote-ios/issues/141#issuecomment-4292636150)

## 参考資料（前セッション = 2026-04-22 遅延）

- [PR #150 audit-createdby per-tenant 部分結果保持](https://github.com/system-279/carenote-ios/pull/150)
- [PR #151 transferOwnership errorId + err.stack](https://github.com/system-279/carenote-ios/pull/151)

## 参考資料（前々セッション = 2026-04-22 昼）

- [PR #138 delete-account mock 深さ制限](https://github.com/system-279/carenote-ios/pull/138)
- [PR #139 Rules エッジケース part 2](https://github.com/system-279/carenote-ios/pull/139)
- [PR #142 @preconcurrency → @MainActor 明示](https://github.com/system-279/carenote-ios/pull/142)
- [PR #144 processItem 主経路テスト](https://github.com/system-279/carenote-ios/pull/144)
- [PR #146 firebase.json 重複 hosting 整理](https://github.com/system-279/carenote-ios/pull/146)
- [PR #147 upload-testflight entitlements 検証](https://github.com/system-279/carenote-ios/pull/147)
- [PR #126 audit-createdby 堅牢性強化](https://github.com/system-279/carenote-ios/pull/126)

## 参考資料（先行セッション）

- [PR #130 Node 22 upgrade](https://github.com/system-279/carenote-ios/pull/130)
- [PR #132 admin ID token helper 堅牢化](https://github.com/system-279/carenote-ios/pull/132)
- [PR #133 Phase 0.9 RUNBOOK draft](https://github.com/system-279/carenote-ios/pull/133)
- [PR #134 Rules エッジケーステスト part 1](https://github.com/system-279/carenote-ios/pull/134)
- [PR #101 Phase -1](https://github.com/system-279/carenote-ios/pull/101)
- [PR #112 A3 dev バックフィル](https://github.com/system-279/carenote-ios/pull/112)
- [PR #115 Phase 0.5 Rules](https://github.com/system-279/carenote-ios/pull/115)
- [PR #117 A3 prod バックフィル](https://github.com/system-279/carenote-ios/pull/117)
- [PR #119 Phase 1 transferOwnership](https://github.com/system-279/carenote-ios/pull/119)
- [PR #128 admin ID token helper part 1](https://github.com/system-279/carenote-ios/pull/128)
