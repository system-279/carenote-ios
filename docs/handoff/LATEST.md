# Handoff — アカウント所有権移行機能 設計着手 + Phase -1 重大バグ修正完了 (2026-04-20)

## セッション成果サマリ

ユーザーからの要望「テナント単位ドメイン全許可 + 改姓時のアカウント完全移行」の検討中、Codex セカンドオピニオンで **既存 `deleteAccount` Cloud Function が機能不全だった重大バグ** (issue #99) と **Firestore Rules の過剰権限** (issue #100) を発見。設計計画 (Phase -1 → Phase 0 → Phase 0.5 → Phase 1 → Phase 0.9) に基づき Phase -1 の先行修正を完了。

| PR | 内容 | 状態 |
|----|------|------|
| #101 | Phase -1: `createdBy` 正常保存 + 監査スクリプト + deleteAccount 統合テスト + Codex Critical 対応 | ✅ main |

## Phase -1 の重要発見と修正

### 発見された重大バグ（issue #99）

**dev/prod の全 recordings で `createdBy: ""` が保存されていた**:

| 環境 | Total | Empty | Non-empty |
|---|---|---|---|
| dev (carenote-dev-279) | 21 | 21 | 0 |
| prod (carenote-prod-279) | 8 | 8 | 0 |

影響:
- 本番稼働中の `deleteAccount` は `where("createdBy", "==", uid)` クエリで **常に 0 件ヒット** → recordings / Storage audio が削除されていなかった
- **App Store 5.1.1(v) アカウント削除要件の実装が実質未達**の可能性が高い
- 今後のアカウント移行機能も機能しない状態だった

### PR #101 の修正内容

- **A1**: `OutboxSyncService` に `currentUidProvider` を DI、`createdBy: uid` を正しく保存。uid 取得失敗時は `OutboxSyncError.userNotAuthenticated` を throw し既存 retry ラダーに乗せる
- **A2**: `functions/scripts/audit-createdby.mjs` で Firestore REST API による `createdBy` 分布計測
- **A4**: `functions/test/delete-account.test.js` に offline mock 統合テスト 7 ケース（空文字 regression + Codex C-Cdx-3 query 失敗時挙動含む）
- **Codex Critical**: `processItem` 冒頭で GCS orphan 防止の uid pre-flight check + deleteAccount の recordings query を try-catch で包み Auth 削除優先方針を実挙動に反映

### テスト結果

- iOS: 7/7 PASS（境界値 nil / "" / valid 網羅）
- functions (auth-blocking + delete-account): 21/21 PASS

## Phase 0 調査結果（ADR-008 に詳細）

uid 参照箇所の全棚卸し完了。移行 Function の書換対象が確定:

| コレクション | フィールド | 書換 | 備考 |
|---|---|---|---|
| `recordings.createdBy` | string | **必要** | PR #101 で uid 保存は正常化済み |
| `templates.createdBy` | string | **必要** | 新規発見 |
| `templates.createdByName` | string | 不変 | 意図的スナップショット |
| `whitelist.addedBy` | string | **必要** | 監査追跡のため |
| `clients/*` | - | 不要 | uid 参照なし |
| Cloud Storage path | - | 不要 | `{tenantId}/{recordingId}.m4a`、uid 非依存 |

詳細は [ADR-008](../adr/ADR-008-account-ownership-transfer.md) 参照。

## 現在の状態

- **ブランチ**: main
- **ビルド**: Build 35（App Store Connect 審査中、2026-04-16 提出）
- **審査通過見込み**: 90%+（リジェクト時の playbook は本セクション末尾参照）
- **アカウント移行機能**: Phase -1 完了、Phase 0 ADR 草案作成、Phase 0.5〜1 は未着手

## アカウント移行機能の Phase 構成

| Phase | 内容 | 状態 |
|---|---|---|
| Phase -1 | `createdBy` 正常保存 + 監査 + deleteAccount テスト | ✅ PR #101 マージ済 |
| Phase -1 A3 | 既存 29 件の `createdBy` バックフィル（別 PR） | ⏳ 未着手、I-Cdx-4/5 注意事項は #99 コメント参照 |
| Phase 0 | uid 参照棚卸し (ADR-008) | ✅ 本 PR で ADR 草案作成 |
| Phase 0.5 | Firestore Rules 強化 + `migrationLogs` collection 新設 | ⏳ issue #100 で追跡 |
| Phase 0.9 | `allowedDomains: ["279279.net"]` 有効化 | ⏳ Phase 0.5 完了後 |
| Phase 1 | `transferOwnership` Callable Function 実装 | ⏳ Phase 0.5 完了後 |
| Phase 2 | 本人主導 UI（移行コード方式） | 🔒 スコープ外（頻度低 × コスト高） |

## オープン Issue（アカウント移行機能関連）

| # | タイトル | ラベル | 優先度 |
|---|---------|--------|-------|
| #99 | 録音の `createdBy` が空文字で保存されている | bug, P0 | A3 バックフィル後にクローズ |
| #100 | Firestore Rules の recordings 権限が過剰 | bug, P0 | Phase 0.5 着手時 |
| #102 | deleteAccount テスト拡張（partial failure / auth error codes） | enhancement, P2 | - |
| #103 | audit-createdby 堅牢性（token cache / pagination 保護） | enhancement, P2 | - |
| #104 | delete-account test mock の深さ制限 | enhancement, P2 | - |
| #105 | deleteAccount E2E を Firebase Emulator Suite で実装 | enhancement, P2 | Phase 1 着手時に吸収予定 |
| #106 | `@preconcurrency` FirebaseAuth Sendable 制約明示化 | enhancement, P2 | - |
| #107 | `processItem` 主経路テスト追加 | enhancement, P2 | - |
| #108 | `firebase.json` runtime 重複解消 | bug, P2 | - |

## 既存オープン Issue

| # | タイトル | ラベル | 優先度 |
|---|---------|--------|-------|
| #71 | upload-testflight.sh に entitlements 検証ステップを追加 | P1, bug | 既存 |
| #65 | Apple ID アカウントリンク | enhancement | 将来対応 |
| #90 | Guest Tenant のスパム対策: TTL / レート制限 | enhancement | P2 |
| #91 | アカウント削除後のローカル SwiftData / Outbox クリーンアップ | bug | **P1**（セキュリティリスク） |
| #92 | Guest Tenant 利用者向けの「本番ログイン不可」案内UI | enhancement | P2 |
| #93 | deleteAccount Cloud Function の単体テスト追加 | enhancement | **PR #101 で完了**（クローズ候補） |

## 次セッション推奨アクション

### アカウント移行機能の続行（優先度順）

1. **A3: 既存 recordings の `createdBy` バックフィル PR**
   - 29 件（dev 21 + prod 8）の対応
   - Issue #99 I-Cdx-4/5 の注意事項（`"unknown"` 扱いは deleteAccount で消えない / 推定バックフィルは false attribution リスク）を踏まえ、stakeholder 合意後に方針決定
   - 候補: 全削除（テストデータ主体と思われるため）/ 隔離コレクション移動 / lifecycle rule 自動削除

2. **Phase 0.5: Firestore Rules 強化 (#100)**
   - `recordings` を owner (`createdBy == uid`) + admin に絞る
   - `migrationLogs` collection 新設（admin のみ read、Cloud Function のみ write）
   - `@firebase/rules-unit-testing` をセット、CI 組込み

3. **Phase 1: `transferOwnership` Cloud Function 実装**
   - ADR-008 の書換対象（recordings + templates + whitelist）
   - 二段階 confirm (dryRun → dryRunId 指定 confirm)
   - chunked batch write + `migrationState.lastDocId` で中断再開可
   - `migrationLogs/{id}` に監査ログ記録
   - 初期実装で `deleteOldAuthUser` は外す（別 Function に分離）

4. **Phase 0.9: allowedDomains 有効化**
   - prod `tenants/279.allowedDomains = ["279279.net"]` を Firestore 直接更新
   - 運用手順書化

### App Store 審査関連

**審査通過時:**
1. Issue #91（Outbox 誤送信セキュリティリスク）を最優先
2. Issue #93 は PR #101 でカバー → クローズ検討
3. #90 / #92 順次対応

**リジェクト時:**
1. リジェクト理由精読 + ADR-007 照合
2. Guideline 別 playbook（2.1(a) / 5.1.1(v) / 4.8）
3. `/codex review` でセカンドオピニオン

## CI / 既知問題

- PR #101 の CI: test PASS (32m17s)
- 過去の CI #96 失敗は GitHub Actions の iOS Simulator Runtime 接続失敗（exit 70）、コード起因ではない

## 参考資料

- [PR #101 Phase -1 修正](https://github.com/system-279/carenote-ios/pull/101)
- [ADR-008 アカウント所有権移行方式](../adr/ADR-008-account-ownership-transfer.md)
- [ADR-007 Guest Tenant 設計判断](../adr/ADR-007-guest-tenant-for-apple-signin.md)
- [Issue #99 createdBy 空文字バグ](https://github.com/system-279/carenote-ios/issues/99)（監査結果コメント + A3 設計注意事項あり）
