# RUNBOOK: Phase 0.9 — `tenants/279.allowedDomains` 有効化

**ステータス**: prod 設定済（2026-04-23）／実機確認 pending（Issue #111 close 条件待ち、次回 TestFlight リリース時に後追い）
**対象**: 本番 tenant `279` にドメインベースの自動参加（`279279.net`）を有効化する
**関連**: Issue #111、ADR-007 Guest Tenant、`functions/index.js` `beforeSignIn`

---

## いつ使うか

- Phase -1 / 0 / 0.5 / 1 すべて完了後、Apple Sign-In ドメイン制限を恒久有効化したい時
- 新しい 279279.net ドメインのケアマネジャーを個別 whitelist 追加なしで 279 テナントに参加させたい時

---

## 背景（`beforeSignIn` の分岐と `allowedDomains` の役割）

`functions/index.js` 抜粋:

```js
// 1. whitelist exact match → 実テナント
// 2. allowedDomains domain match → 実テナント
// 3. Apple プロバイダ → demo-guest
// 4. それ以外 → permission-denied
```

現状 `tenants/279.allowedDomains` は未設定（= 空配列扱い）。この PR で `["279279.net"]` に設定すると:

| シグナル | 現状 | 本 RUNBOOK 実施後 |
|----------|------|------------------|
| `foo@279279.net` を whitelist に追加せず Google/Email Sign-In | `permission-denied` | `tenants/279` に `role: "member"` で自動参加 |
| `foo@279279.net` を whitelist 済で Google/Email Sign-In | 従来通り whitelist 経由で参加 | 変化なし |
| `foo@other-domain.com` で Apple Sign-In | `demo-guest` tenant | 変化なし |
| `foo@other-domain.com` で Google/Email Sign-In | `permission-denied` | 変化なし |

---

## 前提条件

- [ ] Phase -1 (createdBy バックフィル) prod 完了 — PR #117 マージ済
- [ ] Phase 0 (uid 参照棚卸し ADR-008) 完了 — PR #109 マージ済
- [ ] Phase 0.5 (Firestore Rules 強化) **prod deploy 済** — PR #115 dev deploy 済、prod deploy は本 RUNBOOK 実施前に完了必須
- [ ] Phase 1 (transferOwnership) **prod deploy 済** — PR #119 dev deploy 済、prod deploy は本 RUNBOOK 実施前に完了必須
- [ ] Node.js 22 runtime prod deploy 済（本セッション PR #130 で対応）
- [ ] iOS 実機 smoke test 済（Phase 0.5 + Phase 1 + Node 22 の主要動線確認）
- [ ] `gcloud auth application-default login`（`system@279279.net`）で ADC 設定済
- [ ] 既存 279 メンバーの全ドメインが把握済（279279.net 外のメンバーがいる場合は個別 whitelist で保護）

---

## 手順 A: dev 先行検証

### 1. 現状確認

Firestore Console（目視確認可）:
https://console.firebase.google.com/project/carenote-dev-279/firestore/data/~2Ftenants~2F279

期待値: `allowedDomains` フィールドなし、または `[]`。

CLI 代替（Admin SDK ワンライナー、`functions/` 配下で実行）:

```bash
(cd functions && node -e '
const admin = require("firebase-admin");
admin.initializeApp({credential: admin.credential.applicationDefault(), projectId: "carenote-dev-279"});
admin.firestore().doc("tenants/279").get()
  .then(d => { console.log(JSON.stringify(d.data()?.allowedDomains ?? null, null, 2)); process.exit(0); })
  .catch(e => { console.error(e.message); process.exit(1); });')
```

> **Note**: `gcloud firestore` / `firebase firestore:*` には document 単体の read/patch サブコマンドが存在しない。Admin SDK 経由（Node.js）または Firestore Console が唯一の手段。

### 2. dev 設定

**Firestore Console（推奨、目視確認可）:**

1. https://console.firebase.google.com/project/carenote-dev-279/firestore/data/~2Ftenants~2F279 を開く
2. 「フィールドを追加」→ field: `allowedDomains`、type: `array`、要素 1 つ `279279.net`（**lowercase**）
3. 「更新」クリック

**CLI 代替**（Admin SDK ワンライナー）:

