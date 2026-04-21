# Handoff — Node.js 22 upgrade 完了、iOS smoke test + prod deploy 承認待ち (2026-04-21)

## セッション成果サマリ

本セッションで Firebase Functions の Node.js 22 runtime 移行（2026-04-30 deprecation 対応）、admin ID token helper の堅牢化、Phase 0.9 RUNBOOK ドラフト化、Firestore Rules エッジケーステスト拡充の 4 PR を merge。dev functions は全て nodejs22 で ACTIVE。iOS 実機 smoke test 完了後に prod deploy 系統（Phase 0.5 Rules / Phase 1 transferOwnership / Node 22 runtime / Phase 0.9 allowedDomains）を段階的に展開する段階。

### マージ済み PR（本セッション追加分）

| PR | 内容 | Issue |
|----|------|-------|
| #130 | Node.js 20→22 runtime upgrade + firebase.json 重複キー整理 | **#124 closed**, **#108 closed** |
| #132 | admin ID token helper 堅牢化 + CONFIRM_PROD nonce 統一 | **#129 closed** |
| #133 | Phase 0.9 allowedDomains 有効化 RUNBOOK draft | #111 relates |
| #134 | Firestore Rules エッジケーステスト 11 件追加 (55 tests PASS) | **#116 closed** |

### 起票した follow-up Issue

| # | タイトル | Priority |
|---|---------|---------|
| #131 | firebase.json hosting キー重複整理 (Issue #124 follow-up) | P2 |
| #135 | rules tests の更なる堅牢化 (role 値バリエーション + createdBy 型) | P2 |

### 実施済み prod/dev operation（履歴）

| 環境 | 操作 | 結果 | セッション |
|---|---|---|---|
| dev | A3 バックフィル execute | 21 件削除、audit empty=0 | 先行 |
| prod | A3 バックフィル execute (`CONFIRM_PROD=yes`) | 8/8 削除成功、audit empty=0 | 先行 |
| dev | Firestore Rules deploy | `firebase deploy --only firestore:rules` ✅ | 先行 |
| dev | transferOwnership Cloud Function deploy | Node.js 20 2nd Gen → **Node.js 22** (本セッションで upgrade) | 先行 + 本セッション |
| dev | functions deploy (Node 22) | 3 関数全て `nodejs22` ACTIVE、Cloud Logging ERROR 0 件 (本セッション 2026-04-21) | **本セッション** |

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
| Phase 0.5 拡充 | エッジケーステスト 11 件追加 (55 tests) | ✅ PR #134 |
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

### 6. 本 handoff の更新

本セッション更新内容を確認後、不要な先行セッション記述があれば整理。次セッション終盤に再度 `/handoff` で整合性チェック。

## Open Issue（優先度順）

### P0
_解消済み: #99 / #100 / #110 / #116 / #124 / #108 / #129_

### P1

| # | タイトル | 状態 |
|---|---------|------|
| #71 | upload-testflight.sh に entitlements 検証ステップを追加 | 既存、要対応 |
| #91 | アカウント削除後のローカル SwiftData / Outbox クリーンアップ | セキュリティリスク、要対応 |

### P2（本セッション起票）

| # | タイトル |
|---|---------|
| #131 | firebase.json hosting キー重複整理 (#124 follow-up) |
| #135 | Firestore Rules tests follow-up (role 値 + createdBy 型) |

### P2（既存、未対応）

| # | タイトル |
|---|---------|
| #90 | Guest Tenant スパム対策: TTL / レート制限 |
| #92 | Guest Tenant 利用者向けの「本番ログイン不可」案内UI |
| #102 | deleteAccount テスト拡張（partial failure / auth error codes） |
| #103 | audit-createdby 堅牢性（token cache / pagination 保護） |
| #104 | delete-account test mock の深さ制限 |
| #105 | deleteAccount E2E を Firebase Emulator Suite で実装 |
| #106 | `@preconcurrency` FirebaseAuth Sendable 制約明示化 |
| #107 | `processItem` 主経路テスト追加 |
| #111 | Phase 0.9: prod allowedDomains 有効化（RUNBOOK merged、実施待ち） |
| #114 | delete-empty-createdby: 統合テスト・ログ強化 |
| #120 | transferOwnership: /review-pr 指摘の残課題 (logging / CLI / boundary tests、part 1 は #129 で完了) |
| #127 | audit-createdby per-tenant 部分結果保持 + retry 履歴 |

