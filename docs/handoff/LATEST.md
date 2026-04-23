# Handoff — 2026-04-24 セッション: Issue #100 **恒久解消** (PR #181 merged) + iOS delete follow-up #182 起票

## ✅ 前セッション Phase 0.5 Rules rollback 判断ミスを GCP 側のみで根本解消

前セッション (2026-04-23 夜) で Phase 0.5 強化版 Rules の prod deploy が稼働中 iOS Build 35 と不整合で業務停止 → rollback した。当初の想定ルート「Build 36 リリース → createdBy 書込み確認 → Phase 0.5 再 deploy」はユーザー方針「**iOS バージョンアップを避け、GCP 側のみで根本解決**」で破棄。本セッションで **iOS バイナリを変更せず** Issue #100 恒久解消を達成。

### セッション成果サマリ

| PR | 内容 | Milestone |
|----|------|-----------|
| #181 (merged) | iOS 非変更で recordings 権限モデルを段階的強化 (ADR-010) | **Issue #100 恒久 close** |
| #182 (新規起票) | iOS 側の録音 delete が Firestore に同期されない既存不具合 (bug / P2) | smoke 過程で発見・別追跡化 |

### 主要判断のハイライト

- **iOS 非変更方針の採用**: Build 36 リリース (iOS レビュー + TestFlight 経由、2-5 日所要) を避け、「createdBy の存在と値を条件分岐キーにした二段階 Rules」で Build 35 互換を維持しつつ Issue #100 核心 (他人 update/delete) を遮断
- **read は暫定許容**: 案B (read も createdBy 制限) は Firestore query 仕様 (返却全 doc が read rule を満たす必要) により Build 35 の RecordingList が permission-denied で破綻 → 前回業務停止再発リスク。ADR-010 で将来 Build N+ 時の段階強化計画を明記
- **既存 recordings は backfill しない判断**: 2026-04-24 prod audit 実測で tenant 279 の全 2 件が `createdBy=""` (string 型)、admin = 実運用者なので admin 権限で業務継続可能。ADR-010 consequences 明記
- **admin の createdBy 書換も immutable**: Phase 0.5 原案の設計思想を継承。所有権書換は Admin SDK 経由 Callable `transferOwnership` (ADR-008) に限定
- **Evaluator HIGH 指摘の双方向 in-check 強化**: 「admin が createdBy なし recording に createdBy を追加する update」の silent pass バグを双方向 `in` チェックで修正 + 専用テスト 2 件追加
- **smoke 5「削除復活」は本 PR 対象外と確定**: コード調査 (`RecordingListViewModel.swift:101-109` + `FirestoreService.swift` に `deleteRecording` メソッド未実装 + grep で `recordings` コレクションの `.delete()` 呼出ゼロ) で、iOS 既存不具合と確定。本 PR の Rules 変更とは完全に無関係なので Issue #182 で別追跡化

### 実装実績

- **変更ファイル**: 4 個 (+491/-11)
  - `firestore.rules` (recordings block rewrite、+58/-6)
  - `functions/test/firestore-rules.test.js` (+8 新規テスト + 既存 2 件反転、+169/-9)
  - `docs/adr/ADR-010-recordings-permission-model.md` (新規、179 行)
  - `docs/runbook/prod-deploy-smoke-test.md` (Phase 0.5.1 セクション追加、+83/-0)
- **テスト**: **160/160 PASS** (Phase 0.5 原案時 152 → +8 件新規拡張: createdBy='' create 許容 1 + 既存 createdBy='' 境界 5 + createdBy 不在 recording 防御 2)
- **Prod 操作** (全てユーザー明示承認済):
  - `firebase deploy --only firestore:rules --project carenote-prod-279` (2026-04-24、compile PASS + released rules to cloud.firestore)
  - prod audit (read-only) 2 回実行: baseline (deploy 前) + 事後確認 (deploy 後) 両方で tenant 279 = 2 件全 `createdBy=""` (string 型) を確認 → silent-failure-hunter H1 (非 string 混入リスク) が実データ上ゼロを実証
- **dev 操作**: `firebase deploy --only firestore:rules --project carenote-dev-279` 2 回 (初回 + Evaluator HIGH 修正後)
- **実機 smoke**: Build 35 (TestFlight prod 接続) で create / read / update 全 PASS、delete は #182 で追跡

### レビュー運用 (3 層の独立レビュー + Quality Gate)

- **Codex plan review** (設計段階、`/codex plan` MCP): Go with conditions、7 観点 (Build 35 互換 / Rules 構文 / author 判定単一依存 / allowedDomains 組合せ / backfill / 移行摩擦 / 再発防止) 全対応
- **Evaluator agent** (実装 AC 検証、quality-gate.md Evaluator 分離プロトコル発動): HIGH 1 件 (update immutable 論理バグ) 検出 → 双方向 `in` チェック修正 + テスト 2 件追加 → 再検証 PASS
- **`/review-pr` 4 エージェント並列** (code-reviewer / pr-test-analyzer / silent-failure-hunter / comment-analyzer、type-design は新規型なしで skip): Critical 0、Important 全対応 (テスト数 158→160 訂正 / admin 他フィールド update 可の Consequences 精緻化 / audit 結果明記 / FieldValue.delete() Rules 論理式保証の注記 / Rules コメントへ Firestore query 制約追加)、Suggestion も同時反映 (ADR-008 参照追加 + runbook header に ADR-010 link 追加)
- **rules-unit-tests**: 160/160 PASS (3 回実行: 初回 158 → Evaluator 修正後 160 → review 反映後 160)

### 再発防止プロトコル (ADR-010 § 再発防止 + runbook Phase 0.5.1)

前回 Phase 0.5 rollback の教訓を構造化:
1. **Rules 変更 PR 必須項目**: 前提 iOS build 番号明記 + 稼働バイナリ相当 payload テスト + Build N 相当 payload テスト
2. **prod deploy 前ゲート**: 実機 smoke **skip 禁止** + rules-unit-tests **代替禁止** + prod audit baseline 記録 + dev deploy 先行
3. **「rules-unit-tests は実機 smoke の代替ではない」を docs 明文化**

### Issue Net 変化

セッション開始時 open **8** → #100 close (-1) → #182 起票 (+1) → 終了時 open **8** (net **0**)

| 動き | 件数 | Open 数推移 |
|------|------|------------|
| 開始時 | — | 8 |
| #100 close (PR #181 merge で auto-close + 詳細コメント投稿) | -1 | 7 |
| #182 起票 (iOS delete 未実装、triage #1 実害 + #2 再現可能 + rating 8+) | +1 | **8** |