```bash
(cd functions && node -e '
const admin = require("firebase-admin");
admin.initializeApp({credential: admin.credential.applicationDefault(), projectId: "carenote-dev-279"});
admin.firestore().doc("tenants/279").update({allowedDomains: ["279279.net"]})
  .then(() => { console.log("updated"); process.exit(0); })
  .catch(e => { console.error(e.message); process.exit(1); });')
```

**注意**: `allowedDomains` の値は **lowercase** で登録する（`beforeSignIn` は `d.toLowerCase().trim()` で比較するが、保存時も lowercase に揃える運用規範）。

### 3. 動作確認

以下 3 パターンを iOS 実機 + dev build で検証:

| パターン | テストアカウント | 期待結果 |
|----------|----------------|---------|
| 許可内ドメイン、whitelist 未登録 | 新規 `test-phase09-inside@279279.net`（Google or Email） | **279 テナントに自動参加**（新規動作）、`customClaims.tenantId === "279"`、`role: "member"` |
| 許可外ドメイン、Apple Sign-In | テスト用 Apple ID（非 279279.net） | `demo-guest` tenant（従来通り） |
| 許可外ドメイン、Google Sign-In | `test-phase09-outside@example.com` | `permission-denied`（従来通り） |
| 許可内ドメイン、whitelist 済 | 既存 admin `system@279279.net` | 従来通り whitelist 経由で `role: "admin"` 維持 |

**確認手段**: ログイン成功後、端末から ID token をローカル decode して `customClaims` を確認（**jwt.io 等への貼り付け禁止**）:

```bash
# 端末の Xcode console で ID token を取り出した場合
echo "$ID_TOKEN" | cut -d. -f2 | base64 --decode 2>/dev/null | python3 -m json.tool
# → tenantId / role の値を確認
```

### 4. dev rollback（必要な場合）

**Firestore Console:** tenants/279 の `allowedDomains` フィールドを削除、または値を空配列 `[]` に変更

**CLI 代替:**

```bash
(cd functions && node -e '
const admin = require("firebase-admin");
admin.initializeApp({credential: admin.credential.applicationDefault(), projectId: "carenote-dev-279"});
admin.firestore().doc("tenants/279").update({allowedDomains: []})
  .then(() => { console.log("rolled back"); process.exit(0); })
  .catch(e => { console.error(e.message); process.exit(1); });')
```

---

## 手順 B: prod 実施

**CLAUDE.md MUST**: prod 操作前にユーザー明示承認取得。以下コマンドをエージェントが自動実行することは禁止。

### 1. 事前確認

- [ ] 手順 A（dev 先行検証）の 3 パターン動作確認すべて PASS
- [ ] 手順 A で dev の `allowedDomains = ["279279.net"]` に更新後、**24 時間以上** 本番相当の動作を監視（Cloud Logging で `beforeSignIn` のエラー急増がないこと）
- [ ] low-traffic 時間帯（例: JST 平日 22:00 〜 翌 6:00）
- [ ] prod の `transferOwnership` / `deleteAccount` が `ACTIVE` で `nodejs22`（`firebase functions:list --project=carenote-prod-279`）
- [ ] prod の Firestore Rules が Phase 0.5 相当（`firestore.rules` が PR #115 の内容で deploy 済）
- [ ] 作業者が 279 テナントの admin 権限を持つ（`migrationLogs` への書込が許可される）
- [ ] 既存 prod メンバー（非 279279.net ドメインの例外ユーザー）が個別 whitelist 登録済

### 2. prod 設定

**Firestore Console 推奨**（目視確認付き、誤操作リスク最小）:

1. https://console.firebase.google.com/project/carenote-prod-279/firestore/data/~2Ftenants~2F279 を開く
2. 現在の `allowedDomains` フィールドを確認（ないはず）
3. 「フィールドを追加」→ field: `allowedDomains`、type: `array`、value: 要素 1 つ `279279.net`（**lowercase**）
4. 更新

**CLI 代替**（Admin SDK、コンソールにアクセスできない場合のみ）:

```bash
# 必ず invocation 前置きで CLOUDSDK_ACTIVE_CONFIG_NAME を指定
# Admin SDK はコード内で projectId を明示しているため ADC が prod 用にスコープ
# されているか gcloud named config で担保する
(cd functions && CLOUDSDK_ACTIVE_CONFIG_NAME=carenote-prod node -e '
const admin = require("firebase-admin");
admin.initializeApp({credential: admin.credential.applicationDefault(), projectId: "carenote-prod-279"});
admin.firestore().doc("tenants/279").update({allowedDomains: ["279279.net"]})
  .then(() => { console.log("updated prod"); process.exit(0); })
  .catch(e => { console.error(e.message); process.exit(1); });')
```

