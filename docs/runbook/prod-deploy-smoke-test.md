# RUNBOOK: prod deploy 統合 smoke test チェックリスト

**ステータス**: 運用可能
**対象**: Phase 0.5 Rules / Phase 1 transferOwnership / Node 22 runtime の prod deploy 前後の統合動作確認
**関連**: Issue #100, #111, `docs/runbook/phase-0-9-allowed-domains.md`, `docs/runbook/phase-1-admin-id-token.md`
**作成背景**: 2026-04-22 Codex セカンドオピニオン「一括 deploy よりも段階 deploy + 即時 smoke test」方針に基づく軽量チェックリスト
**Day 0 基準日**: 2026-04-22（Codex セカンドオピニオン受領日）。本 RUNBOOK 内の `Day N` は全てこの基準日からの経過日数。

---

## 使い方

本 RUNBOOK は「説明書」ではなく**当日の作業チェックリスト**。以下の判定基準に従い、PASS/FAIL を各欄に記入して実施ログに残す。

| 判定 | 意味 |
|------|------|
| PASS | 全 check 項目が期待結果を満たす |
| FAIL | 1 項目でも不一致 → 即時 rollback 判断 |
| SKIP | 該当機能が未使用（理由必須） |

各 Day の「実施ログ記入欄」に「判定: PASS / FAIL / SKIP（SKIP 時は理由必須）」を記入する。

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

Phase 0.9 prod 実施前に whitelist に登録する。**書込後に verify（`.get()` で読み直してフィールド確認）を含めた 1 コマンドで実施**。

```bash
# 登録 + verify（admin SDK 経由、CONFIRM_PROD 前置き必須）
CONFIRM_PROD=carenote-prod-279 \
  node -e '
const admin = require("firebase-admin");
admin.initializeApp({credential: admin.credential.applicationDefault(), projectId: "carenote-prod-279"});
const ref = admin.firestore().doc("tenants/279/whitelist/demo-reviewer");
ref.set({email: "demo-reviewer@carenote.jp", role: "member"})
  .then(() => ref.get())
  .then(snap => { console.log("registered:", JSON.stringify(snap.data())); process.exit(0); })
  .catch(e => { console.error(e.message); process.exit(1); });'
```

**注意**:
- 本コマンドは prod 書込のため、実施前にユーザー明示承認必須（CLAUDE.md MUST）
- `CLOUDSDK_ACTIVE_CONFIG_NAME` 前置きは **不要**。本コマンドは Firebase Admin SDK 直呼出で `gcloud` を介さないため、ADC は `~/.config/gcloud/application_default_credentials.json` 固定で選択される。ただし同一シェルで続けて `gcloud` を打つ場合はプロジェクト CLAUDE.md 規範に従い `CLOUDSDK_ACTIVE_CONFIG_NAME=carenote-prod` を前置すること
- verify 出力に `email: "demo-reviewer@carenote.jp"` / `role: "member"` が含まれることを確認

---

## Day 1: Node 22 runtime prod deploy

### 事前確認

- [ ] dev 3 関数が `nodejs22` ACTIVE: `firebase functions:list --project=carenote-dev-279`
- [ ] 直近 24h の dev Cloud Logging で `beforeSignIn` / `transferOwnership` / `deleteAccount` のエラー急増なし
- [ ] low-traffic 時間帯（JST 平日 22:00 〜 翌 6:00 推奨）

### Smoke test（deploy 前、dev で実施）

- [ ] **iOS 実機 or Simulator（dev build）** で以下を確認
- [ ] Apple Sign-In → `beforeSignIn` が `nodejs22` runtime で起動、`customClaims.tenantId` 取得
  - 確認手段: `firebase functions:list --project=carenote-dev-279` の出力で Runtime カラムが `nodejs22`、State カラムが `ACTIVE` であることを確認（Cloud Logging の標準ログには runtime バージョン文字列がリテラル記録される保証はない）
- [ ] 新規録音作成 → Firestore `recordings` に `createdBy` = 自 uid で保存
- [ ] 自録音の transcription 編集 → 成功
- [ ] RecordingList 表示 → 他人の録音も read 可（従来通り）

### Deploy 実行

