# RUNBOOK: `transferOwnership` 用 admin ID token の取得

**ステータス**: 運用可能
**対象**: `call-transfer-ownership.mjs` 方式B / 他の Callable Function を admin 権限で叩く必要がある one-off 運用
**関連**: Issue #120、`docs/runbook/phase-1-transfer-ownership-smoke-test.md` 方式B、`functions/scripts/get-admin-id-token.mjs`

---

## いつ使うか

- Phase 1 `transferOwnership` dev smoke test **方式B**（prod 相当経路での動作確認）
- 緊急の one-off 所有権移行運用
- その他、Firebase Auth の admin custom claim を要する Callable を CLI から叩く場合

**iOS 側にデバッグコードを追加して ID token をログ出力する方式は禁止**（revert 忘れで debug コードが merge されるリスクが高い）。本 RUNBOOK の helper script を使うこと。

---

## 前提

- `gcloud auth application-default login` で ADC 設定済（`system@279279.net` アカウント）
- Firebase Admin SDK が `node_modules` に存在（`functions/` で `npm ci` 済）
- 作業 shell が repository root にある（`GoogleService-Info.plist` 自動解決用）

---

## 手順 A: dev 環境

### 1. 一時 admin uid の決定

本 ID token は既存ユーザーの identity を借りる形式。以下のいずれか:

- **推奨: 一時 uid パターン** — `transferOp-<initials>-<YYYYMMDD>`（例: `transferOp-yh-20260421`）
  - 運用後に `auth.deleteUser()` で確実に削除できる
  - admin 権限付与が一時的であることが uid 名から明らか
- 既存 admin ユーザーの uid（監査ログに自分の実 uid が残るメリット）

### 2. ID token の発行

```bash
node functions/scripts/get-admin-id-token.mjs \
  --project carenote-dev-279 \
  --uid transferOp-yh-20260421 \
  --tenant-id 279 \
  --role admin
```

処理内容:
1. Admin SDK (ADC) で該当 uid を Auth に upsert
2. `custom claims: { tenantId, role: "admin" }` を set
3. custom token を発行
4. Identity Toolkit `signInWithCustomToken` REST で ID token に交換（~1 時間有効）

stdout に ID token（JWT）のみが出力される。stderr には診断情報（user 作成有無 / claims 設定）が出る。

### 3. Callable 呼出

```bash
# 1 行で使う場合
ID_TOKEN=$(node functions/scripts/get-admin-id-token.mjs \
  --project carenote-dev-279 \
  --uid transferOp-yh-20260421 \
  --tenant-id 279 --role admin)

node functions/scripts/call-transfer-ownership.mjs \
  --project carenote-dev-279 \
  --from-uid <old-uid> --to-uid <new-uid> \
  --dry-run \
  --id-token "$ID_TOKEN"
```

ID token は ~1 時間有効。dryRun → confirm の操作は同一 token で十分間に合う。

### 4. cleanup

```bash
cat > /tmp/cleanup-admin-uid.mjs <<'EOF'
import { initializeApp, applicationDefault } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
initializeApp({ credential: applicationDefault(), projectId: "carenote-dev-279" });
await getAuth().deleteUser("transferOp-yh-20260421");
console.log("deleted");
process.exit(0);
EOF
node /tmp/cleanup-admin-uid.mjs
```

一時 uid 方式を採用した場合は必ず実行。既存 admin uid を流用した場合はこの手順をスキップし、claims だけ元に戻すか、role を変えずに放置（元から admin の場合）。

---

## 手順 B: prod 環境

**CLAUDE.md MUST**: prod 操作前にユーザー承認取得。以下コマンドをエージェントが自動実行することは禁止。

### 1. 事前確認

- prod の `transferOwnership` function が deploy 済（`firebase functions:list --project=carenote-prod-279` で `ACTIVE` 確認）
- `migrationLogs` / `migrationState` 書込許可のある Rules が deploy 済（Phase 0.5 PR #115 prod 反映後）
- low-traffic 時間帯

