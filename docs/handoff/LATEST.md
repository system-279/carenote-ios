# Handoff — 2026-04-24 夜 → 2026-04-25 未明セッション: Issue #182 delete Firestore sync 完全解消 + Build 36 / v0.1.1 TestFlight リリース

## ✅ Issue #182 auto-close（PR #191 merge） + Build 36 uploaded（v0.1.1 patch bump）

前セッション handoff の推奨 #1「🔥 #182 iOS delete 機能の Firestore 同期実装」を impl-plan v2 で完遂。Codex セカンドオピニオンで v1 の事実誤認 2 件（存在しない `recording.audioStoragePath` / `StorageService.delete`）を検出し、AC を抜本改訂。TDD (RED→GREEN→REFACTOR) + `/simplify` + `/review-pr` 5 agent 並列レビューで Critical 2 件 + Important 6 件を完全対応して merge → TestFlight Build 36 (v0.1.1) uploaded。

### セッション成果サマリ

| PR | 内容 | merge 順 |
|----|------|----------|
| **#191 (merged)** | iOS 録音削除の Firestore 同期 (Issue #182 close) | 1 |
| **#195 (merged)** | Build 36 / v0.1.1 に project.yml / pbxproj 同期 | 2 |

### 主要判断のハイライト

- **Codex plan レビューで v1 の事実誤認を検出**: impl-plan v1 は `recording.audioStoragePath` (SwiftData `RecordingRecord` に存在しない、Firestore DTO のみ) と `storageService.delete(gsPath:)` (未実装) を参照していた。実コード調査で実装前に発見、AC 抜本改訂で Storage 削除を follow-up Issue に切り出し。
- **Storage 削除を本 PR スコープ外に**: Codex 推奨 (a) 案「Firestore のみ削除、Storage orphan cleanup は server-side Cloud Function 化」を採用。既存 `functions/scripts/delete-empty-createdby.mjs` の思想転用で #192 起票。
- **AC5 guard 新設**: `firestoreId != nil` + `firestoreService == nil` / `tenantId` 欠落時は local-only 削除を拒否して throw（再発防止）。`RecordingDeleteError.remoteServiceUnavailable` enum で type 安全に表現。
- **View 層の `try?` swallow を撤廃**: `.alert` binding で delete 失敗をユーザーに可視化（silent failure 原則遵守）。
- **5 agent 並列レビューで Critical 2 + Important 6 を即時修正**:
  1. `.onDelete` IndexSet stale index → snapshot 化 + 失敗時 break
  2. local audio 削除の silent swallow → `logger.warning` 追加
  3. `deleteRecording` logging 皆無 → guard / Firestore 失敗で `logger.error`
  4. エラーメッセージ「ネットワーク確認」誤誘導 → 「アプリ再起動 / 再サインイン」
  5. AC9-3 test コメント guard 評価順説明誤り → 訂正
  6. OutboxItem cascade の VM test 欠如 (rating 7) → AC9-1/9-2 に assertion 追加
  7. `tenantId == ""` 境界値テスト欠如 (rating 6-7) → +1 テスト
  8. StubRecordingStore silent no-op → `Issue.record + throw` fail-fast
- **MARKETING_VERSION 0.1.0 が App Store Connect で closed**: 初回 upload で `Invalid Pre-Release Train` エラー。semver patch bump (0.1.0 → 0.1.1) で再 upload 成功。build 番号は 35 → 36。
- **main 直接 push が hook で block**（CLAUDE.md 準拠）→ PR #195 で project.yml / pbxproj の sync を feature branch 経由で merge。

### 実装実績

