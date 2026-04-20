# Handoff — アカウント移行機能 Phase -1/0/0.5/1 完了、Phase 0.9 待機 (2026-04-21)

## セッション成果サマリ

アカウント所有権移行機能の Phase -1 から Phase 1 まで完了。Phase 0.9 (`allowedDomains` 有効化) の前提となる rules 強化 + 権限移管機能が揃い、ユーザー側の smoke test + prod deploy 承認を待つ状態。

### マージ済み PR（2026-04-21 セッション）

| PR | 内容 | Issue |
|----|------|-------|
| #113 | CI paths-ignore（iOS 軽量化） | — |
| #112 | Phase -1 A3 dev バックフィル + 削除スクリプト | #99 |
| #115 | Phase 0.5 Firestore Rules 強化 + migrationLogs collection | #100 |
| #117 | Phase -1 A3 prod バックフィル実施記録 | **#99 closed** |
| #118 | CI Java 17→21 (firebase-tools 要件) | — |
| #119 | Phase 1 transferOwnership Callable Function | **#110 closed** |

### 実施済み prod/dev operation（履歴）

| 環境 | 操作 | 結果 |
|---|---|---|
| dev | A3 バックフィル execute | 21 件削除、audit empty=0 |
| prod | A3 バックフィル execute (`CONFIRM_PROD=yes`) | 8/8 削除成功、audit empty=0 |
| dev | Firestore Rules deploy | `firebase deploy --only firestore:rules` ✅ |
| dev | transferOwnership Cloud Function deploy | Node.js 20 2nd Gen、asia-northeast1 ✅ |

### 解消した Critical Issue

- **#99** createdBy 空文字バグ → PR #101/#112/#117 で完全解決
- **#100** Firestore Rules 過剰権限 → PR #115 で解決（dev deploy 済、prod deploy 残）
- **#110** transferOwnership 実装 → PR #119 で解決（dev deploy 済、prod deploy 残）

## 現在の状態

- **ブランチ**: main（clean、CI green）
- **ビルド**: Build 35（App Store Connect 審査中、2026-04-16 提出）
- **審査通過見込み**: 90%+（deleteAccount が実データで機能する状態を確立済み）
- **アカウント移行機能**: **Phase -1 / 0 / 0.5 / 1 完了**、Phase 0.9 は smoke test + prod deploy 後

## アカウント移行機能の Phase 構成

| Phase | 内容 | 状態 |
|---|---|---|
| Phase -1 | `createdBy` 正常保存 + 監査 + deleteAccount テスト | ✅ PR #101 マージ済 |
| Phase -1 A3 dev | dev 21 件バックフィル削除 | ✅ PR #112 (2026-04-20) |
| Phase -1 A3 prod | prod 8 件バックフィル削除 | ✅ 実施済 + PR #117 (2026-04-21) |
| Phase 0 | uid 参照棚卸し (ADR-008) | ✅ PR #109 |
| Phase 0.5 | Firestore Rules 強化 + migrationLogs + rules-unit-testing + CI 組込 | ✅ PR #115 merged + dev deploy 完了 (2026-04-21) |
| Phase 0.9 | `allowedDomains: ["279279.net"]` 有効化 | ⏳ **ユーザー作業待ち**（smoke test + prod deploy 後） |
| Phase 1 | `transferOwnership` Callable Function 実装 | ✅ PR #119 merged + dev deploy 完了 (2026-04-21) |
| Phase 2 | 本人主導 UI（移行コード方式） | 🔒 スコープ外（頻度低 × コスト高） |

## ユーザー作業依頼（次セッション再開に関わる重要項目）

### 1. iOS 実機 smoke test（Phase 0.5 dev → prod 移行ゲート）

**目的**: Firestore Rules 強化後の iOS 動作確認。dev 環境で下記が通常通り動くこと:

- 新規録音作成 → Firestore に `createdBy=自分のuid` で保存
- 自分の録音の transcription 編集 → 成功
- RecordingList 表示 → 他人の録音も（read 可）従来通り表示
- 他人の録音編集を試みる操作があれば → 拒否されること（現在 UI に該当なし、実質 admin SDK 経由のみ update）

**失敗時の rollback**:
```
# Firestore Console → Rules → 以前のバージョンにリリース
# または
firebase deploy --only firestore:rules --project carenote-dev-279  # 旧コミットの rules
```

### 2. transferOwnership dev smoke test（Phase 1 dev → prod 移行ゲート）

**目的**: Callable Function の動作確認。`firebase functions:shell` で呼出:

```
firebase functions:shell --project carenote-dev-279
> transferOwnership({ fromUid: "test-from", toUid: "test-to", dryRun: true }, { auth: { uid: "admin-x", token: { tenantId: "279", role: "admin" } } })
# → { dryRunId, counts: {...} }
> transferOwnership({ dryRunId: "<上の id>" }, { auth: adminの auth })
# → { ok: true, updated: {...} }
```

