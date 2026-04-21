# RUNBOOK: prod deploy 統合 smoke test チェックリスト

**ステータス**: 運用可能
**対象**: Phase 0.5 Rules / Phase 1 transferOwnership / Node 22 runtime の prod deploy 前後の統合動作確認
**関連**: Issue #100, #111, `docs/runbook/phase-0-9-allowed-domains.md`, `docs/runbook/phase-1-admin-id-token.md`
**作成背景**: 2026-04-22 Codex セカンドオピニオン「一括 deploy よりも段階 deploy + 即時 smoke test」方針に基づく軽量チェックリスト

---

## 使い方

本 RUNBOOK は「説明書」ではなく**当日の作業チェックリスト**。以下の判定基準に従い、PASS/FAIL を各欄に記入して実施ログに残す。

| 判定 | 意味 |
|------|------|
| PASS | 全 check 項目が期待結果を満たす |
| FAIL | 1 項目でも不一致 → 即時 rollback 判断 |
| SKIP | 該当機能が未使用（理由を明記） |

---

## 全体の deploy 順序（Codex 推奨）

```
Day 1: Node 22 runtime prod deploy        ← 最優先、期限 2026-04-30
Day 2: Phase 0.5 Rules prod deploy         ← Node 22 安定後
Day 3: Phase 1 transferOwnership deploy    ← Rules 安定後
Day 4-5: Phase 0.9 dev 先行検証
Day 6+: Phase 0.9 prod 実施                 ← 4/30 期限から切離、審査通過後推奨
```

**一括 deploy は禁止**（原因切り分け不能化リスク）。各 deploy 後に本 RUNBOOK の該当セクションを実施してから次の deploy に進む。

---

## 事前準備（全 deploy 共通、Day 0 で完了させる）

- [ ] 本 RUNBOOK を印刷 or 別画面で開く
- [ ] dev build の iOS 実機 or Simulator を起動可能な状態
- [ ] 検証用アカウント準備
  - [ ] 既存 admin: `system@279279.net`（whitelist 登録済）
  - [ ] 検証用 member: 279279.net の別アカウント（whitelist 登録済）
  - [ ] 許可外 Email: `@example.com` 等（permission-denied 期待）
  - [ ] 未登録 Apple ID（demo-guest 振り分け期待）
- [ ] **App Store 審査アカウント影響調査**（§ 審査アカウント確認を先に実施）
- [ ] Cloud Logging タブを `beforeSignIn` / `transferOwnership` / `deleteAccount` でフィルタ準備
- [ ] Firestore Console を該当プロジェクトで開く
- [ ] rollback 手順の参照先を開いておく（各 Phase RUNBOOK）

---

## 審査アカウント確認（Phase 0.9 実施前の最優先事前確認）

**背景**: App Store 審査アカウント `demo-reviewer@carenote.jp` は `carenote.jp` ドメイン（279279.net ではない）。Phase 0.9 allowedDomains 有効化後、whitelist 登録がなければログイン不可になる。Build 35 審査中（2026-04-16 提出）のため、審査 blocker 回避が最重要。

### Step 1: prod whitelist 登録確認

**手段**: Firestore Console（ユーザー手作業）

```
https://console.firebase.google.com/project/carenote-prod-279/firestore/data/~2Ftenants~2F279~2Fwhitelist
```

- [ ] `demo-reviewer@carenote.jp` のエントリが存在する
- [ ] `email` フィールドが `demo-reviewer@carenote.jp`（lowercase / 空白なし）
- [ ] `role` フィールドが存在（通常 `member`）

### Step 2: 未登録の場合の対応（上記 Step 1 で FAIL 時のみ）

Phase 0.9 prod 実施前に whitelist に登録する。

```bash
# 登録例（admin SDK 経由、CONFIRM_PROD 前置き必須）
CONFIRM_PROD=carenote-prod-279 \
  CLOUDSDK_ACTIVE_CONFIG_NAME=carenote-prod \
  node -e '
const admin = require("firebase-admin");
admin.initializeApp({credential: admin.credential.applicationDefault(), projectId: "carenote-prod-279"});
admin.firestore().doc("tenants/279/whitelist/demo-reviewer")
  .set({email: "demo-reviewer@carenote.jp", role: "member"})
  .then(() => { console.log("registered"); process.exit(0); })
  .catch(e => { console.error(e.message); process.exit(1); });'
```