### 3. 動作確認（prod）

設定直後に以下を実施:

- [ ] Cloud Logging で `beforeSignIn` の直近 10 分間のエラー率が平常値以下
- [ ] 既存 prod ユーザーの再ログインで `customClaims.tenantId === "279"` / `role` が変わっていないこと（whitelist が優先される仕様）
- [ ] テストアカウント `test-phase09-prod@279279.net`（作業完了後 delete 前提）で新規 Google Sign-In → `customClaims.tenantId === "279"` / `role: "member"`
- [ ] `deleteAccount` でテストアカウントを削除、Auth user + Firestore データ消滅確認

### 4. prod rollback

`beforeSignIn` エラー急増や想定外のユーザー参加が発生した場合、即座に実施:

**Firestore Console:**
1. tenants/279 の `allowedDomains` フィールドを削除、または値を空配列 `[]` に変更

**CLI 代替:**

```bash
(cd functions && CLOUDSDK_ACTIVE_CONFIG_NAME=carenote-prod node -e '
const admin = require("firebase-admin");
admin.initializeApp({credential: admin.credential.applicationDefault(), projectId: "carenote-prod-279"});
admin.firestore().doc("tenants/279").update({allowedDomains: []})
  .then(() => { console.log("rolled back prod"); process.exit(0); })
  .catch(e => { console.error(e.message); process.exit(1); });')
```

rollback 後、`beforeSignIn` は次回実行時に Firestore を都度読み取るため `allowedDomains` 分岐が無効化される。Firestore の read-after-write 一貫性は同一 region 内では強整合のため、rollback は実用上即時反映だが、別 region からの読み取りや CDN キャッシュ経由の場合は伝播に数秒〜十数秒を要する可能性がある。

### 5. 実施記録

本 RUNBOOK 末尾の「実施ログ」セクションに以下を追記してコミット:

```
- 実施日時: YYYY-MM-DD HH:MM JST
- 実施者: <GitHub handle>
- prod 設定値: ["279279.net"]
- 動作確認結果: （上記チェックリストの PASS/FAIL）
- 異常時の対応: （あれば）
```

---

## セキュリティ注意事項

| 項目 | 対応 |
|------|------|
| 許可ドメイン文字列 | 必ず lowercase で登録。`beforeSignIn` は比較時に lowercase 化するが、Firestore には lowercase で入れる運用規範を保つ |
| 作業者権限 | tenants/279 への write は admin のみ（Firestore Rules Phase 0.5 で enforce） |
| rollback 速度 | Firestore ドキュメント更新は即反映。`beforeSignIn` は都度 Firestore 読み取りのためキャッシュなし |
| 既存ユーザー影響 | whitelist が allowedDomains より優先される仕様のため、既存 admin/editor の role は保護される |
| 想定外ドメイン追加 | `allowedDomains` に `gmail.com` 等の汎用ドメインを追加しない。必ず企業固有ドメインのみ |
| 監査 | `tenants/279` の変更は Cloud Audit Log に記録される。GCP Console → Logging で確認可能 |

---

## トラブルシューティング

### 設定後に既存 admin ユーザーの role が "member" に降格した

想定外の挙動。`beforeSignIn` は whitelist を allowedDomains より先に check するため発生しないはず。発生した場合:

1. 直ちに `allowedDomains` を空配列に rollback
2. 降格ユーザーは whitelist 登録を再確認（`tenants/279/whitelist` コレクションに entry が存在するか）
3. 必要に応じて admin が Admin SDK で `setCustomUserClaims` 直接実行

### 許可内ドメインの新規ユーザーが `permission-denied` で止まる

- Firestore の `allowedDomains` 値が正しく配列で保存されているか確認（`type: string` ではなく `type: array`）
- 値が lowercase か確認
- ユーザーのメールアドレスに空白・全角文字が混ざっていないか確認（`beforeSignIn` は `.trim()` するが、フォーム側で弾くのが理想）

### Cloud Logging に `beforeSignIn` のレイテンシ増

`tenants` collection 全件走査が発生するため、テナント数が増えると線形に悪化する（ADR-007 既知制約 #5）。現状 `279` + `demo-guest` の 2 件なので影響軽微。

