# ADR-008: アカウント所有権移行方式（Phase 0: uid 参照箇所棚卸し）

**Status**: Draft（Phase 1 着手時に Accepted へ更新）
**Date**: 2026-04-20
**Supersedes**: なし
**Related**: Issue #99、PR #101、Issue #100（Firestore Rules 強化）

## Context

ユーザー改姓（例: `tanaka@279279.net` → `itou@279279.net`）等でメールごと Firebase Auth のアカウントが新規作成され uid が変わるケースで、過去の録音データを完全に新 uid に引き継ぐ機能が必要。

Firebase Auth Account Linking は同一 provider の異なるメールアカウント間で uid を保持できない（`credentialAlreadyInUse`）ため、「データ所有権移行」方式で対応する。

## Phase 0 調査結果: uid 参照箇所マップ

Explore エージェントによるコードベース全域棚卸しの結果。

### Firestore フィールド（書換対象）

| コレクション | フィールド | 型 | 用途 | 移行時の扱い |
|---|---|---|---|---|
| `tenants/{tid}/recordings/{rid}` | `createdBy` | string | 作成者 uid | **書換必要** |
| `tenants/{tid}/templates/{tid}` | `createdBy` | string | テンプレート作成者 uid | **書換必要** |
| `tenants/{tid}/whitelist/{eid}` | `addedBy` | string | whitelist エントリ追加者 uid | **書換必要**（監査追跡） |

### Firestore フィールド（不変）

| フィールド | 理由 |
|---|---|
| `templates.createdByName` | 意図的スナップショット（当時の表示名を保持） |
| `recordings.audioStoragePath` | gs:// URI、uid 非依存 |
| `tenants/{tid}` トップレベル | uid を含まない |
| `tenants/{tid}/clients/{cid}` | uid 参照なし |

### Cloud Storage

| path パターン | uid 含有 | 移行時の扱い |
|---|---|---|
| `{tenantId}/{recordingId}.m4a` | 含まない | **変更不要** |

Storage rules も uid 基準の ACL ではなく `request.auth.token.tenantId` のみなので、rules 変更も不要。

### iOS Swift コード（uid 取得点）

| ファイル | 参照種別 | 影響 |
|---|---|---|
| `AuthViewModel.swift` | `Auth.auth().currentUser?.uid` | uid 取得の中心。サインアウト/再ログインで自動更新 |
| `OutboxSyncService.swift` (PR #101 修正済) | `currentUidProvider()` を DI、`buildFirestoreRecording` で `createdBy` に設定 | **主経路**。空文字拒否ロジック有 |
| `RecordingConfirmViewModel.swift` (PR #101 修正済) | `{ Auth.auth().currentUser?.uid }` クロージャを渡す | 録音確定時の uid 提供 |
| `TemplateCreateViewModel.swift` | `userId` を init で受取、`createdBy` として渡す | テンプレート作成時の uid 固定 |
| `KeychainHelper.swift` | Apple authCode 保存（uid 自体ではない） | deleteAccount 時の revoke 用、uid 変動で stale 化するが best-effort |

### Cloud Functions (Node.js)

| ファイル:行 | 参照 | 影響 |
|---|---|---|
| `functions/index.js:115` | `request.auth?.uid` | deleteAccount の呼出元特定 |
| `functions/index.js:133` | `.where("createdBy", "==", uid)` | recordings フィルタ |
| `functions/index.js:167` | `admin.auth().deleteUser(uid)` | Firebase Auth user 削除 |

### uid 参照なし（確認済）

- FCM token
- Analytics userId / Crashlytics userId
- UserDefaults
- Cloud Storage metadata

## 対称性の崩れ（設計上の要注意点）

### 1. read は tenant 全件 / delete は uid フィルタ

- `fetchTemplates` / `fetchWhitelist` / `fetchRecordings` は tenant 内全件取得（uid フィルタなし）
- `deleteAccount` の recordings 削除は `createdBy == uid` でフィルタ
- **結果**: 移行前の古い uid で作成された templates / whitelist は、read は問題なく見えるが、移行忘れがあると `deleteAccount` では削除されない

### 2. templates / whitelist の orphan リスク

- `deleteAccount` は recordings のみ削除、templates / whitelist は残る
- 退職者が admin として追加した whitelist entry や template が、アカウント削除後も残存
- Issue #91（アカウント削除後のローカル SwiftData / Outbox クリーンアップ）と合わせて設計見直し必要

## 決定事項

### Phase 1 (transferOwnership Cloud Function) のスコープ

**書換対象**（必須）:
- `tenants/{tid}/recordings/{rid}.createdBy: fromUid → toUid`
- `tenants/{tid}/templates/{tid}.createdBy: fromUid → toUid`
- `tenants/{tid}/whitelist/{eid}.addedBy: fromUid → toUid`

**書換不要**:
- `templates.createdByName`（意図的スナップショット）
- Cloud Storage path（uid 非依存）
- `clients`（uid 参照なし）
- Auth customClaims（tenant/role 変わらず、旧 uid の claims は放置で OK）

### トランザクション境界

1 回の `transferOwnership` 呼出で 3 collection をまとめて更新。Firestore batched write は 500 件制限のため、collection ごとに chunked batch + `migrationState.lastDocId` で中断再開可能な設計（Phase 1 の詳細設計で確定）。

### 順序

1. `migrationState: prepared` ドキュメント作成（dryRun で件数プレビュー）
2. 二段階 confirm で実行開始、`status: running`
3. `recordings` → `templates` → `whitelist` の順に chunked batch で更新
4. 完了時 `status: completed`、`migrationLogs/{id}` に記録
5. 旧 Auth user 削除は default=false（ロールバック余地）

### スコープ外（別途対応）

- **テナント跨ぎ移行**: 同テナント内限定
- **複数 uid 束ね**: 1:1 移行のみ（`transferOwnership(fromUid, toUid)`）
- **取り消し（rollback）**: 監査ログは残すが自動 rollback 機能は実装しない

## 影響する既存実装（PR #101 完了）

- `OutboxSyncService.createdBy = uid` の正常保存は PR #101 で実装済（issue #99 の根本修正）
- `deleteAccount` は `createdBy == uid` クエリで recordings 削除、query 失敗時も Auth 削除に到達（PR #101 で try-catch 化）

## 影響する既存 Issue

- **#99**: createdBy 空文字バグ → PR #101 で新規分は修正済、既存 29 件は A3 (バックフィル) で対応予定
- **#100**: Firestore Rules の recordings 過剰権限 → Phase 0.5 で owner + admin に絞る予定
- **#102-108**: PR #101 レビューで挙がったフォローアップ群

## 参照

- [Firebase Auth Account Linking](https://firebase.google.com/docs/auth/ios/account-linking) - 同一 provider 異メール間の uid 保持不可を確認
- [Codex review for PR #101](https://github.com/system-279/carenote-ios/pull/101) - Phase -1 Critical 指摘
- Explore エージェント棚卸し結果（本セッション 2026-04-20）
