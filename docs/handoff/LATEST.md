# Handoff — Issue 整理 + 過剰起票防止ルール確立 + 7 PR merge (2026-04-22)

## セッション成果サマリ

本セッションで **7 PR merge / 10 Issue close / 3 Issue scope 絞り**を実施。Codex セカンドオピニオンに基づき「過剰起票」を防ぐ運用ルールを確立した。セッション開始時 open 16 件 → 終了時 **12 件**（net -4、PR merge 7 件）。

前セッションまでに完了した Node.js 22 upgrade / admin ID token helper / Phase 0.9 RUNBOOK は変更なし。prod deploy と iOS 実機 smoke test は引き続きユーザー作業待ち。

### マージ済み PR（本セッション）

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

### 1. iOS 実機 smoke test（全 prod deploy の前提ゲート）

**目的**: Phase 0.5 Rules + Phase 1 transferOwnership + Node 22 runtime の統合動作確認

検証動線（iOS 実機、dev build）:
- Apple Sign-In → `beforeSignIn` が `nodejs22` で起動し、`tenantId` custom claim 取得
- 新規録音作成 → Firestore に `createdBy=自分のuid` で保存
- 自分の録音の transcription 編集 → 成功
- RecordingList 表示 → 他人の録音も read 可で従来通り
- （可能なら）テストアカウントで `deleteAccount` callable 呼出、自データ削除 + Auth user 削除確認

**Node 22 起動確認のヒント**: Cloud Logging で `beforeSignIn` / `deleteAccount` / `transferOwnership` の container 起動ログに `nodejs22` が記録される。初回は cold start でやや遅延することあり（想定内）。

**失敗時の rollback**:
```
# Node 22 → 20 に戻す
git revert <commit of PR #130> && firebase deploy --only functions --project carenote-dev-279
# Rules を以前のバージョンに戻す
# Firestore Console → Rules → リビジョンから復元
```

> **注意**: 以下の prod deploy コマンドはすべて `firebase` CLI で `--project=carenote-prod-279` を明示する。`firebase` CLI は `gcloud` と別系統のため `CLOUDSDK_ACTIVE_CONFIG_NAME` は不要。ただし同じターミナルで `gcloud` を使う場合は `CLOUDSDK_ACTIVE_CONFIG_NAME=carenote-prod` の invocation 前置きを使うこと（CLAUDE.md 規範）。

### 2. Phase 0.5 Rules prod deploy（smoke test 通過後）

```
firebase deploy --only firestore:rules --project carenote-prod-279
```

prod 操作のため CLAUDE.md MUST に従いユーザー確認必須。

### 3. Phase 1 transferOwnership prod deploy（smoke test 通過後）

```
firebase deploy --only functions:transferOwnership --project carenote-prod-279
```

prod 操作のため ユーザー確認必須。

### 4. Node 22 runtime prod deploy（**期限 2026-04-30**、smoke test 通過後）

```
firebase deploy --only functions --project carenote-prod-279
```

- prod 操作のため ユーザー確認必須
- Node 20 は 2026-04-30 deprecated、2026-10-30 decommissioned
- deploy 後 `firebase functions:list --project=carenote-prod-279` で 3 関数が `nodejs22` ACTIVE 確認

### 5. Phase 0.9 `allowedDomains` 有効化（Phase 0.5/1/Node22 prod 完了 + 24h 監視後）

- RUNBOOK: `docs/runbook/phase-0-9-allowed-domains.md`
- 先に dev 先行検証（手順 A、4 パターン動作確認）
- prod 実施はユーザー明示承認必須

## Open Issue（優先度順、2026-04-22 時点 12 件）

### P0（要対応、open 継続中）

| # | タイトル | 状態 |
|---|---------|------|
| #100 | Firestore Rules の recordings 権限が過剰 | **実装は PR #115 で完了、dev deploy 済、prod deploy 完了後に close 予定**（本セッションで状態コメント追加） |

### bug（workaround あり）

| # | タイトル | 状態 |
|---|---------|------|
| #141 | ClientRepositoryTests 全体実行時の Firebase configure 未実行クラッシュ | 本セッション起票、原因候補コメント済、修正は別セッション |
| #91 | アカウント削除後のローカル SwiftData / Outbox クリーンアップ | 既存、要対応 |

### P2 follow-up（scope 絞り済）

| # | タイトル |
|---|---------|
| #120 | transferOwnership: CLI エラーロギング改善（errorId 付与 / err.stack 構造化） |
| #127 | audit-createdby.mjs: per-tenant 部分結果保持 |
| #145 | processItem upload 失敗時の createRecording 未呼出検証 |

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

## 次セッション推奨アクション（優先度順）

1. **iOS 実機 smoke test を済ませる**（Phase 0.5 / Phase 1 / Node 22 の統合動作確認、上記「ユーザー作業依頼 §1」）
2. **Phase 0.5 Rules prod deploy**（ユーザー承認 → Rules apply → #100 close）
3. **Phase 1 transferOwnership prod deploy**（ユーザー承認 → Cloud Function deploy）
4. **Node 22 runtime prod deploy（期限 2026-04-30）**（ユーザー承認 → 全 functions deploy）
5. **24h 監視後 Phase 0.9 dev 先行検証**（RUNBOOK `docs/runbook/phase-0-9-allowed-domains.md` § 手順 A）
6. **Phase 0.9 prod 実施**（ユーザー承認 → #111 close）
7. **#91 / #141 の深掘り** — bug 系を先に
8. **P2 follow-up (#120 / #127 / #145) を batch 処理** — 実害ベースで絞った scope のみ
9. **#102 / #105 テスト拡張** — Emulator Suite 必要、時間確保セッションで

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

## 参考資料（本セッション）

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