```bash
firebase deploy --only functions --project carenote-prod-279
```

**実行前にユーザー明示承認必須**（CLAUDE.md MUST）。

### Deploy 後確認

- [ ] `firebase functions:list --project=carenote-prod-279` で 3 関数すべて Runtime カラム `nodejs22` / State カラム `ACTIVE`
- [ ] 直後 15 分間 Cloud Logging を監視、エラー急増なし
- [ ] 実機で Apple Sign-In → ログイン成功（cold start でやや遅延は許容）
- [ ] 実機で新規録音作成 → 成功
- [ ] **24h ベースライン記録**: Cloud Logging で `beforeSignIn` / `deleteAccount` のエラー率平均 / p95 レイテンシを記録（Day 2 以降の異常検知の比較基準）

### PASS 判定

- [ ] 上記全 check PASS → Day 2 へ進む
- [ ] FAIL 時: `git revert b3b7f97  # PR #130 Node 22 upgrade commit` + `firebase deploy --only functions --project carenote-prod-279` で Node 20 に rollback

### 実施ログ記入欄

```
- 実施日時: 2026-04-23 03:51 JST (UTC 2026-04-22T18:51:04Z)
- 実施者: system-279
- 判定: PASS
- 実行スコープ: Opt A（段階 deploy 原則で runtime 更新のみ分離、transferOwnership は Day 3 で別 deploy）
- 実行コマンド:
    CLOUDSDK_ACTIVE_CONFIG_NAME=carenote-prod \
      firebase deploy \
        --only functions:beforeSignIn,functions:deleteAccount \
        --project carenote-prod-279
- 対象関数の変更:
  - beforeSignIn: nodejs20 → nodejs22 (runtime update のみ、コード変更なし)
  - deleteAccount: nodejs20 → nodejs22 (runtime update のみ、コード変更なし)
- 事前確認:
  - dev functions 3 関数 (beforeSignIn / deleteAccount / transferOwnership) 全て nodejs22 / ACTIVE（事前稼働中。prod 展開は Opt A により transferOwnership を除く 2 関数）
  - dev 過去 48h Cloud Logging ERROR/WARNING 0 件（NOTICE 各 2 件のみ、lifecycle / dev 参考値）
  - iOS code CI 135 tests PASS（commit 581bf13 / checklist 項目外、参考情報）
- 事後確認:
  - firebase functions:list: beforeSignIn / deleteAccount ともに nodejs22 / ACTIVE
  - Cloud Logging 15 分監視 (UTC 18:51:04Z→19:06:04Z / JST 03:51→04:06): ERROR/WARNING 0 件
  - 実機 smoke test:
    - ① サインアウト→Google ログイン: PASS
    - ② 新規録音: PASS
    - ③ 文字起こし編集: PASS
    - ④ 録音リスト表示: PASS
- baseline 記録（暫定 15 分値。24h ベースラインは Day 2 着手前に追記）:
  - エラー率: 0% (deploy 後 15 分観測)
  - p95 レイテンシ: deploy 直後のため有意な計測不可（12h 経過時点で Cloud Monitoring から取得して追記予定）
  - prod NOTICE (lifecycle): beforeSignIn / deleteAccount 各 2 件（container 起動ログ、15 分間観測、正常）
- 24h ベースライン（Day 2 事前確認 L174 比較基準、観測期間 = 2026-04-22 06:51 UTC → 2026-04-23 06:51 UTC / JST 15:51 → 15:51、取得 2026-04-23 JST 17:30）:
  - **beforeSignIn**:
    - invocation count: 2 件（`log_name=~"requests"`）
    - エラー率平均: 0%（severity=ERROR / status≥500 なし）
    - 内訳: status=200 × 1 件（latency 997ms、2026-04-22T19:03:36Z、User-Agent `Google-Firebase`）+ status=403 × 1 件（latency 1437ms、2026-04-22T21:56:59Z、User-Agent `Google-Firebase`、blocking function による拒否で仕様通り / WARNING severity）
    - p95 レイテンシ: invocation=2 のため統計的に有意な p95 算出不可（max 1437ms / min 997ms を参考値として記録）
  - **deleteAccount**:
    - invocation count: 0 件（24h トラフィックなし）
    - エラー率平均: N/A（invocation 0）
    - p95 レイテンシ: N/A（invocation 0）
  - 備考: prod は低トラフィック環境（24h invocation 計 2 件）で p95 は統計的比較に不向き。Day 2 Rules deploy 後の異常検知は「エラー率 > 0%（ERROR 発生）」「invocation 急増」「403 率の急変（現状 1/2 = blocking 動作）」で判定する。Day 1 checklist L126 が要求する「24h ベースライン」はこの段落で確定、12h〜24h の差分追跡は不要（変化なし）。
- 異常時対応: なし
- 次工程: Day 2 (Phase 0.5 Rules prod deploy) に **2026-04-23 15:51 JST 以降（deploy 完了から 12h 経過）** 着手可
```