**注意**: 本コマンドは prod 書込のため、実施前にユーザー明示承認必須（CLAUDE.md MUST）。

---

## Day 1: Node 22 runtime prod deploy

### 事前確認

- [ ] dev 3 関数が `nodejs22` ACTIVE: `firebase functions:list --project=carenote-dev-279`
- [ ] 直近 24h の dev Cloud Logging で `beforeSignIn` / `transferOwnership` / `deleteAccount` のエラー急増なし
- [ ] low-traffic 時間帯（JST 平日 22:00 〜 翌 6:00 推奨）

### Smoke test（deploy 前、dev で実施）

- [ ] **iOS 実機 or Simulator（dev build）** で以下を確認
- [ ] Apple Sign-In → `beforeSignIn` が `nodejs22` runtime で起動、`customClaims.tenantId` 取得
  - 確認: Cloud Logging で `beforeSignIn` の container log に `nodejs22` が記録
- [ ] 新規録音作成 → Firestore `recordings` に `createdBy` = 自 uid で保存
- [ ] 自録音の transcription 編集 → 成功
- [ ] RecordingList 表示 → 他人の録音も read 可（従来通り）

### Deploy 実行

```bash
firebase deploy --only functions --project carenote-prod-279
```

**実行前にユーザー明示承認必須**（CLAUDE.md MUST）。

### Deploy 後確認

- [ ] `firebase functions:list --project=carenote-prod-279` で 3 関数すべて `nodejs22` ACTIVE
- [ ] 直後 15 分間 Cloud Logging を監視、エラー急増なし
- [ ] 実機で Apple Sign-In → ログイン成功（cold start でやや遅延は許容）
- [ ] 実機で新規録音作成 → 成功

### PASS 判定

- [ ] 上記全 check PASS → Day 2 へ進む
- [ ] FAIL 時: `git revert <PR #130 commit>` + `firebase deploy --only functions --project carenote-prod-279` で Node 20 に rollback

### 実施ログ記入欄

```
- 実施日時: YYYY-MM-DD HH:MM JST
- 実施者: <GitHub handle>
- 判定: PASS / FAIL
- 異常時対応: （あれば）
```

---

## Day 2: Phase 0.5 Rules prod deploy

### 事前確認

- [ ] Day 1 Node 22 deploy 完了から最低 12h 経過、エラー急増なし
- [ ] 64 rules-unit-tests が PASS: `cd functions && npm test`
- [ ] dev の Rules が PR #115 以降の内容で deploy 済

### Smoke test（deploy 前、dev で実施）

dev 環境で以下を確認:

- [ ] 自作成録音の編集/削除 → 成功
- [ ] 他人作成録音の編集/削除試行 → permission-denied
- [ ] admin が他人録音の削除 → 成功
- [ ] 未認証での recordings read → permission-denied
- [ ] member が migrationLogs read 試行 → permission-denied
- [ ] admin が migrationLogs read → 成功（空コレクション OK）

### Deploy 実行

```bash
firebase deploy --only firestore:rules --project carenote-prod-279
```

**実行前にユーザー明示承認必須**（CLAUDE.md MUST）。

### Deploy 後確認

- [ ] Firebase Console → Firestore → ルール → 最新版が反映
- [ ] 実機で自録音の編集/削除 → 成功
- [ ] 実機で RecordingList 表示 → 従来通り他人の録音も read 可
- [ ] 直後 15 分間 Cloud Logging を監視、`permission-denied` の急増なし（既存ユーザー操作が壊れていないか）

### PASS 判定

- [ ] 上記全 check PASS → Day 3 へ進む → Issue #100 close candidate
- [ ] FAIL 時: Firebase Console → Firestore → ルール → リビジョンから旧版復元

### 実施ログ記入欄

```
- 実施日時: YYYY-MM-DD HH:MM JST
- 実施者: <GitHub handle>
- 判定: PASS / FAIL
- 異常時対応: （あれば）
```

---

## Day 3: Phase 1 transferOwnership prod deploy

### 事前確認

- [ ] Day 2 Rules deploy 完了から最低 12h 経過、エラー急増なし
- [ ] migrationLogs / migrationState の Rules が deploy 済（Day 2 で自動適用）
- [ ] admin 権限ユーザーの uid 把握（caller として使用）
- [ ] `functions/scripts/get-admin-id-token.mjs` + `call-transfer-ownership.mjs` が利用可能