もしくは本番相当の admin アカウントでテストデータを用意し、end-to-end 確認。

**ロールバック**: Cloud Function 削除で即無効化。データ更新は migrationLogs に残るため監査可能。

### 3. Phase 0.5 prod deploy 承認 (smoke test 通過後)

```
firebase deploy --only firestore:rules --project carenote-prod-279
```

prod 操作のため CLAUDE.md に従いユーザー確認ゲートあり。

### 4. Phase 1 prod deploy 承認 (smoke test 通過後)

```
firebase deploy --only functions:transferOwnership --project carenote-prod-279
```

prod 操作のため ユーザー確認必須。

### 5. Sprint E: Phase 0.9 `allowedDomains` 有効化 (Phase 0.5/1 prod 完了後)

- Issue #111 で追跡
- prod `tenants/279.allowedDomains = ["279279.net"]` を Firestore に設定
- RUNBOOK 作成 + `beforeSignIn` で allowedDomains が参照されることの動作確認

## Open Issue（優先度順）

### P0（ブロッカーなし、現時点で CLOSED）

_Issue #99 / #100 / #110 は本セッションで全て解決_

### P1

| # | タイトル | 状態 |
|---|---------|------|
| #71 | upload-testflight.sh に entitlements 検証ステップを追加 | 既存、要対応 |
| #91 | アカウント削除後のローカル SwiftData / Outbox クリーンアップ | セキュリティリスク、要対応 |

### P2（本セッション follow-up）

| # | タイトル |
|---|---------|
| #114 | delete-empty-createdby: 統合テスト・ログ強化 |
| #116 | Firestore Rules 追加エッジケーステスト |
| #120 | transferOwnership: /review-pr 指摘の残課題 (logging / CLI / boundary tests) |

### P2（既存）

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
| #108 | `firebase.json` runtime 重複 + Node.js 20 deprecation (2026-10-30) |
| #111 | Phase 0.9: prod allowedDomains 有効化（Phase 0.5/1 prod deploy 後） |

### 将来対応

| # | タイトル |
|---|---------|
| #65 | Apple ID アカウントリンク |

## 次セッション推奨アクション（優先度順）

1. **Phase 0.5 iOS smoke test を済ませる**（上記「ユーザー作業依頼 §1」）
2. **Phase 1 dev smoke test を済ませる**（上記「ユーザー作業依頼 §2」）
3. **Phase 0.5 prod deploy**（ユーザー承認 → Rules apply）
4. **Phase 1 prod deploy**（ユーザー承認 → Cloud Function deploy）
5. **Sprint E: Phase 0.9 RUNBOOK 作成 + prod allowedDomains 設定**（Issue #111）
6. App Store 審査結果次第で Issue #91/#71 に優先対応

### deleteOldAuthUser 分離 Function（Phase 1 残件）

Issue #110 本体は transferOwnership のみ。旧 Auth user 削除は別 Function として残してあるため、将来独立 Issue 化して実装する（ロールバック余地を Phase 1 完了後に評価）。

## Aliyah / 既知の警告

### Cloud Functions Node.js 20 deprecation

- dev deploy 時に警告: 「Runtime Node.js 20 will be deprecated on 2026-04-30 and will be decommissioned on 2026-10-30」
- Issue #108 に firebase.json runtime 重複解消とあわせて記載。`nodejs20` → `nodejs22` へ upgrade 必要
- firebase-functions パッケージも outdated 警告

### CI Workflow

- `.github/workflows/test.yml` (iOS Tests) は paths-ignore で `firestore.rules` / `functions/**` / `docs/**` / `.github/**` 等を除外
- `.github/workflows/functions-test.yml` (Functions & Rules Tests) が Firestore + Auth emulator で 109 tests を実行
- GitHub Actions iOS Simulator install の infra 失敗 (exit 70) は paths-ignore で回避済み

## ADR

- [ADR-008](../adr/ADR-008-account-ownership-transfer.md) — アカウント所有権移行方式。Phase 0 棚卸し + Phase 1 実装詳細（状態遷移図、エラーマッピング、チェックポイント、監査ログスキーマ、Partial Update 不変性、入力検証、運用呼出フロー、count drift 仕様）まで記載。Status: Accepted。

## 参考資料

- [PR #101 Phase -1](https://github.com/system-279/carenote-ios/pull/101)
- [PR #112 A3 dev バックフィル](https://github.com/system-279/carenote-ios/pull/112)
- [PR #115 Phase 0.5 Rules](https://github.com/system-279/carenote-ios/pull/115)
- [PR #117 A3 prod バックフィル](https://github.com/system-279/carenote-ios/pull/117)
- [PR #119 Phase 1 transferOwnership](https://github.com/system-279/carenote-ios/pull/119)
- [ADR-008 アカウント所有権移行方式](../adr/ADR-008-account-ownership-transfer.md)
- [ADR-007 Guest Tenant 設計判断](../adr/ADR-007-guest-tenant-for-apple-signin.md)