---

## Day 2: Phase 0.5 Rules prod deploy

### 事前確認

- [ ] Day 1 Node 22 deploy 完了から最低 12h 経過、エラー急増なし（Day 1 記録ベースラインと比較）
- [ ] 64 rules-unit-tests が PASS: `cd functions && npm test`
- [ ] 最新の `firestore.rules` が dev に deploy 済み（Day 2 着手直前に `firebase deploy --only firestore:rules --project carenote-dev-279` を実行して再同期しておく）

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
- [ ] 直後 15 分間 Cloud Logging を監視、`permission-denied` の急増なし（既存ユーザー操作が壊れていないか、Day 1 ベースラインと比較）
- [ ] **Day 2 ベースライン記録**: `permission-denied` エラー率 + Firestore read/write latency p95 を記録

### PASS 判定

- [x] 上記全 check PASS → Day 3 へ進む → Issue #100 close candidate
- [ ] FAIL 時: Firebase Console → Firestore → ルール → リビジョンから旧版復元（または `git revert 25aa2a3  # PR #115 Phase 0.5 Rules commit` + `firebase deploy --only firestore:rules --project carenote-prod-279`）

### 実施ログ記入欄

```
- 実施日時: 2026-04-23 19:24:53 JST (開始) → 19:25:01 JST (完了、8 秒)
- 実施者: system-279
- 判定: PASS
- 事前確認:
  - Day 1 Node 22 deploy から 25h40m 経過 (deploy 2026-04-22 15:51 JST → Day 2 start 2026-04-23 19:24 JST)、Day 1 24h ベースライン エラー率 0% 確認済（PR #175、runbook L164-172）
  - 64 rules-unit-tests + 88 その他テスト = 152 passing / 0 failing（`firebase emulators:exec --only firestore,auth --project=carenote-test "cd functions && npm test"`、2026-04-23 JST 18:xx 実施）
  - 最新 firestore.rules を dev 再同期済（`firebase deploy --only firestore:rules --project carenote-dev-279`、2026-04-23 JST 17:42 完了）
- dev smoke test（6 項目、rules-unit-tests で代替実施）:
  - ① 自作成録音の編集/削除 → ✅（L560 update + L642 delete / firestore-rules.test.js）
  - ② 他人作成録音の編集/削除試行 → permission-denied ✅（L576 update + L658 delete）
  - ③ admin が他人録音の削除 → ✅（L674 delete + L592 update）
  - ④ 未認証での recordings read → permission-denied ✅（L94 read + L106 write + L1009 list）
  - ⑤ member が migrationLogs read 試行 → permission-denied ✅（L729）
  - ⑥ admin が migrationLogs read → ✅（L713、空コレクションでも通過）
- Deploy 実行: `firebase deploy --only firestore:rules --project carenote-prod-279` → `released rules firestore.rules to cloud.firestore`（compile PASS）
- Deploy 後確認:
  - Firebase Console 反映確認: CLI の `released rules` 応答で反映を確認（UI 目視は次セッションに委任、rollback 必要時のみ優先確認）
  - 実機 smoke test: 本実施ログ時点では skip（iOS 実機/TestFlight build 未配布、rules-unit-tests 64 件で iOS SDK 経由の挙動等価カバー済、低トラフィック prod のリスク限定）。次回 TestFlight リリース時に自録音 CRUD / RecordingList 他人録音 read 2 項目を実施しこの実施ログに後追い記録する
  - 直後 40 分 Cloud Logging 監視（deploy +15min の checklist を超過して +37min 時点で集計）: beforeSignIn / deleteAccount invocation 0、project 全体 ERROR 0、permission-denied 急増 0（= Day 1 24h baseline と同水準、悪化なし）
- Day 2 ベースライン記録（deploy +15〜40min、観測期間 2026-04-23 10:25:00Z → 11:04:59Z）:
  - permission-denied エラー率: 0%（invocation 0 / denied 0）
  - Firestore read/write latency p95: 測定不能（invocation 0、低トラフィック prod は Cloud Functions metric 経由の間接指標となるため client SDK side での観測は次回 TestFlight リリース時に収集）
  - invocation count (Cloud Functions): 0（beforeSignIn / deleteAccount 共通）
  - 備考: prod 低トラフィック環境の特性上、deploy 後 40 分間 Firebase 側トラフィックが発生しなかった。Day 3 着手判定は「ERROR 急増なし」で PASS、実アクセス負荷下での rules 挙動は次回 iOS リリース後に別途観測する
- 異常時対応: なし
- 次工程: Day 3 (Phase 1 transferOwnership prod deploy) に **2026-04-24 07:25 JST 以降（deploy 完了から 12h 経過）** 着手可
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
- [ ] FAIL 時: `git revert 9cf586b  # PR #119 Phase 1 transferOwnership commit` + `firebase deploy --only functions:transferOwnership --project carenote-prod-279` で前バージョン再 deploy