### Smoke test（deploy 前、dev で実施）

- [ ] `docs/runbook/phase-1-admin-id-token.md` § 手順 A（dev 環境）を完走
- [ ] dryRun でテナント内 uid ペアの件数が期待値と一致
- [ ] confirm 後、該当 uid の recordings の createdBy が移行先に書換
- [ ] migrationLogs に caller uid + from-uid + to-uid が記録

### Deploy 実行

```bash
firebase deploy --only functions:transferOwnership --project carenote-prod-279
```

**実行前にユーザー明示承認必須**（CLAUDE.md MUST）。

### Deploy 後確認

- [ ] `firebase functions:list --project=carenote-prod-279` で `transferOwnership` が ACTIVE / nodejs22
- [ ] 直後 10 分間 Cloud Logging を監視、function が呼ばれても想定外のエラーなし
  - 通常 Callable は呼ばれないので、この時点では起動確認のみ
- [ ] 実際の prod transferOwnership 運用は別途ユーザー明示承認の下で `docs/runbook/phase-1-admin-id-token.md` § 手順 B に従う

### PASS 判定

- [ ] 上記全 check PASS → 24h 安定監視開始
- [ ] FAIL 時: `firebase deploy --only functions:transferOwnership --project carenote-prod-279` で前バージョン再 deploy（git revert 経由）

### 実施ログ記入欄

```
- 実施日時: YYYY-MM-DD HH:MM JST
- 実施者: <GitHub handle>
- 判定: PASS / FAIL
- 異常時対応: （あれば）
```

---

## Day 3-4: 24h 安定監視

Day 1-3 の変更を束ねて 24h 観測。

- [ ] Cloud Logging で `beforeSignIn` / `deleteAccount` / `transferOwnership` のエラー率が平常値以下
- [ ] Firestore denied の急増なし
- [ ] Auth errors の急増なし
- [ ] 実機で主要動線（Sign-In / 録音 / transcription 編集）が従来通り動作

### 監視結果記入欄

```
- 監視開始: YYYY-MM-DD HH:MM JST
- 監視終了: YYYY-MM-DD HH:MM JST
- 異常検知: （なし / あれば詳細）
- 次 Phase 進行判定: GO / NO-GO
```

---

## Day 4-5: Phase 0.9 dev 先行検証

`docs/runbook/phase-0-9-allowed-domains.md` § 手順 A を実施。本 RUNBOOK からは省略。

---

## Day 6+: Phase 0.9 prod 実施

**重要**: 4/30 期限から切り離す（Codex セカンドオピニオン）。Node 22 prod deploy の安定確認 + App Store 審査通過後を推奨。

`docs/runbook/phase-0-9-allowed-domains.md` § 手順 B を実施。本 RUNBOOK からは省略。

---

## 失敗時エスカレーション

| 状況 | 対応 |
|------|------|
| Node 22 deploy で実機ログイン不可 | Node 20 に即時 revert。Issue 化して原因調査 |
| Rules deploy で既存ユーザーの操作が軒並み permission-denied | Firebase Console で旧版 Rules 復元。dev 環境で再検証 |
| transferOwnership deploy 後に関数呼出で 500 | `firebase functions:log --only transferOwnership --project=carenote-prod-279` で stacktrace 確認 |
| Phase 0.9 有効化で既存 member がログイン不可 | allowedDomains を空配列に即時 rollback。whitelist 登録漏れを確認 |
| 審査 reject（Build 35 関連） | 即時 revert 要否判断（App Store Connect で状況確認）、問題箇所のみ修正して再提出 |

---

## 関連

- Issue #100（Firestore Rules の recordings 権限過剰）
- Issue #111（Phase 0.9: prod allowedDomains 有効化）
- [ADR-007 Guest Tenant for Apple Sign-In](../adr/ADR-007-guest-tenant-for-apple-signin.md)
- [ADR-008 Account Ownership Transfer](../adr/ADR-008-account-ownership-transfer.md)
- [phase-0-9-allowed-domains.md](./phase-0-9-allowed-domains.md)
- [phase-1-admin-id-token.md](./phase-1-admin-id-token.md)
- `docs/appstore-metadata.md`（審査アカウント情報）