- **変更ファイル合計**: PR #191 で 5 個 / +301/-21 行、PR #195 で 2 個 / +6/-6 行（version bump）
  - `CareNote/Services/FirestoreService.swift` (#191、protocol + impl 追加)
  - `CareNote/Features/RecordingList/RecordingListViewModel.swift` (#191、`RecordingDeleteError` + deleteRecording 書き換え)
  - `CareNote/Features/RecordingList/RecordingListView.swift` (#191、alert binding + IndexSet snapshot)
  - `CareNoteTests/RecordingListViewModelTests.swift` (#191、新規 4 test + helper + cascade assertion)
  - `CareNoteTests/OutboxSyncServiceTests.swift` (#191、StubRecordingStore fail-fast)
  - `project.yml` / `CareNote.xcodeproj/project.pbxproj` (#195、version sync)
- **テスト成長**: 141 → **145 tests / 20 suites** (+4 新規: firestoreId==nil / firestoreService==nil / tenantId==nil / tenantId 空文字列)
- **CI**: PR #191 Pre-merge 25m4s PASS、PR #195 Pre-merge 26m26s PASS
- **TestFlight upload**: Build 36 / v0.1.1、`** EXPORT SUCCEEDED **` (Firebase Firestore 系 dSYM 欠損 warning は既知で blocker ではない)

### レビュー運用（Generator-Evaluator 分離 + 3 層）

- `/codex plan` (設計段階、MCP 版 timeout 後 Bash 版で成功): AC1-10 改訂案を提示、Storage スコープ外判断、Firestore→local 順、`firestoreId == nil` 分岐の妥当性を確認、High/Medium/Low リスク分類
- `/simplify` 1 回 (REFACTOR 段階): S1 `#expect(throws:)` idiom、S2 fixture helper、S3 doc wording、S4 DI TODO コメントの 4 項目全反映
- **`/review-pr` 5 agent 並列** (code-reviewer / pr-test-analyzer / silent-failure-hunter / comment-analyzer / type-design-analyzer、code-simplifier は REFACTOR で実行済のため除外): Critical 2 + Important 6 + Suggestion 多数 → commit `846e001` で全 Critical/Important 修正、Suggestion は採否を選別 (一部 follow-up Issue 化)

### Issue Net 変化

セッション開始時 open **7** → #182 close (-1) → 起票 #192/#193/#194 (+3) → 終了時 open **9**（net **+2**）

| 動き | Issue | 件数 | Open 数推移 |
|------|------|------|------------|
| 開始時 | — | — | 7 |
| PR #191 merge → #182 auto-close | -1 | -1 | 6 |
| follow-up 起票 #192 (Cloud Storage cleanup) | +1 | +1 | 7 |
| follow-up 起票 #193 (Firestore error 分類) | +1 | +1 | 8 |
| follow-up 起票 #194 (polling silent catch) | +1 | +1 | 9 |
| **終了時** | — | **+2 net** | **9** |

> **Net +2 の理由**: CLAUDE.md 「Issue は net で減らすべき KPI」に対し進捗不足の数値ではあるが、**実害ある user-facing bug (#182) を production TestFlight リリースまで完遂**した成果に対して、`/review-pr` で rating ≥ 7 の legitimate な silent failure リスクが 3 件表面化したため triage 基準 #4 (rating ≥ 7 & confidence ≥ 80) に該当する起票を行った。3 件とも **既存の silent failure の可視化**であり新規バグ導入ではない。
> - #192 audio orphan: Cloud Storage 蓄積 (real harm over time)
> - #193 Firestore error 分類: AC10 UX 化の完遂に必要
> - #194 polling silent catch: CLAUDE.md 「silent failure 禁止」違反の明示化
>
> 仮にこれらを起票しなかった場合、PR コメントに埋もれて忘れ去られるリスクが高く、triage 基準 rating ≥ 7 の明示要件に該当。起票が rating 5-6 の任意改善を機械的に Issue 化した結果ではないことを確認済 (Codex + review-pr 両方での確認)。

### セッション内教訓（handoff 次世代向け）

1. **impl-plan は実コード検証を伴うべき**: v1 は 2 件の存在しない API 参照を含んでいた (Codex の plan review で検出)。plan 段階で grep で API 実在確認する手順を `impl-plan` スキルに追記候補 (TODO)。
2. **TestFlight MARKETING_VERSION は bump 必須**: 既存 `0.1.0` で再 upload 試行 → Apple 側で "train is closed" エラー。今後 Build 番号だけでなく MARKETING_VERSION も release 時に semver bump 方針を明示化すべき (upload-testflight.sh に option 追加 or runbook に明記)。
3. **main 直接 push hook は常に発火する**: Build 番号 bump も PR 経由必須。upload-testflight.sh は project.yml の変更を sed で書き換えるが、commit/push は別手順。今後は upload 前に feature branch 切り替え、upload 後に PR 作成の順で運用すると hook 衝突を避けられる。
4. **5 agent 並列レビューは Critical を確実に拾う**: 今回 IndexSet stale index は silent-failure-hunter + code-reviewer で独立に検出、安全策の相互チェックが効いた。単一 agent 依存だと見逃しリスクがある。
5. **Generator-Evaluator 分離の TDD 活用**: Codex plan review → 自身 TDD → simplifier → review-pr の 4 段階で品質を積み上げた。Codex の sanbox: read-only モードはコード読み取りに有効。MCP 版は 300s timeout あるので長尺の review は Bash 版が安全。

### CI の現状

- main `9194f84` (PR #195 merge 後): iOS Tests CI push 経由で in_progress（post-merge の re-verify、blocker ではない）
- Pre-merge CI は両 PR とも PASS 済 (PR #191: 25m4s / PR #195: 26m26s)

### 次セッション推奨アクション（優先順）

Issue #182 の production リリースは完了。次は実機 smoke と follow-up の ROI 評価。

1. **🔥 Build 36 / v0.1.1 実機 smoke (最優先)**:
   - TestFlight で Build 36 配布 → 録音作成 → スワイプ削除 → Firebase Console で `tenants/279/recordings/{id}` が消滅確認 → pull-to-refresh で復活しないこと
   - PR #156 の deleteAccount local purge も Build 36 初リリースなので同時確認
   - smoke PASS 後、`handoff` で成功記録 + #111 close 判断 (自録音 CRUD / Guest 振分 / allowedDomains 3 条件同時確認できる)
2. **#192 Cloud Storage orphan cleanup** (enhancement, P2): Cloud Function 化。`functions/scripts/delete-empty-createdby.mjs` の思想転用。所要 2-3h 見積もり、Firestore emulator でのテスト含む。
3. **#193 Firestore error 分類** (enhancement, P2): AC10 UX 化の完遂。`FirestoreErrorCode` cast + permissionDenied / notFound / transient の 3 分類。所要 1-2h。
4. **#194 polling silent catch 可視化** (bug, P2): `pollProcessingRecordings` + `try? save` を logger で surface。CLAUDE.md silent failure 禁止違反の解消。所要 30min-1h。
5. **#111 実機 smoke 後追い close**: Build 36 配布時に条件揃えば即 close (Apple ID × Google 連携を除く CRUD / Guest / allowedDomains 3 点確認)。
6. **#178 Stage 2 GHA + WIF 運用基盤** (enhancement, P2、ADR-009 follow-up)
7. **#105 deleteAccount E2E (Firebase Emulator Suite)** (enhancement, P2、I-Cdx-1)
8. **#92 / #90 Guest Tenant 関連** (enhancement)、**#65 Apple × Google account link** (enhancement)

### 関連リンク

- [Issue #182 CLOSED](https://github.com/system-279/carenote-ios/issues/182) — iOS delete Firestore 同期
- [PR #191 merged](https://github.com/system-279/carenote-ios/pull/191) — Issue #182 修正 (Firestore→local 順 + AC5 guard)
- [PR #195 merged](https://github.com/system-279/carenote-ios/pull/195) — Build 36 / v0.1.1 project.yml sync
- [Issue #192 (follow-up)](https://github.com/system-279/carenote-ios/issues/192) — Cloud Storage orphan cleanup
- [Issue #193 (follow-up)](https://github.com/system-279/carenote-ios/issues/193) — Firestore error 分類
- [Issue #194 (follow-up)](https://github.com/system-279/carenote-ios/issues/194) — polling silent catch
- impl-plan v2 (Issue #182 コメント): https://github.com/system-279/carenote-ios/issues/182#issuecomment-4313520262
- Codex plan review: [`codex exec ...`](https://github.com/system-279/carenote-ios/pull/191) の PR description に反映
- /review-pr 5 agent レビュー反映: [PR #191 comment](https://github.com/system-279/carenote-ios/pull/191#issuecomment-4313729400)

---

# Handoff — 2026-04-24 夜セッション: Issue #170 hardening bundle 完全 close（H1-H6 全項目）

## ✅ #170 hardening bundle 最終項目（H5）merge で Issue #170 auto-close → Issue Net -1 達成

前セッション（2026-04-24 昼）終了時の推奨アクション「#170 H2-H6 hardening（6-10h）」を本セッションで完遂。PR #173（先行 H1）と本セッション 4 PR（H2/H3, H6, H4, H5）で 6 項目すべて main 統合、**Issue #170 完全 close**。

### セッション成果サマリ

| PR | 項目 | 内容 | merge 順 |
|----|------|------|----------|
| #173 (前セッション) | H1 | scheme parallelizable=NO + lint-scheme-parallel.sh + 再合流 | ✅ 済 |
| **#185 (merged)** | **H2/H3** | `cleanup()` per-model 失敗ログ + `fatalError` NSError unpack + `formatNSError` helper | 1 |
| **#186 (merged)** | **H6** | lint-model-container.sh に Pre-flight 3（Issue 参照コメント強制）+ bash 3.2 silent failure 修正 + xcodegen→lint 順序 | 2 |
| **#187 (merged)** | **H4** | OutboxSyncServiceTests 4 test に preflight assertion（`fetchCount`+`fileExists`）+ `Issue.record` 経由の fetch error context | 3 |
| **#188 (merged)** | **H5** | SharedTestModelContainer invariant tests 4 件（singleton / schema tripwire / cleanup-empties-all / round-trip） | 4（#170 close） |

### 主要判断のハイライト

- **impl-plan v1/v2 で 4 PR 分割を設計**: H2/H3（同一ファイル）/ H6（shell+yml 独立）/ H4（OutboxSyncServiceTests）/ H5（新 invariant suite）に分解し、独立 merge で main 衝突リスク最小化
- **逐次主義選択**（PM/PL 判断）: 「CI 16-20 分待ちに PR D 並列着手」を却下、1 PR 完了→次へで状態シンプル化、PR #173 時の bash 3.2 `mapfile` fail の教訓を活用
- **fail-fast 契約維持** (PR #185): Issue 本文の「rethrow」を「best-effort loop」に誤拡張しない、元コード契約保持の pragmatic 判断
- **bash 3.2 command substitution silent failure 防御** (PR #186): silent-failure-hunter Critical 指摘で `if ! missing_issue_refs=$(perl ...)` の明示 exit code check に変更、`set -e` が propagate しない構造を回避
- **`fetchCount` 使用** (PR #187): SwiftData `fetch().count` の object hydration 回避（efficiency agent 指摘）+ `Issue.record` で fetch error 時の context 維持（silent-failure-hunter）
- **Swift Testing の `@Suite` 間順序不保証を受容** (PR #188): cross-suite contamination smoke test を sequential round-trip で代替、doc comment で literal 不可の制約を明記、`.serialized` trait + scheme `parallelizable=NO` の defense-in-depth
- **schema tripwire 追加** (PR #188 review 反映): `schema.entities.count == 4` で 5 番目の `@Model` 追加忘れを検知、pr-test-analyzer Rating 7 指摘

### 実装実績

- **変更ファイル合計**: 4 個 / 5 ファイル（+280 程度）
  - `CareNoteTests/TestHelpers/SwiftDataTestHelper.swift` (#185、NSError unpack + cleanup per-model ログ)
  - `scripts/lint-model-container.sh` (#186、Pre-flight 3 + meta-guard + 3-step ガイダンス)
  - `.github/workflows/test.yml` (#186、xcodegen→lint 順序変更)
  - `CareNoteTests/OutboxSyncServiceTests.swift` (#187、preflight + assertPreflightState helper)
  - `CareNoteTests/TestHelpers/SwiftDataTestHelperTests.swift` (#185 新設 + #188 invariant suite 追加)
- **テスト成長**: 135 → **141 tests / 20 suites**（+6 新規 test、+2 新 suites）
  - 2 回の 20 回連続実行 × 4 PR = **合計 160 回連続実行で全 PASS**（race-free 検証）
- **CI**: 4 回 green（PR #188 で lint false positive 1 件 → amend で即 fix）
- **ローカル lint self-test**: lint-model-container.sh 8 種ケース全 PASS（PR #186、OK / Issue コメント欠落 / entry 削除 / 変数名 typo / blank line 分離 / 2 種の false positive 検証 / 違反ファイル挿入）

### レビュー運用（3 層 + Quality Gate）

- `/simplify` 3 並列: 4 回（reuse / quality / efficiency）
- `/safe-refactor`: 1 回（PR #185）
- **`/evaluator` (rules/quality-gate.md §2 発動)**: 1 回（PR #188、新機能追加）→ **APPROVE**（AC-C1〜C4/C6 PASS、AC-C5 UNTESTABLE [20 回実行で後検証済]）
- `/review-pr` 4 並列: 4 回（code-reviewer / pr-test-analyzer / silent-failure-hunter / comment-analyzer、type-design は新規型なしで skip）
- **API 529 Overloaded**: 1 回発生（PR #188 の simplify quality + evaluator）→ CLAUDE.md rules/workflow.md §3 プロトコル遵守、8 分待機で復旧・全 agent 完了、手動代替行動なし

### Issue Net 変化

セッション開始時 open **8** → #170 close (-1) → 終了時 open **7**（net **-1**）

| 動き | 件数 | Open 数推移 |
|------|------|------------|
| 開始時 | — | 8 |
| PR #188 merge → #170 auto-close | -1 | **7** |

> **CLAUDE.md KPI「Issue は net で減らすべき」達成 ✅**。本セッションは review-pr Critical 0 件、Important 多数を PR 内修正で吸収（新規 Issue 起票ゼロ）。triage 基準 #4（rating ≥ 7 & confidence ≥ 80）を超える指摘も全て PR 内で解消、Issue net +0。

### セッション内教訓（handoff 次世代向け）

1. **lint regex の doc comment false positive** (PR #188 amend fix): `lint-model-container.sh` の perl slurp regex が doc 内の `` `ModelContainer(for:)` `` 文字列を誤検出。ローカル self-test でカバーされておらず CI で判明。次回 lint 改修時は「別ファイルの doc comment/string literal 内の API 名言及」ケースを self-test に含める（rating 6 enhancement として TODO 記録、Issue 化せず）
2. **bash 3.2 + `set -e` + command substitution**: silent failure の典型パターン。`set -e` は command substitution 内の failure を propagate しない（macOS default の bash 3.2）。CI runner の bash が新しくても script は bash 3.2 互換で書く慣習を崩さないこと
3. **Swift Testing `@Suite` 間順序不保証**: cross-suite 検証は literal 実装不可、sequential round-trip で代替可能。`.serialized` trait + scheme parallelizable=NO の defense-in-depth が必要
4. **並列着手を避ける判断基準**: 2 PR 並列は「Agent Teams 閾値（3 独立タスク）未満」+ 「CI fail 時の原因切り分け困難」+ 「main 衝突」の 3 観点で ROI 負、本セッションは 4 PR 全て逐次着手で完遂

### CI の現状

- main `e5633e8` (PR #188 merge 後): iOS Tests CI 17m57s green、141 tests / 20 suites PASS
- cross-suite race の四重防御完成:
  1. scheme `parallelizable=NO` (#173)
  2. `lint-scheme-parallel.sh` machine check (#173)
  3. `SharedTestModelContainer.cleanup()` の NSError diagnostic (#185)
  4. `assertPreflightState` diagnostic + `SharedTestModelContainerInvariantsTests` invariant 検証 (#187/#188)

### 次セッション推奨アクション（優先順）

Issue #170 hardening bundle 完了で test infra は安定化。次は application-side の bug fix / enhancement。

1. **🔥 #182 iOS delete 機能の Firestore 同期実装**（bug, P2）: 前セッションから継続、impl-plan v1 は Issue #182 コメントに既記載（AC1-10 / RED-GREEN-REFACTOR / 変更ファイル予測 4 個 / 所要 2-3h）。**feature branch `fix/issue-182-ios-delete-firestore-sync` を切って RED フェーズから即着手**
2. **#178 Stage 2 GitHub Actions + WIF 運用基盤**（enhancement, P2、ADR-009 follow-up）
3. **#111 Phase 0.9 prod tenants/279.allowedDomains 有効化**（enhancement, P2、実機 smoke 後追い close 条件満たせば close 候補）
4. **#105 deleteAccount E2E（Firebase Emulator Suite）**（enhancement, P2、I-Cdx-1）
5. **#92 / #90 Guest Tenant 関連**（enhancement）
6. **#65 Apple ID × Google account link**（enhancement）

### 関連リンク

- [Issue #170 CLOSED](https://github.com/system-279/carenote-ios/issues/170) — hardening bundle 6 項目完了
- [PR #185 merged](https://github.com/system-279/carenote-ios/pull/185) — H2/H3
- [PR #186 merged](https://github.com/system-279/carenote-ios/pull/186) — H6
- [PR #187 merged](https://github.com/system-279/carenote-ios/pull/187) — H4
- [PR #188 merged](https://github.com/system-279/carenote-ios/pull/188) — H5 (Closes #170)
- impl-plan v1/v2（Issue #170 コメント）: https://github.com/system-279/carenote-ios/issues/170#issuecomment-4308689214

---

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

1. **🔥 #182 iOS delete 機能の Firestore 同期実装 — 次セッション即着手・休まず完遂** (bug, P1 へ昇格検討): `FirestoreService.deleteRecording` 追加 + `RecordingListViewModel.deleteRecording` で Firestore delete 呼び出し。ADR-010 の author 分岐 (`admin OR createdBy==uid`) を活用できる設計済。**方針 A (FirestoreService 直接呼び出し) 確定**、方針 B (OutboxSync delete 拡張) は却下 (実装コスト高・ROI 低)。
   - **impl-plan は Issue #182 のコメント `impl-plan v1` に詳細記載**（AC1-10 / RED-GREEN-REFACTOR ステップ / 変更ファイル予測 4 個 / 所要 2-3h / リスク対策 3 点）
   - **次セッション開始時のアクション**:
     1. `/catchup` で本 handoff を読む
     2. Issue #182 `impl-plan v1` コメントを開く
     3. feature branch `fix/issue-182-ios-delete-firestore-sync` 作成
     4. RED フェーズ (失敗テスト追加) から開始
   - **本セッションの反省 (ユーザーに謝罪済)**: PR #181 時に iOS 側の delete 実装確認を怠り、smoke test まで問題が顕在化しなかった。ADR-010 § 再発防止プロトコル §4 に「iOS/クライアント側実装確認」を恒久プロトコル化。
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