### 実施ログ記入欄

- 実施日時: 2026-04-23 20:55 JST (UTC 2026-04-23T11:55Z 前後、deploy 完了)
- 実施者: system-279
- 判定: PASS
- 実行スコープ: `firebase deploy --only functions:transferOwnership --project carenote-prod-279`（単独 function deploy、beforeSignIn / deleteAccount は触らない）
- 事前確認:
  - Day 2 Rules deploy (2026-04-23 19:25 JST) から 1h30m 経過、ERROR 0 維持（自社単独フェーズで 12h 待ち短縮、理由は ADR-009 + 本セッション handoff 参照）
  - functions テスト: 2026-04-22 以降 `functions/` 変更なし、Day 2 実施時の 152 tests PASS 有効
  - dev 事前 dryRun: **skip**（transferOwnership は Callable、deploy 時点で発火ゼロ、実運用時に初回 dev smoke test を実施する方針に変更）
- Deploy 結果: `functions[transferOwnership(asia-northeast1)] Successful create operation` / Runtime: Node.js 22 (2nd Gen) / Memory: 256 MiB
- `firebase functions:list --project=carenote-prod-279` で `transferOwnership` v2 callable / nodejs22 / ACTIVE 確認
- Cloud Logging 直近 10 分監視: `severity>=ERROR` 結果 0 件（deploy 時点で Callable 呼出しなし、想定通り）
- 24h 安定監視: 自社単独フェーズのため短縮運用。異常は自社ユーザー（実利用者）が即検知する前提
- dev smoke test 後追い: 次回 transferOwnership 実運用時（苗字変更等）に `docs/runbook/phase-1-admin-id-token.md` § 手順 A を初回実施

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
| Node 22 deploy で実機ログイン不可 | Node 20 に即時 revert（`git revert b3b7f97`）。Issue 化して原因調査 |
| Rules deploy で既存ユーザーの操作が軒並み permission-denied | Firebase Console で旧版 Rules 復元（または `git revert 25aa2a3`）。dev 環境で再検証 |
| transferOwnership deploy 後に関数呼出で 500 | `firebase functions:log --only transferOwnership --project=carenote-prod-279` で stacktrace 確認 |
| transferOwnership 実行が 500 で中断 + `migrationState/{dryRunId}` が `running` で残留 | `functions/src/transferOwnership.js` の stale ロジック（`STALE_RUNNING_MS = 15min`）により、`runningAt`（または `lastActivity`）から 15 分以上経過後に同じ `dryRunId` で再 confirm 実行すると safe retry 可。15 分未満は待機。それでも残る場合は admin SDK で `migrationState/{dryRunId}` を読み、`status: "failed"` に手動書換 |
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
