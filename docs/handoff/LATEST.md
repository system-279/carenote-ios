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

### bug（workaround あり）

| # | タイトル | 状態 |
|---|---------|------|
| #141 | ClientRepositoryTests 全体実行時のクラッシュ（全体テスト連鎖失敗源） | **根本原因特定済（SwiftData 同一プロセス複数 ModelContainer → SIGTRAP）**、根本解決は設計変更要、open 維持 |
| #91 | アカウント削除後のローカル SwiftData / Outbox クリーンアップ | 既存、要対応 |

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
9. **#141 根本解決** — 本セッションで調査完了（SwiftData 同一プロセス複数 ModelContainer）、A/B/C 選択肢いずれも影響範囲大、時間確保セッションで着手
10. **#91 アカウント削除後 SwiftData / Outbox クリーンアップ**（bug 系、iOS + XcodeBuildMCP 必要）
11. **#105 deleteAccount E2E Emulator Suite テスト**（時間確保セッションで、#102 の追加 branch coverage は本セッションで closed）

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

### Swift Testing: 全体テスト実行時の ClientRepositoryTests クラッシュ（#141）

- 個別 `xcodebuild -only-testing:` では PASS するスイートと、Xcode 26 β 環境では単独でも crash するスイートあり（Xcode / SwiftData のバージョン差に依存）
- **真の root cause（2026-04-22 夕方セッションで特定）**: 同一プロセス内で同じ `@Model` 型を 2 つの異なる `ModelContainer` に登録すると SwiftData 内部で SIGTRAP。詳細は [#141 issue comment](https://github.com/system-279/carenote-ios/issues/141#issuecomment-4292636150)
- **workaround**: CI は Xcode 16.3 で通過。ローカルで個別 test suite を `-only-testing:` で呼び分ける
- **根本解決**: 設計変更（test host app 外し / `modelContainer` Optional 化 / app host ModelContainer 再利用）いずれも影響範囲大、時間確保セッションで着手

## ADR

- [ADR-007](../adr/ADR-007-guest-tenant-for-apple-signin.md) — Apple Sign-In 用 Guest Tenant 自動プロビジョニング。Status: 採用。
- [ADR-008](../adr/ADR-008-account-ownership-transfer.md) — アカウント所有権移行方式。Phase 0 棚卸し + Phase 1 実装詳細（状態遷移図、エラーマッピング、チェックポイント、監査ログスキーマ、Partial Update 不変性、入力検証、運用呼出フロー、count drift 仕様）まで記載。Status: Accepted。

## RUNBOOK

- [phase-1-admin-id-token.md](../runbook/phase-1-admin-id-token.md) — admin ID token 発行 + cleanup 手順（`get-admin-id-token.mjs --cleanup-uid` 使用）
- [phase-0-9-allowed-domains.md](../runbook/phase-0-9-allowed-domains.md) — Phase 0.9 allowedDomains 有効化手順（draft、ユーザー作業待ち）
- [prod-deploy-smoke-test.md](../runbook/prod-deploy-smoke-test.md) — prod deploy 統合 smoke test チェックリスト（2026-04-22 新設、Codex 推奨段階 deploy 方針に対応）

## 参考資料（本セッション = 2026-04-22 夕方）

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