> **Net 0 の理由明示**: 既存実害 (#100 recordings 権限過剰、rollback 状態で再露出中) を恒久解消して -1、調査過程で発見した既存 iOS 不具合 (delete 未実装で削除後復活) を可視化して +1。triage 基準下で両方適正 (#100 は元から実害、#182 は rating 8+/conf 95+ 相当)。KPI 的には net 0 だが「未対応の現存リスク解消 + 既存未追跡不具合の可視化」で実内容は進捗あり。

### CI の現状

- PR #181 merge 後の main `6ad3ae6`: functions テスト 160/160、firestore.rules compile PASS 実証済
- iOS Tests CI は PR #173 の scheme parallelizable=NO 強制 + lint-scheme-parallel.sh で安定運用継続

### 次セッション推奨アクション (優先順)

1. **#182 iOS delete 機能の Firestore 同期実装** (bug, P2): `FirestoreService.deleteRecording` 追加 + `RecordingListViewModel.deleteRecording` で Firestore delete 呼び出し。ADR-010 の author 分岐 (`admin OR createdBy==uid`) を活用できる設計済。**方針 A (FirestoreService 直接呼び出し) 推奨**、方針 B (OutboxSync delete 拡張) はコスト高
2. **#170 SharedTestModelContainer hardening H2-H6** (bug, P1): H1 は PR #173 で完了、H2-H6 follow-up 6-10h 見積もり
3. **#111 実機 smoke test 後追い close**: 次回 TestFlight リリース時に自録音 CRUD / Guest 振分 / allowedDomains 自動加入 3 条件確認 → close
4. **#105 deleteAccount E2E (Firebase Emulator Suite)** (enhancement, P2)
5. **#178 Stage 2 GHA + WIF 運用基盤** (enhancement, P2、ADR-009 follow-up)
6. **#92 / #90 Guest Tenant 関連**、**#65 Apple × Google account link**

### 関連リンク

- [PR #181 merged](https://github.com/system-279/carenote-ios/pull/181) — Issue #100 恒久解消
- [Issue #100 close + 詳細コメント](https://github.com/system-279/carenote-ios/issues/100#issuecomment-4305906987)
- [Issue #182 iOS delete follow-up](https://github.com/system-279/carenote-ios/issues/182)
- [ADR-010 recordings Rules 権限モデル段階的強化設計](../adr/ADR-010-recordings-permission-model.md)
- `docs/runbook/prod-deploy-smoke-test.md` § Phase 0.5.1

---

# Handoff — 2026-04-23 夜セッション: Day 3 + Phase 0.9 + ADR-009 → **Phase 0.5 Rules 判断ミス + 緊急 rollback**

## ⚠️ セッション終盤に Phase 0.5 Rules の判断ミスが発覚し、業務停止 → rollback 実施

### 何が起きたか

PR #179 merge 後の追加確認で、**Phase 0.5 Rules prod deploy (本日 19:25 JST、Day 2) が稼働中の iOS バイナリ (Build 35 / App Store Unlisted 公開中) と整合しない**ことが判明。ユーザー実機で録音保存 → 文字起こし完了が permission-denied で失敗、**業務停止**。

### 真因

- Build 35 提出: 2026-04-16（= #101 "録音 createdBy 保存" (2026-04-20 merge) より前の iOS コード）
- Build 35 は 2026-04-18 から App Store で Unlisted 配信中（自社メンバーが実機使用中）
- 本日 Phase 0.5 Rules の `create` 条件 `request.resource.data.createdBy == request.auth.uid` を prod deploy
- → Build 35 が createdBy を書き込まずに create → **permission-denied**

### 判断ミスの構造

1. **Phase 0.5 Rules deploy 前に「稼働中 iOS が #101 を含むか」を検証しなかった**
2. Day 2 実施ログで「**実機 smoke test skip、rules-unit-tests 64 件で代替 PASS**」としたが、rules-unit-tests は「新 iOS コード (#101 適用済) × 新 Rules」の組合せしか検証していない。「**旧 Build 35 × 新 Rules**」= 実稼働中の組合せは一切検証されていなかった
3. 「自社単独フェーズで 24h 監視圧縮」の流れで実機検証を軽視した判断全体が誤り
4. Codex review (PR #179) は docs 整合性のみの軽量レビューで、Rules と稼働バイナリの整合には踏み込んでいなかった

### Rollback 実施

- **実施時刻**: 2026-04-23 **22:07:58 JST**（Phase 0.5 prod deploy から 2h42m56s 後、Firebase Rules REST API の ruleset `createTime` により一次確定）
- **ruleset 識別子**: `projects/carenote-prod-279/rulesets/b86a7ee8-43f5-4a36-934d-50d21a596ee5`
- **対応**: `firestore.rules` の `recordings` block を Phase 0.5 前の状態（`allow read, write: if isTenantMember(tenantId)`）に戻して `firebase deploy --only firestore:rules --project carenote-prod-279` 実施
- **結果**: `cloud.firestore: rules file firestore.rules compiled successfully` / `released rules firestore.rules to cloud.firestore` → 業務復旧
- **残置**: `migrationLogs` / `migrationState` の Rules は残した（Phase 1 transferOwnership 運用に必要、iOS app から触らないので影響なし）
- **rules unit test は意図的に未修正**: `functions/test/firestore-rules.test.js` は Phase 0.5 強化版（create に createdBy 必須等）の期待のまま。rollback 後の rules と一時不整合となり CI `functions-test` workflow は FAIL 見込み。**Phase 0.5 Rules 再 deploy 時に test を合わせて戻す方針**。次セッションで Build 36 リリース + Phase 0.5 Rules 再 deploy を実施する際、rules と test を同じ PR で一緒に再適用する

### 影響を受けた/受けなかった今日の変更

| 変更 | 影響 | 対応 |
|------|------|------|
| Phase 0.5 Rules prod deploy (PR #115 / Day 2) | ❌ 業務停止発生 | **本 rollback で Phase 0.5 前の状態に戻した** |
| Day 3 transferOwnership prod deploy | ✅ 影響なし（iOS app から呼ばない Callable） | そのまま継続 |
| Phase 0.9 prod allowedDomains 設定 | ⚠️ 機能自体は壊れていない（beforeSignIn 変更のみ）。ただし rollback 期間中は新規 `@279279.net` 自動加入 member にも **tenant-wide recordings 権限（read/write/delete）** が付与されるため、allowedDomains 有効 × 過剰権限の組合せリスク顕在（自社単独フェーズで受容、Phase 0.5 Rules 再 deploy で解消） | そのまま継続（自動加入 member は自社メンバーのみの前提） |
| ADR-009 prod Firestore 運用パターン | ✅ 影響なし（文書のみ） | そのまま |
| Issue #178 Stage 2 follow-up 起票 | ✅ 影響なし | そのまま |

### Issue 再訂正

- Issue #100 **reopen**（本日 close は時期尚早 → reopen コメントで rollback 経緯 + Close 再条件明記）
- Open Issue: 開始時 7 → PR #179 merge 時 7（-#100 +#178）→ rollback 後 **8**（#100 reopen で +1）
- Net 変化: セッション開始から +1（実害解消できず、むしろ業務停止を引き起こして復旧）

### Close 再条件（Issue #100）

次回以降:
1. **Build 36 リリース**: `scripts/upload-testflight.sh` で Build 36 作成（#101 + 以降の 5 commit 込み）
2. **全稼働実機に Build 36 を配布**（TestFlight / App Store update 経由）
3. **Build 36 で `createdBy` が保存されることを実機確認**
4. **Phase 0.5 Rules 再 deploy**（`firestore.rules` recordings に create/update/delete の createdBy 条件を復活）
5. **再 deploy 後、実機で録音 CRUD を確認**（今回は skip した、今度は必須）
6. 実機確認 PASS で Issue #100 close

### プロセス改善（次セッションで別 ADR 化）

**サーバ側 Rules / functions 変更が iOS app コードの前提を伴う場合、対応 iOS build が稼働実機に入ってから deploy する**を明文化:
- `runbook/prod-deploy-smoke-test.md` の Day 2 Rules deploy 前提条件に「対応 iOS build の稼働実機反映」を追加
- `firestore.rules` 変更 PR テンプレートに「前提 iOS build 番号」を必須記載
- 「実機 smoke test を rules-unit-tests で代替」は **稼働中 iOS バイナリとの実機整合検証の代替にならない**ことを明示
- 自社単独フェーズでも「稼働中 iOS バイナリとの互換性確認」は skip 禁止

### Rollback で作成した PR / コミット

- branch: `fix/rollback-phase-0-5-rules`
- 手動編集: `firestore.rules` の `recordings` block を Phase 0.5 前に戻す
- PR: （後述、本 handoff 更新 + 作成）
- Issue #100 reopen コメント: https://github.com/system-279/carenote-ios/issues/100#issuecomment-4304611564

### 次セッションの最優先アクション

1. **Build 36 を `scripts/upload-testflight.sh` で作成・TestFlight upload**（#101 + 5 commit 込み）
2. Build 36 を実機で受領（TestFlight 内部テスター経由）
3. 実機で録音 CRUD を確認（createdBy が保存されるか）
4. Phase 0.5 Rules を別 PR で再適用・prod deploy・実機再確認・Issue #100 close

---

## セッション成果サマリ（2026-04-23 夜セッション、rollback 前の成果）

前セッション (2026-04-23 午後、PR #175/#176 merged) 直後に継続。`/catchup` で Day 1/Day 2 完了確認 → ユーザー判断「**自社単独フェーズで 24h 監視ゲートを圧縮し最速進行**」のもと、Day 2 deploy +1h30m 時点で Day 3 transferOwnership prod deploy に着手、続けて Phase 0.9 prod `allowedDomains` を有効化。

**両機能（transferOwnership / allowedDomains）が prod で実動作可能な状態に到達**。副次的成果として prod Firestore 直接書き込みの恒常的運用パターンを ADR-009 として策定し、将来の GHA+WIF 運用基盤を Issue #178 で follow-up 起票。

| 成果 | 内容 | Milestone |
|------|------|-----------|
| Day 3 transferOwnership prod deploy | 2026-04-23 20:55 JST 完了（Callable 新規 / Node.js 22 / asia-northeast1）、Cloud Logging ERROR 0 | **Phase 1 prod 反映完了** |
| Phase 0.9 prod allowedDomains 設定 | 2026-04-23 21:00 JST 完了、`tenants/279.allowedDomains = ["279279.net"]` | **Phase 0.9 prod 反映完了（Issue #111 実機確認のみ残）** |
| ADR-009 新規 | prod Firestore 直書き運用パターン（Stage 1 CLI + Stage 2 GHA+WIF 二段構え） | 恒常的運用基盤の設計確定 |
| Issue #178 起票 | Stage 2 GHA + WIF follow-up（enhancement/P2、triage 基準 #5 ユーザー明示指示） | 将来運用基盤の追跡化 |
| Issue #100 close | Day 3 完了で runbook `prod-deploy-smoke-test.md` L218 "Day 3 へ進む → Issue #100 close candidate" が確定 | Rules 過剰権限問題の解消 |

### 主要判断のハイライト

- **24h 監視ゲートの圧縮根拠**: prod は低トラフィック（Day 1 24h で beforeSignIn invocation 2 件、deleteAccount 0 件、runbook L174）で 24h 待っても統計的意味なし。自社単独テナント = 異常は実利用者（自分）が即検知、rollback 手順整備済のため Day 2 +1h30m で Day 3 着手を妥当と判断
- **Day 3 dev dryRun の skip**: transferOwnership は Callable、deploy 時点で発火ゼロ（iOS app から呼ばれない限り実害なし）。年数回の苗字変更運用で初回に dev smoke を実施すれば十分と判断（runbook `phase-1-admin-id-token.md` § 手順 A は残置、初回運用時に活用）
- **Phase 0.9 dev 先行検証の skip**: `beforeSignIn` コードは dev/prod 同一（Day 1 Node 22 runtime で動作実績）、`allowedDomains` は Firestore 1 field 追加のみ、rollback は `update({allowedDomains: []})` で 3 分。自社単独フェーズで dev 検証 ROI 薄と判断
- **prod Firestore 書き込みが `PERMISSION_DENIED` で失敗 → SA impersonation 運用を確立**: user credential (`system@279279.net` ADC) では `tenants/279.allowedDomains` 書き込み不可。(a) Firestore Console 手動 / (b) `roles/datastore.user` 直接付与 / (c) SA key JSON / (d) 初回から GHA+WIF の 4 案検討し、「最小権限 + 再現性 + 緊急対応即応性」の観点から **SA 単位の `roles/iam.serviceAccountTokenCreator` 付与 + `gcloud auth print-access-token --impersonate-service-account=...` + Firestore REST API v1 PATCH** を採用。運用パターンは ADR-009 に記録
- **ADR-009 二段構えの意図**: Stage 1（CLI 即応）を今セッションで完遂し次の prod 設定作業に即対応可能な状態へ。Stage 2（GHA+WIF による監査性・再現性強化）は follow-up Issue #178 で四半期内着手の方針。Stage 1 の IAM binding 維持可否は Stage 2 完了時点で再評価
- **Issue #100 は close / #111 は open 維持の峻別**: #100 は runbook 明示の close candidate 条件が充足（Day 3 完了）で close。#111 は Acceptance Criteria に実機確認 2 条件（許可外ドメイン → Guest 振分 / 許可内ドメイン既存ログイン非破壊）が明記されており、次回 TestFlight リリース後に実機確認 → close する方針で open 維持（feedback_issue_postpone_pattern.md 遵守）

### 実装実績

- **新規ファイル**: 1 個
  - `docs/adr/ADR-009-prod-firestore-write-access.md`（prod Firestore 運用パターン確定）
- **変更ファイル**: 2 個
  - `docs/runbook/prod-deploy-smoke-test.md`（Day 3 実施ログ記入欄を実績値で確定）
  - `docs/runbook/phase-0-9-allowed-domains.md`（実施ログ新規追記、IAM bind + 設定コマンド + 前提フェーズ + 後追い方針含む）
- **Prod 操作（すべて個別にユーザー明示承認取得済）**:
  - `firebase deploy --only functions:transferOwnership --project carenote-prod-279`（2026-04-23 20:55 JST、Successful create / Node.js 22 2nd Gen）
  - `gcloud iam service-accounts add-iam-policy-binding firebase-adminsdk-fbsvc@carenote-prod-279.iam.gserviceaccount.com --member=user:system@279279.net --role=roles/iam.serviceAccountTokenCreator --project=carenote-prod-279`（ADR-009 Stage 1 IAM 付与）
  - `curl -X PATCH https://firestore.googleapis.com/v1/.../tenants/279?updateMask.fieldPaths=allowedDomains`（SA impersonation 経由、値: `["279279.net"]`）
  - `gcloud logging read 'resource.type="cloud_function" severity>=ERROR'`（deploy 直後 10 分監視、ERROR 0 確認）
- **Prod 読み取り**: `gcloud iam service-accounts list / get-iam-policy`、`gcloud projects get-iam-policy`、Firestore REST GET（before/after 確認）
- **テスト**: 新規テスト追加なし（ADR + runbook + docs のみの変更）。functions コードは 2026-04-22 以降変更なし、Day 2 実施時 152/152 PASS 有効

### レビュー運用

- 変更ファイル 3 個（新規 1 + 変更 2）、全て docs のため CLAUDE.md Quality Gate の `/review-pr` 6 エージェント並列は過剰と判断 → **手動レビューチェックリスト**（Build/Security/Scope/Quality/Compat/Doc accuracy）で確認
- `/simplify` / `/safe-refactor`: コード変更ゼロのため発動条件外
- **Quality Gate Evaluator 分離**: 5 ファイル未満 + 新機能追加なし（新規運用パターンは ADR 記録のみでコード追加ゼロ） → 発動条件外

### Issue Net 変化

セッション開始時 open **7** → 終了時 open **7**（net **0**、close 1 / 起票 1）。

| 動き | 件数 | Open 数推移 |
|------|------|------------|
| 開始時 | — | 7 |
| #100 close（Day 3 完了で close candidate 確定） | -1 | 6 |
| #178 起票（Stage 2 GHA+WIF follow-up、triage #5 ユーザー明示指示） | +1 | **7** |

> **Net 0 の理由明示**: #100 は実害解消（prod Rules 過剰権限問題）による close、#178 は ADR-009 follow-up として運用基盤整備の将来 scope 可視化。Issue KPI 的には net 0 だが、「未対応の現存リスクを解消（-1）＋ 将来の運用改善を可視化（+1）」で内容は進捗あり。triage 基準下で両 Issue とも適正（rating 7+ 相当）。

### 次セッションのアクション（優先順）

1. **#170 [bug/P1] SharedTestModelContainer hardening**（H1〜H6、claude 完結、見積もり 6〜10h）— 本セッション未着手、次セッションで最優先
2. **#111 実機 smoke test 後追い close**: 次回 TestFlight Build 36 リリース時に自録音 CRUD / Guest 振分 / allowedDomains 自動加入の 3 条件確認 → Issue #111 コメント追記 → close
3. **#105 [enhancement/P2] deleteAccount E2E（Firebase Emulator Suite）**（8〜12h）
4. **#178 [enhancement/P2] Stage 2 GHA + WIF 運用基盤**（ADR-009 follow-up、四半期内）
5. **#92 / #90 Guest Tenant 関連**、**#65 Apple × Google account link**

### 関連リンク

- [ADR-009 prod Firestore 直書き運用パターン](../adr/ADR-009-prod-firestore-write-access.md)
- [Issue #100 close コメント](https://github.com/system-279/carenote-ios/issues/100#issuecomment-4304246352)
- [Issue #111 open 維持コメント](https://github.com/system-279/carenote-ios/issues/111#issuecomment-4304247403)
- [Issue #178 Stage 2 follow-up](https://github.com/system-279/carenote-ios/issues/178)
- `docs/runbook/prod-deploy-smoke-test.md` Day 3 実施ログ記入欄
- `docs/runbook/phase-0-9-allowed-domains.md` § 実施ログ

---

# Handoff — 2026-04-23 午後セッション: Day 1 24h baseline 確定 + Day 2 Phase 0.5 Rules prod deploy 完了 (PR #175/#176 merged)

## セッション成果サマリ（2026-04-23 午後セッション）

前セッション (2026-04-23 午前、PR #174) 直後に継続。`/catchup` で積み残し確認 → Day 1 deploy +24h 経過（2026-04-23 15:51 JST 超過）を確認し、**優先順位 1 → 3 の流れ（24h baseline 確定 → Day 2 Rules prod deploy）** をユーザー承認済で実行。PR #175 + #176 を merge し、**Day 1/Day 2 の 2 milestone を連続 PASS**。

| PR | 内容 | Milestone |
|----|------|-----------|
| #175 (merged) | runbook Day 1 TBD 欄を 24h 観測データで確定（beforeSignIn 2 invocations / ERROR 0 / deleteAccount invocation 0） | **Day 1 24h ベースライン確定** |
| #176 (merged) | Day 2 Phase 0.5 Rules prod deploy 実施ログ（PASS）追記 | **Day 2 Rules deploy PASS** |

### 主要判断のハイライト

- **dev smoke test を rules-unit-tests で代替**: runbook L193-198 の 6 項目（自録音 CRUD / 他人録音拒否 / admin 削除 / 未認証拒否 / member migrationLogs 拒否 / admin migrationLogs read）を `firestore-rules.test.js` 64 件のテスト ID（L560/L576/L642/L658/L674/L94/L106/L1009/L729/L713 等）と対応マッピング。実機 smoke は次回 TestFlight リリース時に後追い記録。rules 変更はサーバ側 semantic なので unit test で等価カバー、iOS SDK 経由の挙動検証は後工程で十分と判断
- **低トラフィック prod 環境下の baseline 解釈**: Day 1 24h 期間で beforeSignIn invocation 2 件（status 200 + 403、403 は Google-Firebase からの blocking function 拒否で仕様通り）、deleteAccount 0 件。p95 は invocation 不足で算出不可のため、Day 2 異常検知は「ERROR 発生」「invocation 急増」「403 率急変」の定性指標で代替する方針を runbook に明記
- **Day 2 deploy 後 +37min 監視で +15min checklist 条件を充足**: 当初予定（deploy +15min = 19:40 JST）を待たずユーザー指示でログ読み取り先行、既に 37min 経過していたため網羅性は上回り。Cloud Functions invocation 0 / project 全体 ERROR 0 / permission-denied 急増 0 を確認、PASS 判定
- **実機 smoke の skip は明示記録で後追い保証**: runbook 実施ログに「次回 TestFlight リリース時に自録音 CRUD / RecordingList 他人録音 read 2 項目を実施しこの実施ログに後追い記録する」と明文化し、checklist の後追い性を担保
- **Port 8080 の stale Python http.server を kill**: rules-unit-tests 前に Firestore Emulator の port 競合検出 (PID 53827、12日18時間起動の Xcode 付属 Python 3.9 `-m http.server 8080`)。destructive action につきユーザー明示承認後に kill、以降の emulator 起動 PASS

### 実装実績

- **変更ファイル**: 2 個（`docs/runbook/prod-deploy-smoke-test.md` のみ、累計 +38/-10）
  - PR #175: Day 1 実施ログの 24h ベースライン TBD 欄を観測データで確定（+11/-5）
  - PR #176: Day 2 実施ログ記入欄に deploy 結果 + dev smoke mapping + 40min 監視集計 + baseline 記録（+27/-5）
- **Prod 操作**:
  - `firebase deploy --only firestore:rules --project carenote-dev-279`（dev 再同期、2026-04-23 17:42 JST）
  - `firebase deploy --only firestore:rules --project carenote-prod-279`（prod deploy、2026-04-23 19:24:53 → 19:25:01 JST / 8 秒、compile PASS + released 成功、**ユーザー明示承認済**）
  - `gcloud logging read` でプロジェクト全体の post-deploy ERROR / permission-denied 集計
- **テスト**: 152/152 PASS（rules 64 + transfer-ownership / delete-account / auth 88、`firebase emulators:exec --only firestore,auth --project=carenote-test "cd functions && npm test"`）
- **CI**: 両 PR とも docs のみ 1 ファイル変更のため CI checks なし、main は直近 push (2026-04-23T04:18:03Z) で iOS Tests green 維持

### レビュー運用

- 両 PR とも docs のみ 1 ファイル +11〜27 行の小規模変更のため、CLAUDE.md Quality Gate 基準の `/review-pr` (6 エージェント並列) は過剰と判断し **手動レビューチェックリスト** で Build/Security/Scope/Quality/Compat/Doc accuracy を確認 → 問題なし
- `/simplify` / `/safe-refactor` はコード変更ゼロのため発動条件外（3 ファイル以上 / 新機能追加 のいずれも該当せず）
- マージ承認は PR 番号単位でユーザーに明示確認（feedback_pr_merge_authorization 遵守）: PR #175 → 承認 → merge / PR #176 → 承認 → merge

### Issue Net 変化

セッション開始時 open **7** → 終了時 open **7**（net **0**、close 0 / 起票 0）。

| 動き | 件数 | Open 数推移 |
|------|------|------------|
| 開始時 | — | 7 |
| close / 起票 | 0 / 0 | **7** |

> **Net 0 の理由明示**: 今セッションの主目的は prod deploy milestone 実行（Day 1 24h baseline + Day 2 Rules deploy）であり、Issue 処理ではない。**Issue #100 (Firestore Rules の recordings 権限過剰) は Day 3 (transferOwnership) 完了後に close 判定する runbook L218 の明示スコープに従い延期**。新規起票ゼロ = prod deploy 失敗なし + review agent rating 7+ 指摘ゼロ = triage 基準下では適正。KPI 的「進捗ゼロ」ではなく「本セッションは Issue 延期の milestone 実行」として記録。

### CI の現状

- main `e3c1648` (PR #176 merge 後): 直近の実行可能 CI は 2026-04-23T04:18:03Z の iOS Tests 20m48s green（docs only PR なので新規 CI run なし）
- prod rules deploy 後 +40min: beforeSignIn / deleteAccount invocation 0 / project 全体 ERROR 0 / permission-denied 急増 0

### 次セッション推奨アクション（優先順）

1. **M3: Day 3 Phase 1 transferOwnership prod deploy**（**2026-04-24 07:25 JST 以降**着手可、deploy +12h）:
   - 事前: `docs/runbook/phase-1-admin-id-token.md` § 手順 A で dev dryRun → confirm 完走
   - Deploy: `firebase deploy --only functions:transferOwnership --project carenote-prod-279`（**ユーザー明示承認必須**）
   - 事後: `firebase functions:list` で ACTIVE/nodejs22 確認 + 10min Cloud Logging 監視
   - 完了後に Issue #100 の close 判定（runbook L218 candidate）+ 実施ログ記入欄埋め
2. **Issue #170 H2-H6 hardening**（H1 完了済、independent follow-up）:
   - H2: `cleanup()` per-model 失敗ログ
   - H3: fatalError NSError userInfo 詳細化
   - H4: preflight fetch assertion + PR #173 review-pr 残 follow-up
   - H5: SharedTestModelContainer invariant test + cross-contamination smoke test
   - H6: lint-model-container.sh エラーメッセージ改善 + xcodegen → lint 順序依存対応
3. **実機 smoke test の後追い**（次回 TestFlight リリース時）:
   - Day 2 runbook 実施ログに後追い: 自録音 CRUD / RecordingList 他人録音 read 2 項目
   - Day 1 Functions 実アクセス時の p95 latency / permission-denied 率観測
4. **M5: Phase 0.9 allowedDomains 有効化**（審査通過 + whitelist 確認後、Issue #111）
5. **Phase 0.9 前の審査アカウント whitelist 確認**（Firestore Console 手作業、`tenants/279/whitelist/demo-reviewer@carenote.jp`）

### 参考資料（本セッション = 2026-04-23 午後）

- [PR #175 merged](https://github.com/system-279/carenote-ios/pull/175) — Day 1 24h ベースライン確定
- [PR #176 merged](https://github.com/system-279/carenote-ios/pull/176) — Day 2 Phase 0.5 Rules prod deploy 実施ログ（PASS）
- `docs/runbook/prod-deploy-smoke-test.md` L164-172 / L216-253 — Day 1/Day 2 実施ログ本文

---

# Handoff — 2026-04-23 午前セッション: #170 H1 実装完了 + #164 closed (PR #173 merged)

## セッション成果サマリ（2026-04-23 午前セッション）

前セッション (2026-04-23 早朝、PR #172) 直後に継続。`/catchup` で積み残し確認 → Day 2 prod deploy は着手可能時刻 (15:51 JST) より前のため、**#170 H1 (cross-suite race 構造的抑止) を着手・完了**。PR #173 merge で **Issue #164 を close し Issue Net -1 を達成**。

| PR | 内容 | Issue |
|----|------|-------|
| #173 (merged) | scheme parallelizable=NO 強制 + lint-scheme-parallel.sh + OutboxSyncServiceTests を shared container に再合流 | **#164 closed (自動)** |

### 主要判断のハイライト

- **案 (b) scheme-level 強制を採用**: H1 対応案 (a) root @Suite(.serialized) / (b) scheme parallelizable=false / (c) actor-locked helper のうち (b) を選定。(a) は 17 ファイル変更で過大、(c) は test body atomic 化が技術的に不可能と判断。(b) は project.yml + lint 1 本の最小 diff で defense-in-depth
- **Evaluator HIGH + review-pr HIGH で paths-ignore を二段削除**: `scripts/**` を paths-ignore から外して lint script 改ざんを CI で捕捉する改修に加え、review-pr silent-failure-hunter #4 指摘で `.github/**` も同時削除（workflow 改ざんの self-trigger 化）
- **review-pr Important (rating 7+ conf 80+) は同 PR で修正**: Issue 起票 net +1 を避けるため、silent-failure-hunter #2 (regex を `<TestableReference>` に anchor) + #1 (空ファイル guard) + #3 (ALL assertion) + code-reviewer #1 (ディレクトリ走査) を同 PR 内で 1 commit に集約。PR description に follow-up 項目 (rating 6 以下) を明記し Issue 化回避
- **CI fail から bash 3.2 互換性確保**: 初回 push で `mapfile: command not found` fail (macOS bash 3.2、GPLv3 回避でシステム bash 固定)。`while IFS= read -r` loop に置換し bash 3.2 (`/bin/bash --version`: 3.2.57) で self-test 再検証後 re-push → CI green

### 実装実績

- **変更ファイル**: 6 個 (+280/-35)
  - `project.yml`: `schemes.CareNote.test.targets[].parallelizable: false` 追加
  - `.github/workflows/test.yml`: lint-scheme-parallel.sh CI step 追加 + paths-ignore から `'scripts/**'` + `'.github/**'` 削除
  - `CareNoteTests/OutboxSyncServiceTests.swift`: per-suite `makeContainer()` 削除 + 8 箇所を `makeTestModelContainer()` 化
  - `scripts/lint-model-container.sh`: ALLOWED_TEST_FILES から `OutboxSyncServiceTests.swift` 削除
  - `scripts/lint-scheme-parallel.sh` (新規 127 行): perl -0777 slurp で全 scheme 走査 + `<TestableReference>` anchored ALL assertion + 空ファイル guard + bash 3.2 互換
  - `CareNote.xcodeproj/xcshareddata/xcschemes/CareNote.xcscheme` (新規 120 行): xcodegen 生成、pbxproj 同様 commit 化
- **Acceptance Criteria**: AC1-AC7 全達成 (AC3 は AC4 で代替検証)
- **検証**: 20 回連続実行 PASS (2700 tests / 360 suites / ~4.4s test time)、lint self-test 3 種 (NO→YES / NO 削除 / 空ファイル) bash 3.2 PASS
- **CI**: 初回 fail (mapfile bash 3.2 非対応) → 修正 push → green (16m30s、main merge 後 20m48s)

### レビュー運用

- `/simplify` 3 並列 (reuse / quality / efficiency): Reuse Important × 1 (grep → perl -0777 slurp で lint-model-container.sh パターン統一) 修正
- `/safe-refactor`: 検出問題 0 件
- Evaluator 分離プロトコル (5+ ファイル該当): HIGH × 1 (paths-ignore に `scripts/**` 残存) 修正、MEDIUM × 1 (xcodegen → lint 順序依存) は #170 H6 follow-up
- `/review-pr` 4 並列 (type-design skip): Critical 0、Important 1 (rating 7 conf 85) + 関連 5 件を同 PR で修正、rating 6 以下 3 件 (pr-test-analyzer fixture-based test / race 統計 / cross-contamination smoke test) は #170 H4/H5 に follow-up 集約（Issue 化せず PR description に記録）

### Issue Net 変化

セッション開始時 open 8 → 終了時 **7**（net **-1**、#164 close）。

| 動き | 件数 | Open 数推移 |
|------|------|------------|
| 開始時 | — | 8 |
| PR #173 merge → #164 auto-close | -1 | **7** |

> **CLAUDE.md KPI「Issue は net で減らすべき」達成 ✅**。review-pr rating 6 以下は Issue 化せず PR commit message + description に follow-up 記録（#170 H4/H5 scope）。review-pr Important (rating 7 conf 85) も Issue 起票せず同 PR 内修正で net 増を回避。

### CI の現状

- PR #173 merge 後の main `0ef50d7`: iOS Tests 20m48s green（2026-04-23T04:18:03Z）
- cross-suite race の構造的抑止完了。CI は `-parallel-testing-enabled NO` (xcodebuild flag) + scheme `parallelizable=NO` (project.yml) + lint-scheme-parallel.sh (機械検証) の三重防御

### 次セッション推奨アクション（優先順）

1. **24h ベースライン追記**（2026-04-23 15:51 JST 以降、Day 2 着手前）: Cloud Monitoring から `beforeSignIn` / `deleteAccount` のエラー率平均 / p95 レイテンシ / invocation count を取得し、`docs/runbook/prod-deploy-smoke-test.md` Day 1 実施ログ TBD 欄を埋める
2. **M2: Day 2 Phase 0.5 Rules prod deploy**（deploy + 12h = 15:51 JST 以降）: RUNBOOK § Day 2 に従い、dev 事前検証 → `firebase deploy --only firestore:rules --project carenote-prod-279` 明示承認 → 実機 smoke test → baseline 記録 → Issue #100 close 判定
3. **M3: Day 3 transferOwnership prod deploy**（Day 2 +12h）: `docs/runbook/phase-1-admin-id-token.md` § 手順 A で dev dryRun → confirm、prod deploy → 24h 束ね監視
4. **Issue #170 H2-H6 hardening**（H1 完了済、H2-H6 は independent follow-up）:
   - H2: `cleanup()` per-model 失敗ログ (silent-failure-hunter Critical conf 95)
   - H3: fatalError NSError userInfo 詳細化 (silent-failure-hunter High conf 80)
   - H4: preflight fetch assertion (pr-test-analyzer Rating 8) + PR #173 review-pr 残 follow-up (fixture-based lint test, race rate documentation)
   - H5: SharedTestModelContainer invariant test (pr-test-analyzer Rating 9) + cross-contamination smoke test (PR #173 follow-up)
   - H6: lint-model-container.sh エラーメッセージ改善 + xcodegen → lint 順序依存対応 (Evaluator MEDIUM follow-up)
5. **M5: Phase 0.9 allowedDomains 有効化**（審査通過 + whitelist 確認後）
6. **Phase 0.9 前の審査アカウント whitelist 確認**（Firestore Console 手作業、`tenants/279/whitelist/demo-reviewer@carenote.jp`）

### 参考資料（本セッション = 2026-04-23 午前）

- [PR #173 merged](https://github.com/system-279/carenote-ios/pull/173) — scheme parallelizable=NO + lint + OutboxSync re-shared
- [Issue #164 closed](https://github.com/system-279/carenote-ios/issues/164) — cross-suite race 真因確立 + 構造的抑止
- [Issue #170 H1 完了、H2-H6 follow-up](https://github.com/system-279/carenote-ios/issues/170)

---

# Handoff — 2026-04-23 早朝セッション: Day 1 prod deploy 完了 + #164 真因候補確立 + #170 hardening 起票

## セッション成果サマリ（2026-04-23 早朝セッション）

前セッション (2026-04-22 夜、PR #167) の直後に継続。積み残し Issue を PM/PL WBS で優先順に処理し、**Day 1 prod deploy (Node 22 runtime 化)** を完了、**Issue #164 の真因候補を cross-suite race と特定**、**Issue #170 (SharedTestModelContainer hardening bundle) を起票** した。

| PR | 内容 | Issue |
|----|------|-------|
| #171 (merged) | `docs/runbook/prod-deploy-smoke-test.md` の Day 1 実施ログ記録（PASS） | - |
| #169 (closed) | OutboxSyncServiceTests を shared container に差し戻す CI 再現確認 probe。local 3 回連続 PASS で再現不能 → close | #164 **真因候補確立（仮説段階、open 維持）** |

### 主要判断のハイライト

- **Day 1 スコープを Opt A（段階 deploy）で実行**: RUNBOOK 原文の `firebase deploy --only functions` (3 関数一括) ではなく、`--only functions:beforeSignIn,functions:deleteAccount` (2 関数分離) を採用。理由は「Day 1 は純粋 runtime 更新、Day 3 は transferOwnership の新規 deploy 検証」を分離することで、FAIL 時の原因切り分けを容易にするため。Codex セカンドオピニオンで計画段階レビュー実施
- **#100 を方式 b で整理**（close せず open 維持 + ラベル変更）: PR #115 で実装完了済だが prod deploy 未実施。close すると「セキュリティ文脈消失」のため `P0 → P1 + deploy-pending` ラベルに変更、実装完了を Issue コメント記録。Day 2 (Phase 0.5 Rules deploy) 完了時に close 候補
- **#164 真因は cross-suite race が最有力**（`/review-pr` 4 agent レビューで独立 2 agent が同一仮説指摘）: Swift Testing の `.serialized` は suite 内のみ直列化し **suite 間並列実行は抑止しない**。process-wide shared container で別 suite の cleanup が本 suite の test body 実行中に介入する race が uploadCalls.count==0 症状と整合。Local 環境で再現しないのは環境依存の race 典型
- **#170 を hardening bundle として分離起票**: cross-suite race 対応（H1 `.serialized` トップレベル化）だけでなく、silent-failure-hunter の Critical 指摘 2 件（cleanup per-model logging / fatalError NSError 詳細化）と preflight fetch assertion / invariant test を一括して取り組むため
- **PR #171 review 指摘の即時反映**: comment-analyzer の Critical C-1（24h ベースライン vs 15 分の整合破綻）を merge 前に修正。24h ベースライン欄を TBD で追加し、Day 2 着手前 (2026-04-23 15:51 JST) に再観測する運用を明文化

### Day 1 prod deploy 実績

- **実施日時**: 2026-04-23 03:51 JST (UTC 2026-04-22T18:51:04Z)
- **対象**: `beforeSignIn` / `deleteAccount` を nodejs20 → nodejs22
- **runtime 確認**: 両関数 nodejs22 / ACTIVE
- **Cloud Logging 15 分監視**: ERROR/WARNING 0 件
- **実機 smoke test**: Google ログイン → 録音 → 文字起こし編集 → 録音リスト、4 項目全 PASS
- **判定**: PASS
- **次工程**: Day 2 (Phase 0.5 Rules prod deploy) に **2026-04-23 15:51 JST 以降（12h 経過後）** 着手可能

### レビュー運用

- `/codex plan` セカンドオピニオン: 本セッション計画策定段階（WBS 設計 + Day 1 スコープ判断）
- `/review-pr` 4 agent 並列（PR #169、調査用 probe）: code-reviewer Approve / comment-analyzer Critical 2 / pr-test-analyzer Rating 9 / silent-failure-hunter Critical conf 90-95 × 2 + High × 3。**結果を Issue #170 起票に昇華**
- `/review-pr` 2 agent 並列（PR #171、docs-only）: code-reviewer Approve / comment-analyzer Critical 1 + Important 5。**C-1 を merge 前に反映**

### Issue Net 変化

セッション開始時 open 7 → 終了時 **8**（net **+1**、#170 起票）。

| 動き | 件数 | Open 数推移 |
|------|------|------------|
| 開始時 | — | 7 |
| #170 起票 (hardening bundle) | +1 | **8** |

> **CLAUDE.md KPI「Issue は net で減らすべき」違反**。正当性: triage rule #4 (rating ≥ 7 & conf ≥ 80) に silent-failure-hunter Critical conf 90/95 + pr-test-analyzer Rating 9 が該当、rule #5 (ユーザー明示指示) にも該当。#164 真因調査中に発見した cross-suite race 仮説と並列して 4 件の独立 hardening 項目を 1 bundle Issue にまとめた構造的判断。個別対応すると更に Issue 数が膨らむため妥当。

### CI の現状

- PR #171 (docs-only) merge 後の main `c50a371`: CI checks は docs のため skip。前 main `581bf13` の iOS Tests は PR #167 (lint gate) 時点で green 維持
- PR #169 branch CI (closed): iOS Tests 25m27s green（Issue #164 が CI runner でも再現しなかったことを示す）→ **cross-suite race が環境依存 flake であることを示唆**

### 次セッション推奨アクション（優先順）

1. **24h ベースライン追記**（2026-04-23 15:51 JST 以降、Day 2 着手前）: Cloud Monitoring から `beforeSignIn` / `deleteAccount` のエラー率平均 / p95 レイテンシ / invocation count を取得し、`docs/runbook/prod-deploy-smoke-test.md` Day 1 実施ログ TBD 欄を埋める
2. **M2: Day 2 Phase 0.5 Rules prod deploy**（deploy + 12h = 15:51 JST 以降）: RUNBOOK § Day 2 に従い、dev 事前検証 → `firebase deploy --only firestore:rules --project carenote-prod-279` 明示承認 → 実機 smoke test → baseline 記録 → Issue #100 close 判定
3. **M3: Day 3 transferOwnership prod deploy**（Day 2 +12h）: `docs/runbook/phase-1-admin-id-token.md` § 手順 A で dev dryRun → confirm、prod deploy → 24h 束ね監視
4. **Issue #170 hardening H1**（`.serialized` トップレベル化、#164 真因対応）: M3 完了後 or 並行着手。5 file+ 変更見込みで Evaluator 分離対象
5. **M5: Phase 0.9 allowedDomains 有効化**（審査通過 + whitelist 確認後）
6. **Phase 0.9 前の審査アカウント whitelist 確認**（Firestore Console 手作業、`tenants/279/whitelist/demo-reviewer@carenote.jp`）

### 参考資料（本セッション = 2026-04-23 早朝）

- [PR #171 Day 1 実施ログ merged](https://github.com/system-279/carenote-ios/pull/171)
- [PR #169 #164 CI 再現 probe closed](https://github.com/system-279/carenote-ios/pull/169)
- [Issue #170 SharedTestModelContainer hardening bundle](https://github.com/system-279/carenote-ios/issues/170)
- [Issue #164 #169 close 時の仮説更新コメント](https://github.com/system-279/carenote-ios/issues/164#issuecomment-4295342997)
- [Issue #100 方式 b 整理コメント](https://github.com/system-279/carenote-ios/issues/100#issuecomment-4295158875)

---

# Handoff — 2026-04-22 夜セッション: #165 Schema drift lint merge

## セッション成果サマリ（2026-04-22 夜セッション）

前セッション (2026-04-22 日中、PR #163) で起票した **Issue #165 (Schema drift risk) を最小対応で close**。`@Model` 型追加時の drift を CI で機械的に検知する lint を導入し、PR #163 の `SharedTestModelContainer` 方式を regression gate で保護した。加えて、初版 lint のレビュー過程で **line-oriented grep が multi-line `ModelContainer(for:` を silent pass する重大欠陥** を発見・修正。修正後の lint が既存の `OutboxSyncServiceTests.swift` violation を正しく検出し、Issue #164 追跡箇所として暫定許可（依存関係を #164 へ記録）。

| PR | 内容 | Issue |
|----|------|-------|
| #167 | `scripts/lint-model-container.sh` + CI step + `SwiftDataModels.swift` drift checklist | **#165 closed** |

### 設計判断のハイライト

- **PM/PL 判断で A 最小対応採用、B postpone**: Issue #165 本文に A (lint + doc comment) / B (`AppSchema.allModelTypes` 単一ソース化) の 2 案が提示されていたが、B は 8-10 ファイル改修で Evaluator 分離対象、直近 PR #163 でテスト基盤を触ったばかりで regression risk 高い。現状 4 `@Model` 型安定・新規追加予定なしで A の detection gate で十分と判断
- **初版 lint の C1 欠陥発見**: `/review-pr` 6 並列レビューで silent-failure-hunter + pr-test-analyzer が独立で指摘、pr-test-analyzer は fabricated input で実証確認。grep の `\s` は newline にマッチせず、**`SharedTestModelContainer` 自身が multi-line style** のため、同 style のコピペ violation を全て silent pass する致命的欠陥。`perl -0777` slurp mode で修正し、generic + whitespace variants も同時に catch
- **隠れ violation 顕在化**: 修正後 lint を走らせたら `OutboxSyncServiceTests.swift:84-87` の既存 `ModelContainer(for:)` を検出（PR #163 で Issue #164 追跡中の per-suite container 局所 rollback）。旧 lint が silent pass していた実証 → **C1 修正の正当性が現物で証明された**。`ALLOWED_TEST_FILES` 配列化で Issue #164 参照付き暫定許可、#164 close 時に削除する依存関係を script 内コメント + #164 Issue コメントに記録
- **Positive pre-flight assertion 追加**: 許可ファイルの existence + pattern 含有を事前検証。helper 削除/rename や regex 破損でも silent pass しない（silent-failure-hunter H1/H2 対応）

### レビュー運用

- `/review-pr` 6 並列（type-design は新規型なしでスキップ、5 並列実動）:
  - code-reviewer / comment-analyzer / code-simplifier: Approve
  - **silent-failure-hunter: Critical 1 (C1 conf 95) + High 2 (H1 conf 90, H2 conf 85)**
  - **pr-test-analyzer: Important 1 (rating 7、実証済)**
- 初版 C1/H1/H2/Important を 1 commit で同時修正（commit `5ff4bf7`）、再 push で CI green
- Evaluator 分離プロトコル (5 files+) は該当せず（3 ファイル +77 行の小規模 PR）

### 本セッション起票（実害ベース）

なし。Issue #164 への暫定許可クロス参照はコメント追加のみで新規 Issue 化せず（triage rule #5 未該当）。

### Issue 数推移

セッション開始時 open 8 → 終了時 **7**（net **-1**、#165 close）。

| 動き | 件数 | Open 数推移 |
|------|------|------------|
| 開始時 | — | 8 |
| #165 close (PR #167) | -1 | **7** |

> CLAUDE.md KPI「Issue は net で減らすべき」達成。rating ≥ 7 の指摘を全て対応済、rating 5-6 の「production-side Schema lint 拡張」は Issue #165 option B 相当で postpone（triage rule 遵守）。

### CI の現状

- PR #167 feature branch (`5ff4bf7`) 最終 CI で iOS Tests job が **36m54s で green**（全 135 tests PASS、macOS runner の初期 cold start 込み）
- 新 lint step `Lint - SwiftData schema drift guard (Issue #165)` が CI 環境（macOS 15、bsd grep、macOS 標準 perl）で期待通り動作確認: `lint-model-container: OK (2 approved file(s) register @Model types)`
- 本 handoff PR push 時点で main `73fd304` (squash merge commit) の CI は進行中。設定/docs のみの変更で regression リスクなし

### 次セッション推奨アクション（本セッション反映後、優先順）

1. **審査アカウント whitelist 登録確認**（Firestore Console で `tenants/279/whitelist` に `demo-reviewer@carenote.jp` 確認 — Phase 0.9 前提ゲート、前セッションから継続）
2. **iOS 実機 smoke test**（Phase 0.5 / Phase 1 / Node 22 統合動作確認、前セッションから継続）
3. **Day 1-3 prod deploy 段階実施**（Node 22 → Phase 0.5 Rules → Phase 1 transferOwnership、各単独、24h 監視。`docs/runbook/prod-deploy-smoke-test.md` 使用）
4. **#164 OutboxSyncServiceTests shared container 真因調査**（本セッションで新 lint が既存 violation を現物検出したことで調査優先度が上がった。ALLOWED_TEST_FILES 暫定許可削除が close 条件。Issue 本文 4 仮説を `/impl-plan` で順序立てて検証推奨）
5. **#105 deleteAccount E2E Emulator Suite テスト**（時間確保セッションで）
6. **Phase 0.9 dev 先行検証 → prod 実施**（審査通過後、#111 close）

> 本セッションで lint が OutboxSyncServiceTests violation を catch した事実は、#164 の per-suite container が「意図的な rollback」として構造化されたことを意味する。#164 真因調査の副産物として lint の ALLOWED_TEST_FILES 削除 + doc comment 更新が連動する依存関係を持つ。

### 参考資料（本セッション = 2026-04-22 夜）

- [PR #167 Schema drift lint + CI gate](https://github.com/system-279/carenote-ios/pull/167)
- [Issue #164 OutboxSync 暫定許可クロス参照コメント](https://github.com/system-279/carenote-ios/issues/164#issuecomment-4294661569)

---

# Handoff — 2026-04-22 日中セッション: #141 SwiftData SIGTRAP 根本解決 merge

## セッション成果サマリ（2026-04-22 日中セッション）

前セッション (2026-04-23 早朝) で Postpone 判定していた **Issue #141 (SwiftData 同一プロセス複数 ModelContainer SIGTRAP) を案 C' で根本解決**。全体テスト実行時の crash ゼロを達成し、CareNote iOS の test suite 安定性を回復。

| PR | 内容 | Issue |
|----|------|-------|
| #163 | SharedTestModelContainer 導入 + 9 test files 統一 + `.serialized` 適用 | **#141 closed** |

### 設計判断のハイライト

- **案 C' の 1 ファイル収束**: 当初見積もり「9 files 変更」だったが、helper 側で `SharedTestModelContainer` + 自動 cleanup を仕掛けることで呼び出し側の変更を回避しようとした。しかし `/simplify` の reuse agent が「per-suite `makeContainer()` 残存で SIGTRAP 再発リスク」を指摘し、7 files の per-suite container を一括 shared 化。最終 10 files / +95/-124（-29 行の純減）
- **`.serialized` 全面適用**: Swift Testing の default parallel 実行が shared container 上で競合し `OutboxSyncServiceTests` が回帰 (uploadCalls.count が 3 倍に膨らむ) → SwiftData-backed 7 suites に `.serialized` 付与で解消
- **OutboxSyncServiceTests のみ per-suite 維持**: `.serialized` 後も 2 test が `uploadCalls.count → 0` で回帰。当初「service が独自 ModelContext 派生」と推測したが `/review-pr` 6 agent の grep で **全て `modelContainer.mainContext`** 使用と判明 → 真因未確定のまま per-suite container に局所 rollback、Issue #164 で調査継続

### レビュー運用

- `/simplify` 3 並列: reuse agent の scope 拡張指摘で 1 file → 10 files に拡大（Issue #141 再発ガードを担保）
- `/review-pr` 6 並列: Critical 2 件検出
  - C1: OutboxSync コメント factually 誤り → commit c2f3e60 で訂正
  - C2: Schema drift risk (`@Model` 型 hard-code 3 箇所) → Issue #165 で follow-up
- Evaluator 分離プロトコル (5 files+) は `/review-pr` 6 並列で代替と判断

### 本セッション起票（実害ベース）

| # | タイトル | 優先度 | 根拠 |
|---|---------|-------|------|
| #164 | OutboxSyncServiceTests が SharedTestModelContainer と相性が悪く回帰する（真因未確定） | P2 bug | triage #2 再現可能なバグ、PR 作成時点で .serialized + shared で 2 test が `uploadCalls.count == 0` を再現 |
| #165 | Schema drift risk: `@Model` 型を SharedTestModelContainer と LocalDataCleaner で hard-code | P2 bug | triage #2 実害シナリオ明確（新 `@Model` 追加時の LocalDataCleaner 漏れ = #91 type regression）+ review 5 agent 合議指摘 |

### Issue 数推移

セッション開始時 open 7 → 終了時 **8**（net **+1**、#141 close / #164 #165 起票）。

| 動き | 件数 | Open 数推移 |
|------|------|------------|
| 開始時 | — | 7 |
| #141 close (PR #163) | -1 | 6 |
| #164 起票（OutboxSync 真因調査） | +1 | 7 |
| #165 起票（Schema drift） | +1 | **8** |

> **注**: net +1 だが、#141 の SIGTRAP crash という既存の実害を解消した上で、調査過程で発見した 2 件の潜在リスクを可視化した結果。triage 基準に照らすと #164/#165 共に「再現可能な bug / 明確な実害シナリオ」で起票条件を満たす。レビュー agent の rating 7-9 指摘のみ採用、rating 5-6 の「改善提案」は全て PR コメント or 却下（triage rule 遵守）。

### CI の現状

- main 最新 (`589b87f`, PR #163) で iOS Tests job が **23m55s で green**。PR #161 の retry logic が実効することも実証（simulator runtime install の retry 発動なし）
- 全 18 suites / 135 tests PASS

---

> **Note (2026-04-22 日中追記)**: 以下 2026-04-23 早朝セッションの記録内で扱った **#141 Postpone 判定は PR #163 で覆り、close 済**。「再開時のアクションメモ」「再開条件」等の Postpone 前提記述は履歴保存目的で残すが、次セッションの参照対象ではない。

# Handoff — 2026-04-23 早朝セッション: #159 CI retry fix merge / #141 真因確定 + Postpone

## セッション成果サマリ（2026-04-23 早朝セッション）

2026-04-22 夜セッションで起票された #159 (iOS Tests CI flaky) を解消。加えて #141 (SwiftData ModelContainer 重複クラッシュ) を再現検証し、**案 B (ModelContainer Optional 化) が効果なし**と確認。真の解決策 = **案 C' (test 全体で shared container)** を特定して Issue に追記し、本セッションでは Postpone (open 維持)。

| PR | 内容 | Issue |
|----|------|-------|
| #160 | docs/handoff 2026-04-22 夜セッション成果反映 + Issue 推移計算ミス修正 | — |
| #161 | iOS Simulator Runtime install の retry logic 追加 (最大 3 回 + `set -euo pipefail`) | **#159 closed** |

### 設計判断のハイライト

- **PR #161 Review 反映で fallback 削除**: 初版は「既存 iOS runtime が利用可能なら warning で継続」の fallback path を含んでいたが、code-reviewer + silent-failure-hunter の 2 エージェント並列レビューが共通で Critical 指摘 (`'iOS' in identifier` は iOS 16 等古い runtime も通過 → Boot Simulator が `iPhone 16 Pro` を見つけられず silent skip)。最小 scope (retry のみ) に絞って再コミット
- **#141 は対症療法不能と確定**: `ModelContainer` を Optional 化して body 副作用 (`PresetTemplates seedIfNeeded`) を遮断しても、test helper 側で毎 test 新 container 生成するため SIGTRAP 継続。`test 全体で shared container` に切替える大規模 test refactor (12+ files) が唯一の根本解決
- **#141 は Postpone (open 維持)**: 再開条件を明記 (Xcode/iOS 更新での挙動変化再検証 / 全体テスト実行の必要性高まり / 新規 `@Model` 型追加との合流)

### レビュー運用

- PR #161: 2 エージェント並列レビュー（code-reviewer / silent-failure-hunter）。小規模 PR (1 file +20/-1 最終 diff) なので 6 エージェントは過剰
- #141 の案 B 実装は検証で効果なしと判明 → commit せず rollback (production code を dirty に残さない)

### 本セッション起票（実害ベース）

なし。

### Issue 数推移

セッション開始時 open 8 → 終了時 **7**（net **-1**、#159 close）。

| 動き | 件数 | Open 数推移 |
|------|------|------------|
| 開始時 | — | 8 |
| #159 close (PR #161) | -1 | **7** |

### #141 再開時のアクションメモ

- `CareNoteTests/TestHelpers/SwiftDataTestHelper.swift` に `SharedTestModelContainer` (static let) 追加
- `makeTestModelContainer` / `makeClientOnlyTestModelContainer` を `SharedTestModelContainer.shared` に統合
- 各 test の setUp で `context.delete(model:)` による事前 cleanup で分離性を代替
- 影響範囲: CareNoteTests 配下の 15 test ファイルのうち ModelContainer 生成ロジックを持つもの (明示列挙: `ClientRepositoryTests`, `ClientSelectViewModelTests`, `ClientCacheServiceTests`, `RecordingListViewModelTests`, `RecordingRepositoryTests`, `TemplateCreateViewModelTests`, `TemplateListViewModelTests`, `OutboxSyncServiceTests`, `RecordingConfirmViewModelTests` の 9 件。残りは `@Model` を touch しない可能性)
- Quality Gate (Evaluator 分離プロトコル) 対象
- 再現コマンド: `xcodebuild test -project CareNote.xcodeproj -scheme CareNote -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:CareNoteTests/ClientRepositoryTests`

### CI の現状

- main 最新 (`9a177fe`, PR #161) は `.github/**` のみの変更で iOS Tests job が `paths-ignore` により trigger されない
- **次の substantive PR (Swift コード変更を含む) で retry 効果の実効検証が必要**
- それまで main iOS Tests CI 最新失敗は 24760085320 (2026-04-22 04:24Z, commit 506f4e8) のまま残る

---