### 2. ID token 発行

```bash
CONFIRM_PROD=yes \
CLOUDSDK_ACTIVE_CONFIG_NAME=carenote-prod \
  node functions/scripts/get-admin-id-token.mjs \
    --project carenote-prod-279 \
    --uid transferOp-yh-20260421 \
    --tenant-id 279 --role admin
```

`CONFIRM_PROD=yes` が無いと helper script が exit 2 で即拒否する。

### 3. transferOwnership 呼出

```bash
ID_TOKEN=$(CONFIRM_PROD=yes CLOUDSDK_ACTIVE_CONFIG_NAME=carenote-prod \
  node functions/scripts/get-admin-id-token.mjs \
    --project carenote-prod-279 --uid transferOp-yh-20260421 \
    --tenant-id 279 --role admin)

CONFIRM_PROD=yes \
  node functions/scripts/call-transfer-ownership.mjs \
    --project carenote-prod-279 \
    --from-uid <old-uid> --to-uid <new-uid> \
    --dry-run \
    --id-token "$ID_TOKEN"

# 問題なければ confirm
CONFIRM_PROD=yes \
  node functions/scripts/call-transfer-ownership.mjs \
    --project carenote-prod-279 \
    --dry-run-id <uuid> --confirm \
    --id-token "$ID_TOKEN"
```

### 4. 一時 uid の削除（必ず実施）

dev 手順 A § 4 の cleanup スクリプトを `projectId: "carenote-prod-279"` と `CONFIRM_PROD=yes` + `CLOUDSDK_ACTIVE_CONFIG_NAME=carenote-prod` で実行。

`migrationLogs` に記録された caller uid は削除されない（監査ログは保持）。

---

## セキュリティ注意事項

| 項目 | 対応 |
|---|---|
| API_KEY の扱い | 公開 identifier（iOS バイナリに埋込済）なので helper script への引数 / ログ出力は許容 |
| ID token の扱い | **機密**。shell history に残さないよう `ID_TOKEN=$(...)` で変数経由、`--id-token "$ID_TOKEN"` で渡す |
| 一時 admin uid | 作業終了後に必ず delete。放置すると永続的 admin 権限が残る |
| prod 実行履歴 | `migrationLogs/<dryRunId>` に caller uid + 操作内容が自動記録される |
| GOOGLE_APPLICATION_CREDENTIALS | **使わない**。`gcloud auth application-default login` の ADC を利用 |

---

## トラブルシューティング

### `signInWithCustomToken HTTP 400: INVALID_CUSTOM_TOKEN`

- 時刻ずれ (`gcloud auth application-default login` を再実行して ADC を refresh)
- API key と project id が不一致 (`--api-key` を明示的に指定)

### `Error: permission-denied: 管理者のみ実行可能です`

- `transferOwnership` は `request.auth.token.role === "admin"` を要求
- helper script が set した claims が ID token に反映されているか確認: ID token を [jwt.io](https://jwt.io) にペースト → payload に `role: "admin"` が入っていること
- helper script 内で claims を set してから custom token を発行しているので、通常ここで失敗しない。失敗した場合は helper script の logs (stderr) を確認

### `--id-token is required` (call-transfer-ownership.mjs)

- ID token 発行コマンドの stderr 出力が stdout に混ざって JWT 以外の文字列が取れている可能性
- `node get-admin-id-token.mjs ... 2>/dev/null` で stderr を捨てて stdout のみ取るか、`command substitution` で最終行だけ抽出

---

## 関連

- [Phase 1 transferOwnership smoke test](./phase-1-transfer-ownership-smoke-test.md)
- [ADR-008 アカウント所有権移行方式](../adr/ADR-008-account-ownership-transfer.md)
- Issue #120 (本 RUNBOOK の整備トリガー)
- `functions/scripts/get-admin-id-token.mjs` (本 RUNBOOK の主役)
- `functions/scripts/call-transfer-ownership.mjs` (ID token の消費者)