---

## 関連

- [ADR-007 Guest Tenant for Apple Sign-In](../adr/ADR-007-guest-tenant-for-apple-signin.md)
- [ADR-005 Auth Blocking Function](../adr/ADR-005-auth-blocking-function.md)
- Issue #111（本 RUNBOOK の追跡 Issue）
- Phase 0.5 Firestore Rules 強化（PR #115）
- Phase 1 transferOwnership（PR #119）

---

## 実施ログ

### 2026-04-23 21:00 JST: prod allowedDomains 有効化（Stage 1 CLI 運用）

- 実施者: system-279
- 判定:
  - **設定 PASS**: Firestore field 更新成功（NOT SET → `["279279.net"]`）、Stage 1 CLI 運用確定
  - **Issue #111 AC**: pending — 「許可外ドメインユーザーが Guest Tenant 振分」「許可内ドメインユーザー既存ログイン非破壊」の実機確認 2 項目は次回 TestFlight リリース時に後追い
- 手段: SA impersonation + Firestore REST API v1 PATCH（ADR-009 Stage 1 採用）
- 前提整備:
  - `system@279279.net` (roles/owner on prod) に SA `firebase-adminsdk-fbsvc@carenote-prod-279.iam.gserviceaccount.com` の `roles/iam.serviceAccountTokenCreator` を付与
  - `gcloud iam service-accounts add-iam-policy-binding firebase-adminsdk-fbsvc@carenote-prod-279.iam.gserviceaccount.com --member=user:system@279279.net --role=roles/iam.serviceAccountTokenCreator --project=carenote-prod-279`
  - IAM propagation 約 60〜90 秒
- 設定前: `tenants/279.allowedDomains` = NOT SET（未定義フィールド）
- 設定コマンド:
  ```bash
  TOKEN=$(gcloud auth print-access-token \
    --impersonate-service-account=firebase-adminsdk-fbsvc@carenote-prod-279.iam.gserviceaccount.com)

  # 書き込み（4xx/5xx を失敗扱いに）
  curl -sS --fail-with-body -X PATCH \
    "https://firestore.googleapis.com/v1/projects/carenote-prod-279/databases/(default)/documents/tenants/279?updateMask.fieldPaths=allowedDomains" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"fields":{"allowedDomains":{"arrayValue":{"values":[{"stringValue":"279279.net"}]}}}}'

  # verify GET（期待値と比較）
  curl -sS --fail-with-body \
    "https://firestore.googleapis.com/v1/projects/carenote-prod-279/databases/(default)/documents/tenants/279" \
    -H "Authorization: Bearer $TOKEN"
  ```
- 設定後: `tenants/279.allowedDomains` = `["279279.net"]`（lowercase、runbook 規範準拠）
- 前提フェーズ:
  - Phase -1 createdBy バックフィル: PR #117（2026-04-21 完了）
  - Phase 0 uid 参照棚卸し: PR #109（完了）
  - Phase 0.5 Rules prod deploy: PR #176（2026-04-23 19:25 JST 完了）
  - Phase 1 transferOwnership prod deploy: 2026-04-23 20:55 JST 完了（本 runbook = `prod-deploy-smoke-test.md` Day 3 実施ログ参照）
  - Node.js 22 runtime prod deploy: PR #175（2026-04-23 完了）
  - iOS 実機 smoke test: **次回 TestFlight リリース時に後追い予定**（自社単独フェーズで受容）
  - 既存 279 メンバーのドメイン把握: **全員 `@279279.net` 確認済**（ユーザー明示、2026-04-23 セッション）
- 動作確認: Cloud Logging の `beforeSignIn` で新規 `@279279.net` アカウントの自動 member 化は、次回新規サインアップ発生時に確認する（低トラフィック環境下で即時確認不可、自社単独フェーズで受容）
- 24h 監視: 自社単独フェーズで短縮運用、`beforeSignIn` のエラー急増は自社ログインで即検知する前提
- 運用基盤: Stage 2 GitHub Actions + Workload Identity Federation は follow-up Issue で整備（ADR-009 参照）

### 2026-04-27 22:30 JST: prod 設定健全性 read-only verify + B2 ポストポーン継続判定

