# Handoff — Codex scope-narrowed follow-up 双子消化 + 2 PR merge (2026-04-22 late session)

## セッション成果サマリ（2026-04-22 遅延セッション）

2026-04-22 昼セッションで scope 絞りした Codex follow-up 双子 Issue (#127 / #120) を消化。**2 PR merge / 2 Issue close**。勢いと context を保ったまま 1 日 3 PR 目を完走。

| PR | 内容 | Issue |
|----|------|-------|
| #150 | audit-createdby per-tenant 部分結果保持 + testable `auditCreatedBy` export (DI 化、9 test) | **#127 closed** |
| #151 | transferOwnership errorId 付与 + err.stack 構造化ログ + HttpsError.details enrich (8 test) | **#120 closed** |

### 本セッション適用した運用ルール
- 過剰起票防止（新規 Issue 起票ゼロ）
- review agent rating 5-6 は Issue 化せず PR 内で吸収（Array.isArray 判定、empty message fallback は対応 / Error Reporting 連携・dryRun errorId 化は scope 絞り見送り）
- emulator 必須テストは Test plan 未実行として明記（次セッション or CI emulator 環境へ後送り）

Issue 数推移: セッション開始時 open 12 → 終了時 **10**（net -2）。

前セッションまでに完了した Node.js 22 upgrade / admin ID token helper / Phase 0.9 RUNBOOK / 昼セッションの 7 PR + 過剰起票防止ルールは変更なし。prod deploy と iOS 実機 smoke test は引き続きユーザー作業待ち。

---

## 前セッション成果（2026-04-22 昼、参考保持）

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

## Open Issue（優先度順、2026-04-22 遅延セッション末時点 10 件）

### P0（要対応、open 継続中）

| # | タイトル | 状態 |
|---|---------|------|
| #100 | Firestore Rules の recordings 権限が過剰 | **実装は PR #115 で完了、dev deploy 済、prod deploy 完了後に close 予定** |

### bug（workaround あり）

| # | タイトル | 状態 |
|---|---------|------|
| #141 | ClientRepositoryTests 全体実行時の Firebase configure 未実行クラッシュ | 昼セッション起票、原因候補コメント済、修正は別セッション（iOS + XcodeBuildMCP 必要） |
| #91 | アカウント削除後のローカル SwiftData / Outbox クリーンアップ | 既存、要対応 |

### P2 follow-up（scope 絞り済、残り 1 件）

| # | タイトル |
|---|---------|
| #145 | processItem upload 失敗時の createRecording 未呼出検証 |

> **消化済**: #120 (→ PR #151)、#127 (→ PR #150) は 2026-04-22 遅延セッションで close。

### P2 機能・テスト拡張

| # | タイトル |
|---|---------|
| #102 | deleteAccount テスト拡張（partial failure / auth error codes） |
| #105 | deleteAccount E2E を Firebase Emulator Suite で実装 |
| #111 | Phase 0.9: prod allowedDomains 有効化（RUNBOOK merged、実施待ち） |

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
9. **#91 / #141 の深掘り** — bug 系を先に（#141 は iOS + XcodeBuildMCP、#91 は SwiftData cleanup）
10. **P2 follow-up 残 (#145) を処理** — 昼/遅延セッションで #120 / #127 を消化済、残 1 件
11. **#102 / #105 テスト拡張** — Emulator Suite 必要、時間確保セッションで

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

- 個別 `xcodebuild -only-testing:` では全 PASS
- 全体 `xcodebuild test` では ClientRepositoryTests.fetchAll で Firebase 未 configure クラッシュ → 後続 66 件が連鎖失敗扱い
- **workaround**: 個別 test suite を `-only-testing:` で呼ぶ
- 開発ブロッカーではないが、CI / PR 確認時の混乱源

## ADR

- [ADR-007](../adr/ADR-007-guest-tenant-for-apple-signin.md) — Apple Sign-In 用 Guest Tenant 自動プロビジョニング。Status: 採用。
- [ADR-008](../adr/ADR-008-account-ownership-transfer.md) — アカウント所有権移行方式。Phase 0 棚卸し + Phase 1 実装詳細（状態遷移図、エラーマッピング、チェックポイント、監査ログスキーマ、Partial Update 不変性、入力検証、運用呼出フロー、count drift 仕様）まで記載。Status: Accepted。

## RUNBOOK

- [phase-1-admin-id-token.md](../runbook/phase-1-admin-id-token.md) — admin ID token 発行 + cleanup 手順（`get-admin-id-token.mjs --cleanup-uid` 使用）
- [phase-0-9-allowed-domains.md](../runbook/phase-0-9-allowed-domains.md) — Phase 0.9 allowedDomains 有効化手順（draft、ユーザー作業待ち）
- [prod-deploy-smoke-test.md](../runbook/prod-deploy-smoke-test.md) — prod deploy 統合 smoke test チェックリスト（2026-04-22 新設、Codex 推奨段階 deploy 方針に対応）

## 参考資料（本セッション = 2026-04-22 遅延）

- [PR #150 audit-createdby per-tenant 部分結果保持](https://github.com/system-279/carenote-ios/pull/150)
- [PR #151 transferOwnership errorId + err.stack](https://github.com/system-279/carenote-ios/pull/151)

## 参考資料（前セッション = 2026-04-22 昼）

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
