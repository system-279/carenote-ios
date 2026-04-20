# RUNBOOK: Phase 0.9 `tenants/279.allowedDomains` 有効化

**ステータス**: 準備完了 / prod 実行待ち
**対象 Issue**: #111
**前提**: Phase 0.5 (PR #115) prod Rules deploy 完了 / Phase 1 (PR #119) prod Function deploy 完了
**関連**: ADR-007 Guest Tenant、`functions/index.js` の `beforeSignIn` allowedDomains 評価ブロック

## 完了条件チェックリスト

本 RUNBOOK は以下が全て埋まった時点で完了とする。未達のまま Issue #111 をクローズしない。

- [ ] 事前確認セクションで既存 whitelist ドメインを確認
- [ ] dev 先行検証結果記録欄を全て埋める
- [ ] prod 実施記録欄を全て埋める
- [ ] prod 実施後動作確認 3 項目すべて PASS

---

## 目的

prod tenant `279` の `allowedDomains` を `["279279.net"]` に設定し、`@279279.net` ドメインの Google / Email ユーザーを**招待なしで tenant `279` の member として自動サインインさせる**。

許可外ドメインの挙動は変更なし:
- Apple Sign-In → Guest Tenant (`demo-guest`) 振り分け（ADR-007 既存動作）
- Google / Email → `permission-denied`（既存動作）

実装詳細は `functions/index.js` の `beforeSignIn` 関数内、whitelist match の後に続く `allowedDomains` 評価ブロック (`// 2. Allowed domains: domain match` コメント直下) を参照。

## 影響範囲

| 対象 | 影響 |
|---|---|
| `tenants/279` 既存メンバー | 影響なし（whitelist が先に評価される） |
| `@279279.net` 新規サインイン | **NEW**: tenant `279` member として自動プロビジョニング |
| 他ドメイン新規 Apple Sign-In | 影響なし（Guest Tenant へ） |
| 他ドメイン新規 Google/Email | 影響なし（拒否） |
| 他テナント (`demo-guest` 等) | 影響なし（`allowedDomains` 未設定のため） |

## 事前確認

### 1. 既存メンバーのドメイン把握

**Firebase Console 経由** (簡易):
1. Firebase Console → dev プロジェクト → Firestore → `tenants/279/whitelist`
2. 各ドキュメントの `email` フィールドを一覧
3. `@279279.net` 以外のドメインが含まれていても、whitelist match が allowedDomains より優先されるため影響なし

**admin SDK スクリプト経由** (自動化):
```bash
# dev 側で ADC 認証済であることを確認
gcloud auth application-default login

cat > /tmp/audit-whitelist-domains.mjs <<'EOF'
import admin from "firebase-admin";
admin.initializeApp({ projectId: "carenote-dev-279" });
const db = admin.firestore();
const snap = await db.collection("tenants/279/whitelist").get();
const domains = new Set();
snap.docs.forEach(d => {
  const email = d.data().email || "";
  const domain = email.split("@")[1] || "";
  if (domain) domains.add(domain);
});
console.log([...domains].sort());
process.exit(0);
EOF

node /tmp/audit-whitelist-domains.mjs
```

### 2. Guest Tenant への誤振り分け再発防止確認

`functions/index.js` の `beforeSignIn` で `allowedDomains` match は whitelist match の**後**、Guest Tenant 振り分けの**前**。Phase 0.9 はコード変更を伴わず、Firestore データ更新のみ。

### 3. Phase 0.5 / Phase 1 prod deploy 完了の確認

**Rules deploy 確認** (Firebase Console):
1. Firebase Console → prod プロジェクト → Firestore → Rules タブ
2. 最新の「公開日時」が Phase 0.5 PR #115 マージ後であること
3. Rules 本文が Phase 0.5 版（`isTenantMember()` 関数＋ `migrationLogs` 参照あり）であること

**transferOwnership Function 確認**:
```bash
CLOUDSDK_ACTIVE_CONFIG_NAME=carenote-prod \
  gcloud functions list --v2 --regions=asia-northeast1 \
    --filter='name~transferOwnership' \
    --format='table(name,state)' \
    --project=carenote-prod-279
# → transferOwnership  ACTIVE であること
```

どちらも未完了なら Phase 0.9 へ進まず、先に smoke test → prod deploy を完了させる。

---

## dev 先行検証

### 手順

**Firebase Console 経由** (推奨・最少手数):
1. Firebase Console → dev プロジェクト → Firestore → `tenants/279` ドキュメントを開く
2. 「フィールドを追加」→ フィールド: `allowedDomains`、型: `array`、値: `["279279.net"]`
3. 保存

**admin SDK スクリプト経由** (自動化):
```bash
cat > /tmp/set-allowed-domains-dev.mjs <<'EOF'
import admin from "firebase-admin";
admin.initializeApp({ projectId: "carenote-dev-279" });
const db = admin.firestore();
await db.doc("tenants/279").set(
  { allowedDomains: ["279279.net"] },
  { merge: true }
);
console.log("dev allowedDomains set");
process.exit(0);
EOF

node /tmp/set-allowed-domains-dev.mjs
```

### 動作確認

| ケース | 期待結果 |
|---|---|
| `test-allowed@279279.net` で初回サインイン | tenant `279`, role `member` で成功 |
| `test-denied@other.com` (Google) で初回サインイン | `permission-denied` |
| `test-denied@other.com` (Apple) で初回サインイン | Guest Tenant (`demo-guest`) にフォールバック |
| 既存 whitelist ユーザー（ドメイン一致含む）でサインイン | whitelist の role がそのまま適用 |

### dev 検証結果記録

<!-- 検証実施後、以下を埋める -->
- 実施日時: TBD
- 実施者: TBD
- `test-allowed@279279.net`: ☐ PASS ☐ FAIL
- `test-denied@other.com` (Google): ☐ PASS ☐ FAIL
- `test-denied@other.com` (Apple): ☐ PASS ☐ FAIL
- whitelist 既存ユーザー: ☐ PASS ☐ FAIL

---

## prod 実施（ユーザー明示承認必須）

**CLAUDE.md MUST**: prod 操作前にユーザーから明示的な「実行承認」を取得すること。以下コマンドをエージェントが自動実行するのは禁止。

### 実施タイミング

- 低トラフィック時間帯（推奨: 平日夜間 22:00 以降 / 休日）
- `@279279.net` ユーザーが新規登録する可能性が低い時刻帯

### 実施方法A: Firebase Console (推奨)

1. Firebase Console → **prod** プロジェクト → Firestore → `tenants/279` ドキュメント
2. フィールド `allowedDomains`（型: `array`）を追加、値: `["279279.net"]`
3. 保存

prod 環境であることを URL の project id (`carenote-prod-279`) で必ず確認。

### 実施方法B: REST API + 二重ロック

`gcloud` には document 単位 patch がないため、Firestore REST API 経由で実施する。`CONFIRM_PROD=yes` は運用上の二重ロック（手順書読み飛ばし防止）として使用する。

```bash
test "$CONFIRM_PROD" = "yes" || { echo "CONFIRM_PROD=yes not set"; exit 2; }

CLOUDSDK_ACTIVE_CONFIG_NAME=carenote-prod \
  curl -X PATCH \
    "https://firestore.googleapis.com/v1/projects/carenote-prod-279/databases/(default)/documents/tenants/279?updateMask.fieldPaths=allowedDomains" \
    -H "Authorization: Bearer $(CLOUDSDK_ACTIVE_CONFIG_NAME=carenote-prod gcloud auth print-access-token)" \
    -H "Content-Type: application/json" \
    -d '{"fields":{"allowedDomains":{"arrayValue":{"values":[{"stringValue":"279279.net"}]}}}}'
```

### 実施直後の動作確認

1. `@279279.net` の新規アカウントで Apple / Google サインインを試行し、tenant `279` に振り分けられることを確認
2. 既存ユーザー 1 名に再ログインを依頼し、whitelist で従来通りサインインできることを確認
3. Cloud Logging で `beforeSignIn` 関数の直近 10 件にエラーがないこと

### 実施記録

<!-- prod 実施後に埋める -->
- 実施日時: TBD
- 実施者: TBD
- 承認取得元: TBD
- 確認1 (`@279279.net` 新規): ☐ PASS ☐ FAIL
- 確認2 (既存 whitelist 再ログイン): ☐ PASS ☐ FAIL
- 確認3 (beforeSignIn ログエラーなし): ☐ PASS ☐ FAIL

---

## Rollback 手順

`allowedDomains` を空配列に戻せば即時に Phase 0.5 以前の挙動に戻る（`@279279.net` 新規登録は以後 `permission-denied`、既存メンバーは影響なし）。

### Rollback 方法A: Firebase Console (推奨)

1. Firebase Console → prod → Firestore → `tenants/279`
2. `allowedDomains` フィールドを `[]` に編集、または削除して保存

### Rollback 方法B: REST API

```bash
test "$CONFIRM_PROD" = "yes" || { echo "CONFIRM_PROD=yes not set"; exit 2; }

CLOUDSDK_ACTIVE_CONFIG_NAME=carenote-prod \
  curl -X PATCH \
    "https://firestore.googleapis.com/v1/projects/carenote-prod-279/databases/(default)/documents/tenants/279?updateMask.fieldPaths=allowedDomains" \
    -H "Authorization: Bearer $(CLOUDSDK_ACTIVE_CONFIG_NAME=carenote-prod gcloud auth print-access-token)" \
    -H "Content-Type: application/json" \
    -d '{"fields":{"allowedDomains":{"arrayValue":{"values":[]}}}}'
```

### Rollback の判断基準

| 症状 | Rollback 要否 |
|---|---|
| `@279279.net` ユーザーが誤った tenant に振り分けられる | **即 Rollback** |
| 既存 whitelist ユーザーのサインインが壊れた | **即 Rollback** + 原因調査（`beforeSignIn` のコード問題の可能性） |
| `beforeSignIn` レイテンシ悪化 | 監視継続、致命的なら Rollback |

### Rollback 後の対処

- Guest Tenant に誤って振り分けられたユーザーがいる場合、`transferOwnership` で tenant `279` に移管可能（Phase 1 完了済）
- ただし現状 Guest Tenant → 正規 tenant 間の transferOwnership は ADR-008 の想定範囲外。必要時は手動 Firestore 書換 + Auth custom claim 更新で対応

---

## 関連ドキュメント

- [ADR-007 Guest Tenant 設計](../adr/ADR-007-guest-tenant-for-apple-signin.md)
- [ADR-008 アカウント所有権移行方式](../adr/ADR-008-account-ownership-transfer.md)
- [Phase 1 dev smoke test 手順](./phase-1-transfer-ownership-smoke-test.md)
- PR #115 (Phase 0.5 Firestore Rules)
- PR #119 (Phase 1 transferOwnership)
- Issue #111 (本 RUNBOOK のトリガー)