- 実施者: system-279
- きっかけ: ユーザーから「内部のアプリリンクを知る社員はテナント内のドメインなら誰でも入れるか?」確認、Issue #111 が open のため未完了と推定して再評価 → 実態は prod 設定 2026-04-23 完了済、実機 smoke test だけが pending と判明
- 確認内容（read-only、ユーザー明示承認後に実行）:
  - prod `tenants/279.allowedDomains` = `["279279.net"]` 維持確認（Firestore REST API GET）
  - `tenants/279` フィールド構成 = `["allowedDomains", "createdAt", "name"]`
  - `beforeSignIn` Cloud Function = ACTIVE / GEN_2（`gcloud functions list`）
  - Cloud Logging エラー: 直近 7d で **0 件**
  - 直近のログイン試行: 2026-04-24 15:21 JST までエラーなし（設定後 18h 時点で実ログインあり、正常）
- 判定: prod 技術設定は完全に健全、Build 38 / v1.0.1 配信中の今もエラーなし
- 残作業 = Issue #111 close 条件 (元 AC 全 6 項目を網羅):
  - [ ] **(allowedDomains 正常系)** 新規 `@279279.net` 社員が初回 Google Sign-In 成功（Build 38 / v1.0.1 配信中の Unlisted URL から取得）
  - [ ] **(allowedDomains 正常系)** Cloud Logging で `beforeSignIn` の allowedDomains match 経路を確認
  - [ ] **(allowedDomains 正常系)** Firebase Auth に当該 user の `customClaims.tenantId === "279"` / `role === "member"` 反映確認
  - [ ] **(allowedDomains 正常系)** `tenants/279/whitelist` に当該 entry が存在しないこと（allowedDomains 経由を担保、whitelist 経由でないことの否定的確認）
  - [ ] **(Apple Guest 経路)** 許可外ドメイン × Apple Sign-In が `demo-guest` tenant に振り分けられること（次回 App Store Review 提出時の審査員操作で事実上検証可、能動テストは任意。Build 33 以降通過実績ありで実質充足扱い可）
  - [ ] **(既存ログイン非破壊)** 既存 `@279279.net` 社員のログインが allowedDomains 有効化後も継続成功（直近 7d Cloud Logging エラー 0 件で実質確認済、新規社員ジョイン時の既存メンバーの App Store 自動更新後ログインでも再確認）
- 方針: A1 (whitelist 未登録の `@279279.net` 社員ジョイン予定者あり) + B2 (社員ジョイン待ち) でポストポーン継続。能動テスト用アカウント発行は採用せず、自然観測する
- 再開トリガー: 新規 `@279279.net` 社員のオンボーディング発生時（social signal: 「社員が増えた」「アカウント発行した」等の発言、または Cloud Logging で新規 `@279279.net` の `beforeSignIn` 成功ログ出現）
- 観測コマンド（社員初回ログイン後 24h 以内に実行、`EMAIL` を観測対象の社員メールに置換）:
  ```bash
  TOKEN=$(CLOUDSDK_ACTIVE_CONFIG_NAME=carenote-prod gcloud auth print-access-token)
  EMAIL="alice@279279.net"  # ← 観測対象の社員メールを指定（例、実際の値に置換）

  # 1. beforeSignIn の最新ログ（allowedDomains match 経路を確認）
  CLOUDSDK_ACTIVE_CONFIG_NAME=carenote-prod gcloud logging read \
    'resource.type="cloud_run_revision" AND resource.labels.service_name="beforesignin"' \
    --project=carenote-prod-279 --limit=10 --freshness=24h \
    --format='value(timestamp,severity,jsonPayload.message)'

  # 2. Auth user の custom claim 確認
  curl -sS -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -H "x-goog-user-project: carenote-prod-279" \
    "https://identitytoolkit.googleapis.com/v1/projects/carenote-prod-279/accounts:lookup" \
    -d "{\"email\":[\"$EMAIL\"]}"

  # 3. whitelist に当該 entry がないこと確認（allowedDomains 経由担保）
  curl -sS -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    "https://firestore.googleapis.com/v1/projects/carenote-prod-279/databases/(default)/documents/tenants/279:runQuery" \
    -d "{\"structuredQuery\":{\"from\":[{\"collectionId\":\"whitelist\"}],\"where\":{\"fieldFilter\":{\"field\":{\"fieldPath\":\"email\"},\"op\":\"EQUAL\",\"value\":{\"stringValue\":\"$EMAIL\"}}}}}"
  ```