### 将来対応

| # | タイトル |
|---|---------|
| #65 | Apple ID アカウントリンク |

## 次セッション推奨アクション（優先度順）

1. **iOS 実機 smoke test を済ませる**（Phase 0.5 / Phase 1 / Node 22 の統合動作確認、上記「ユーザー作業依頼 §1」）
2. **Phase 0.5 Rules prod deploy**（ユーザー承認 → Rules apply）
3. **Phase 1 transferOwnership prod deploy**（ユーザー承認 → Cloud Function deploy）
4. **Node 22 runtime prod deploy（期限 2026-04-30）**（ユーザー承認 → 全 functions deploy）
5. **24h 監視後 Phase 0.9 dev 先行検証**（RUNBOOK `docs/runbook/phase-0-9-allowed-domains.md` § 手順 A）
6. **Phase 0.9 prod 実施**（ユーザー承認）
7. 残 P2（#127 / #114 / #106 / #107 / #131 / #135）を batch 処理
8. App Store 審査結果次第で Issue #91 / #71 に優先対応

### deleteOldAuthUser 分離 Function（Phase 1 残件）

Issue #110 本体は transferOwnership のみ。旧 Auth user 削除は別 Function として残してあるため、将来独立 Issue 化して実装する（ロールバック余地を Phase 1 完了後に評価）。

## 既知の警告

### Cloud Functions Node.js 22 runtime（Issue #124 / #108 解消済み、本セッション）

- dev 3 関数は 2026-04-21 時点で nodejs22 ACTIVE、deprecation warning 消滅
- prod は未 deploy（ユーザー承認必要、期限 2026-04-30）
- firebase.json `hosting` キー重複は別 Issue #131 で追跡（scope 外）

### CI Workflow

- `.github/workflows/test.yml` (iOS Tests) は paths-ignore で `firestore.rules` / `functions/**` / `docs/**` / `.github/**` 等を除外
- `.github/workflows/functions-test.yml` (Functions & Rules Tests) が Firestore + Auth emulator で全テストスイート（`npm test` = 5 ファイル合計 120 tests、うち rules-only は 55）を実行（Node 22、エッジケーステスト 11 件追加後）

## ADR

- [ADR-007](../adr/ADR-007-guest-tenant-for-apple-signin.md) — Apple Sign-In 用 Guest Tenant 自動プロビジョニング。Status: 採用。
- [ADR-008](../adr/ADR-008-account-ownership-transfer.md) — アカウント所有権移行方式。Phase 0 棚卸し + Phase 1 実装詳細（状態遷移図、エラーマッピング、チェックポイント、監査ログスキーマ、Partial Update 不変性、入力検証、運用呼出フロー、count drift 仕様）まで記載。Status: Accepted。

## RUNBOOK

- [phase-1-admin-id-token.md](../runbook/phase-1-admin-id-token.md) — admin ID token 発行 + cleanup 手順（`get-admin-id-token.mjs --cleanup-uid` 使用）
- [phase-0-9-allowed-domains.md](../runbook/phase-0-9-allowed-domains.md) — Phase 0.9 allowedDomains 有効化手順（draft、ユーザー作業待ち）

## 参考資料（本セッション）

- [PR #130 Node 22 upgrade](https://github.com/system-279/carenote-ios/pull/130)
- [PR #132 admin ID token helper 堅牢化](https://github.com/system-279/carenote-ios/pull/132)
- [PR #133 Phase 0.9 RUNBOOK draft](https://github.com/system-279/carenote-ios/pull/133)
- [PR #134 Rules エッジケーステスト](https://github.com/system-279/carenote-ios/pull/134)

## 参考資料（先行セッション）

- [PR #101 Phase -1](https://github.com/system-279/carenote-ios/pull/101)
- [PR #112 A3 dev バックフィル](https://github.com/system-279/carenote-ios/pull/112)
- [PR #115 Phase 0.5 Rules](https://github.com/system-279/carenote-ios/pull/115)
- [PR #117 A3 prod バックフィル](https://github.com/system-279/carenote-ios/pull/117)
- [PR #119 Phase 1 transferOwnership](https://github.com/system-279/carenote-ios/pull/119)
- [PR #128 admin ID token helper part 1](https://github.com/system-279/carenote-ios/pull/128)
