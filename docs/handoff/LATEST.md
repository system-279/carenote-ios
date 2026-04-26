# Handoff — 2026-04-26 早朝セッション: 「完全着地」フロー Phase B 完遂 + Build 37 / v0.1.2 TestFlight upload

## ✅ Issue #201 close (PR #202 merge) + Build 37 release bump (PR #203 merge) + TestFlight upload 完了

ユーザー要件「テナント内ドメイン自動加入 + admin UI でアカウント引き継ぎ」の完全着地ルートを実行。Apple App Review 経緯を memory に集約 (`project_carenote_app_review.md` 新設) し、Phase 2 admin UI を実装、Build 37 / v0.1.2 として TestFlight upload まで完遂。残作業はユーザーの App Store Connect での App Review 提出と Unlisted release のみ。

### セッション成果サマリ

| PR | Issue | 内容 | merge 順 |
|----|-------|------|----------|
| **#202 (merged)** | **#201** | transferOwnership iOS admin UI (ADR-008 Phase 2): Service / ViewModel / View / SettingsView edit + テスト 38 ケース | 1 |
| **#203 (merged)** | — | Build 37 / v0.1.2 bump (project.yml + pbxproj sync) | 2 |

### 主要判断のハイライト

- **Apple App Review 経緯の memory 化** (ユーザー指摘「プロジェクトで最も重要なことの 1 つ、ちゃんと正しく理解と把握しといて」): Build 21-22 リジェクト (Sign in with Apple 未実装 / 赤字エラー判定) → Build 33 設計転換 (ADR-007 Guest Tenant 自動プロビジョニング) → Build 35 Unlisted 配布中 → Build 37 提出予定の全経緯を `~/.claude/memory/project_carenote_app_review.md` に集約。再発防止チェックリストと完全着地フローの正確な依存関係も記述
- **TestFlight ≠ 永続配布の認識**: TestFlight 90 日 expire のため社員全員配布には不向きと判明 → App Store Unlisted Distribution (CareNote 既存運用) ルートで「完全着地」を再定義
- **Phase B 実装パターン**: AuthViewModel.deleteAccount の Functions Callable パターン踏襲、`TransferOwnershipServicing` protocol で SDK 抽象化、`@Observable @MainActor` ViewModel + state machine (`idle → dryRunInFlight → preview → confirmInFlight → completed / failed`)、Sendable 維持で SwiftData `@Model` を associated value に持たせない (PR #198 教訓)
- **Quality Gate 3 層 + Evaluator バグ検出**: `/simplify` 3 並列 → callable 名/region constant 化 + Equatable コメント。Evaluator (5 ファイル + 新機能で発動) → **checkbox リセット欠落バグ** (preview 状態で再 dryRun 時に二段階 confirm 安全性違反) を検出、修正 + 専用回帰テスト追加。`/review-pr` 6 agent → triage 基準 (rating ≥ 7 + confidence ≥ 80) 6 件全反映 (transient エラー分類 / preview 中 uid 編集禁止 / silent guard logger / alreadyExists 文言誤誘導 / message(for:) 12 文言テスト / PR/Issue 番号コメント削除)
- **CI Xcode 16.3 strict concurrency**: ローカル Xcode (iOS 26.2 SDK) では警告のみだったが CI で error 化 → `nonisolated static func message(for:)` で SwiftUI View 内 pure function を MainActor 跨ぎから呼び出し可能化
- **upload-testflight.sh の運用実証**: project.yml の MARKETING_VERSION のみ手動更新、Build 番号は引数で指定 (`./scripts/upload-testflight.sh 37`)、entitlements lint + xcodegen + archive + export + ASC upload を自動化、Build 37 / v0.1.2 が `Upload succeeded` で App Store Connect 到達

### 実装実績

- **変更ファイル合計**: 9 ファイル (PR #202: 7 / PR #203: 2)
  - PR #202 新規 6 ファイル: `CareNote/Services/TransferOwnershipService.swift` (Service + Error mapping、198 行) / `CareNote/Features/Settings/AccountTransferViewModel.swift` (state machine、94 行) / `CareNote/Features/Settings/AccountTransferView.swift` (UI、195 行) / `CareNoteTests/TransferOwnershipServiceTests.swift` (mapping + transient 14 ケース) / `CareNoteTests/AccountTransferViewModelTests.swift` (state machine + 二段階 confirm 13 ケース) / `CareNoteTests/AccountTransferViewMessageTests.swift` (UI 文言 12 ケース)
  - PR #202 編集: `CareNote/Features/Settings/SettingsView.swift` (admin 限定 NavigationLink 追加)
  - PR #203: `project.yml` / `CareNote.xcodeproj/project.pbxproj` (MARKETING_VERSION 0.1.1 → 0.1.2 + CURRENT_PROJECT_VERSION 36 → 37)
- **テスト成長**: iOS 173 → **211** (+38)、新 suite 3 件 (TransferOwnershipError.map mapping / AccountTransferViewModel state machine / AccountTransferView.message(for:) mapping)
- **CI**: PR #202 初回 fail (Xcode 16.3 strict concurrency) → fix commit で green / PR #203 green
- **TestFlight upload**: Build 37 / v0.1.2、`Upload succeeded` + `EXPORT SUCCEEDED` (Firebase Firestore 系 dSYM 欠損 warning は既知)

### Quality Gate 運用 (Generator-Evaluator 分離 3 層 + 6 agent 並列レビュー)

- **`/simplify` 3 並列** (PR #202、5 ファイル以上): 採用 = callable 名 + region constant 化、`Equatable` `==` の `unknown` 比較規則コメント追加。見送り = dryRun/confirm DRY 化 (2 箇所のみ ROI 負)、Functions cache (SDK 内部 cache 済)、@ViewBuilder 統合 (admin 低頻度 UI で hot path でない)
- **Evaluator 分離プロトコル** (PR #202、5 ファイル + 新機能、`rules/quality-gate.md` 発動): HIGH 1 = checkbox リセット欠落 (機能バグ、本 PR 内修正 + 回帰テスト)、文言を AC に揃え、Sendable 明示、accessibilityLabel 追加。`runDryRun()` 開始時に `confirmCheckboxChecked = false` で二段階 confirm 安全性回復
- **`/review-pr` 6 agent 並列** (PR #202): code-reviewer / pr-test-analyzer / silent-failure-hunter / comment-analyzer / type-design-analyzer / code-simplifier。triage 基準 6 件全反映。保留 = ローカル invalidArgument semantics (rating 7/80 だが enum case 拡張で複雑化)、parseCounts internal 化テスト (本 PR スコープ拡大)

### Issue Net 変化

セッション開始時 open **7** → 起票 #201 (+1、CLAUDE.md triage 基準 #5 ユーザー明示指示) → close #201 (-1、PR #202 merge で auto-close) → 終了時 open **7** (net **0**)

> **Net 0 の意味**: ユーザー要請「テナント内ドメイン自動加入 + アカウント引き継ぎ self-service」を起票 (#201)・実装 (PR #202)・close を**1 セッション内で完遂**したパターン。memory `feedback_issue_triage.md` 基準では Net ≤ 0 は進捗ゼロ扱いだが、本セッションは「Issue 化された機能要件の起票→完遂」+「Build 37 リリース upload まで実行」で実質的進捗あり。CLAUDE.md「Issue は net で減らすべき KPI」は「未解消 Issue を放置・量産しない」精神であり、起票即完遂はこの精神に反しない

### セッション内教訓 (handoff 次世代向け)

1. **Apple App Review 経緯の memory 化が必須**: 過去のリジェクト経緯 (Build 21-22 赤字エラー判定 → Guest Tenant 設計転換) は CareNote プロジェクトの設計判断の根本にあり、これを把握せず「TestFlight で全員配布すれば OK」「審査不要で即配布」と短絡判断する危険があった。`memory/project_carenote_app_review.md` で Build 別経緯 + 配布方式 + デモアカウント + 再発防止チェックリスト + 完全着地フロー (実装 → version bump → TestFlight upload → App Review 1-3 日 → Unlisted release) を集約
2. **SwiftUI View 内 static func は最初から `nonisolated`**: SwiftUI View struct は暗黙的に `@MainActor` 隔離 → static func も MainActor 隔離 → 非 MainActor テストから呼べない。ローカル Xcode (iOS 26.2 SDK) は警告のみで通るが CI Xcode 16.3 は error 化。pure function (state 非依存) には `nonisolated static func` を最初から明示する
3. **Evaluator は機能バグも検出する**: `/review-pr` の前段で Evaluator (`rules/quality-gate.md` 発動条件) を回したことで、preview 状態で再 dryRun 時の checkbox リセット欠落 (二段階 confirm 安全性違反) を実装の前提知識なしで検出。実装者の盲点を補正する効果。修正 + 回帰テストを同 PR 内で吸収
4. **TestFlight 90 日 expire は社員全員配布に不向き**: TestFlight Internal Testing は審査不要で即配布できるが 90 日で expire するため永続運用には不適切。CareNote のような社内 B2B アプリは App Store Unlisted Distribution (URL 招待制、App Review あり) が正解。ユーザー指摘「Testフライトなんかで社員全員に配布しないですよ。だってずっとつかえないでしょ」が正論
5. **PR/Issue 番号コメントの陳腐化リスク**: テストコメントに「Evaluator 検出 (#201)」「(Issue #201 受け入れ基準)」と書くと、Issue close 後・PR merge 後に文脈が失われる。CLAUDE.md「Don't reference current task/fix/callers」遵守、不変条件ベースの記述 (例: 「二段階 confirm の不変条件 (preview ∧ checkbox=true) が崩れる」) に書き換える
6. **upload-testflight.sh は Build 番号のみ自動 bump、MARKETING_VERSION は手動**: Apple の "Invalid Pre-Release Train" エラー回避のため MARKETING_VERSION の semver bump は必須だが script は触らない。version bump PR (project.yml + pbxproj sync) → merge → upload の順を runbook 化済 (PR #195 / PR #203 で実証済)

### CI の現状

- main `7e11b71` (PR #203 merge 後): post-merge iOS Tests 走行中 (Pre-merge は両 PR とも green)
- Pre-merge: PR #202 → Xcode 16.3 strict concurrency fix 後 green (sha 3a721a6) / PR #203 → green (sha 7b1e0b6)

### 次セッション推奨アクション (優先順)

「完全着地」残作業は基本ユーザー手動。Build 37 が App Review 通過 → Unlisted release 配布 → メンバー追加で smoke の流れ。

1. **🔥 Build 37 / v0.1.2 App Review 提出 (ユーザー手動)**: App Store Connect で Build 37 processing 完了 (10-30 分) を待ち、Build 37 を選択して App Review 提出。**Apple Review 経緯チェックリスト** (`memory/project_carenote_app_review.md`「次回審査時の留意点」) を提出前に確認: デモアカウント whitelist 維持 / エラー UI 赤字単色なし / admin 限定機能 demo-reviewer でテスト可能 / Sign in with Apple entitlement 維持
2. **App Review 通過後 Unlisted release (ユーザー手動)**: 通過 (1-3 日想定、リジェクト時は理由分析 + 修正版再提出) → App Store Connect で Build 37 を Unlisted release。**完全着地達成**
3. **Issue #111 Phase 0.9 close 判断**: Build 37 配布後に新メンバー (`@279279.net`) を 1 名招待し allowedDomains 自動加入 + admin UI でアカウント引き継ぎ self-service の実機 smoke 完了 → close
4. **#192 Phase B/C** (Cloud Storage orphan cleanup): dev 実 trigger smoke + prod deploy + runbook 整備 (既存 handoff 推奨アクション継続)
5. **#178 Stage 2 GHA + WIF** / **#105 deleteAccount E2E** / **#92 / #90 Guest Tenant** / **#65 Apple × Google account link**

### 関連リンク

- [PR #202 merged](https://github.com/system-279/carenote-ios/pull/202) — Issue #201 transferOwnership iOS admin UI (ADR-008 Phase 2)
- [PR #203 merged](https://github.com/system-279/carenote-ios/pull/203) — Build 37 / v0.1.2 bump
- [Issue #201 CLOSED](https://github.com/system-279/carenote-ios/issues/201)
- `~/.claude/memory/project_carenote_app_review.md` (グローバル) — Apple App Review 経緯の集約
- ADR-008 Phase 2 (本セッションで実装完遂)

---

# Handoff — 2026-04-25 朝〜午後セッション: PR #191 follow-up 3 件 (#194 / #193 / #192) 完遂 + Cloud Function dev deploy

## ✅ Issue #194 / #193 close (PR #197 / #198 merge) + Issue #192 Phase A merge (PR #199) + dev deploy ACTIVE

前セッション (2026-04-25 未明) handoff の推奨 follow-up 3 件すべてを完遂。各 PR で Quality Gate 3 層（`/simplify` 該当時 + `/review-pr` 5-6 agent 並列 + Evaluator 分離プロトコル）通過。Issue #192 は Phase A (impl + test) を merge し dev deploy も成功させ、Phase B/C tracking のため Issue を再 open 維持。

### セッション成果サマリ

| PR | Issue | 内容 | merge 順 |
|----|-------|------|----------|
| **#197 (merged)** | **#194** | RecordingListViewModel polling の silent catch を transient/permanent 分類で logger 可視化 | 1 |
| **#198 (merged)** | **#193** | Firestore delete error 分類 (permissionDenied / notFound / retryable) + UI alert 分岐 (再試行ボタン) | 2 |
| **#199 (merged)** | **#192 (Phase A)** | Cloud Function `onRecordingDeleted` (Firestore trigger) で Cloud Storage orphan audio cleanup | 3 |

### 主要判断のハイライト

- **#194 polling silent catch**: PR #197 で `FirestoreError.isTransient` を service 層に追加 (gRPC code 4/8/14 = deadlineExceeded / resourceExhausted / unavailable で transient 判定)。`pollProcessingRecordings` の `// ポーリングエラーは静かに無視` を撤廃し、transient → `logger.info` (silent retry 維持)、permanent → `logger.error` (DI/権限/schema drift 等の actionable failure)、save 失敗 → `logger.error` + `errorMessage` で UI surface に分類。`/review-pr` で SDK 公開定数 (`FirestoreErrorDomain` + `FirestoreErrorCode.<name>.rawValue`) 使用と `isTransient` 集約を採用、ハードコード `"FIRFirestoreErrorDomain"` + magic 4/8/14 を排除。
- **#193 delete error 分類**: PR #198 で `FirestoreError` に `.permissionDenied` / `.notFound` case 追加、`static func map(_:)` で NSError → case 変換。`RecordingDeleteError` に `.permissionDenied` / `.retryable(recordingId: UUID, underlying: FirestoreError)` 追加。`recording: RecordingRecord` ではなく `UUID` を保持するのは SwiftData `@Model` が non-Sendable で enum の Sendable 準拠を崩すため。VM の `static func resolveDeleteError` で notFound → idempotent success (return) / permissionDenied → throw `.permissionDenied` / transient → throw `.retryable` / その他 → 原 FirestoreError rethrow に分岐。View で 2 つの alert (errorMessage 用 + deleteError 用) を併置、retryable のみ「再試行」ボタン。`presentDeleteError(_:)` helper で onDelete / retry 両経路の state 更新を統合 + 相互排他化 (alert 同時表示 race 防止)。
- **#192 Phase A Cloud Function**: PR #199 で `exports.onRecordingDeleted = onDocumentDeleted("tenants/{tenantId}/recordings/{recordingId}", handleRecordingDeleted)` 追加。既存 `parseGsUri` helper を再利用、`getStorage().bucket().file().delete({ ignoreNotFound: true })` で Storage object 削除。**失敗時は throw せず error log のみ** (Firebase v2 trigger は throw すると exponential backoff 退避ループに入る、orphan は手動 cleanup script で回収可能)。`deleteAccount` Callable との二重実行は `ignoreNotFound: true` で冪等。handler を `_handleRecordingDeleted` として named export (test 用、`firebase-functions-test` の `makeDocumentSnapshot` が他 test の `getFirestore` mock と干渉する問題を回避するため)。`/review-pr` 反映で parseGsUri null log を warn → error に昇格 (data corruption は actionable)。
- **#192 Phase B dev deploy**: `firebase deploy --only functions:onRecordingDeleted -P default` 成功 (carenote-dev-279 / asia-northeast1 / nodejs22 2nd Gen / state ACTIVE / event type `google.cloud.firestore.document.v1.deleted` / path pattern `tenants/{tenantId}/recordings/{recordingId}`)。
- **Phase B 実 trigger smoke 残**: ADC user (system@279279.net) は dev Firestore の test tenant で member 権限を持たないため admin SDK での test doc create が `PERMISSION_DENIED` (code 7)。SA key 同梱は CLAUDE.md「禁止」事項。`gcloud firestore documents create` も subcommand 不在で不可。実 trigger 発火確認は次セッションで (a) gcloud admin token + REST API、(b) dev TestFlight build を別途用意して実機操作、(c) prod TestFlight Build 37 配布後に Cloud Console で確認のいずれかを選択。
- **Issue #192 reopen**: PR #199 commit message の `Closes #192 (Phase A only; ...)` で GitHub が auto-close したが、Phase B/C 残のため `gh issue reopen 192` で再 open。Phase C 完了後に手動で close する方針。

### 実装実績

- **変更ファイル合計**: 9 ファイル (PR #197: 1+1=2 / PR #198: 5 / PR #199: 2)
  - PR #197: `CareNote/Features/RecordingList/RecordingListViewModel.swift` (`pollProcessingRecordings` 改修 + `logPollingFetchError` helper) / `CareNote/Services/FirestoreService.swift` (`FirestoreError.isTransient` 追加) / `CareNoteTests/FirestoreErrorTests.swift` (新規 7 ケース)
  - PR #198: `FirestoreService.swift` (FirestoreError case 追加 + `map(_:)`) / `RecordingListViewModel.swift` (RecordingDeleteError case 追加 + `resolveDeleteError`) / `RecordingListView.swift` (alert 分岐 + `presentDeleteError`) / `FirestoreErrorTests.swift` (FirestoreErrorMapTests suite + 7 ケース) / `RecordingListViewModelTests.swift` (resolveDeleteError 5 + round-trip 2 ケース)
  - PR #199: `functions/index.js` (handleRecordingDeleted + onRecordingDeleted export + deleteAccount docstring) / `functions/test/on-recording-deleted.test.js` (新規 9 ケース、console spy + 非 string test 含む)
- **テスト成長**: iOS 145 → **173** (+28、PR #197: +12 / PR #198: +14 (round-trip 2 含む) / 既存 retryable 関連 +2) / functions 36 → **44** (+9 - 1 = +8、PR #199 で 9 追加)
- **CI**: 3 PR 全 pass (iOS Tests + Functions & Rules Tests)

### Quality Gate 運用 (Generator-Evaluator 分離 3 層 + 6 agent 並列レビュー)

- **/simplify** (3 ファイル以上時): 3 agent (reuse / quality / efficiency) 並列で改善提案
  - PR #197: 5 ファイル変更で実行 → SDK 定数化、isTransient 集約、errorMessage clear、コメント整理を採用
  - PR #198: 5 ファイル変更で実行 → resolveDeleteError signature 簡素化、alert helper 統合、switch 明示 case 化、未使用 isRetryable 削除を採用
  - PR #199: 2 ファイル変更で skip
- **/review-pr** 5-6 agent 並列 (code-reviewer / pr-test-analyzer / silent-failure-hunter / comment-analyzer / type-design-analyzer / code-simplifier): 全 PR で実行、Important / Rating 7+ を反映、Rating 5-6 は triage 基準 (rating ≥ 7 + confidence ≥ 80) 未達のため見送り。
- **Evaluator 分離** (5 ファイル以上 or 新機能、`rules/quality-gate.md` 発動条件):
  - PR #198: APPROVE (全 AC PASS、HIGH 問題なし、MEDIUM 2 + LOW 1 は別 PR refactor / Evaluator 理解誤り)
  - PR #199: APPROVE (全 AC PASS、HIGH 問題なし、LOW 3 件はすべて反映済)

### Issue Net 変化

セッション開始時 open **9** → close #194/#193 (-2) → reopen #192 (+1 net 0) → 終了時 open **7**（net **-2**）

| 動き | Issue | 件数 | Open 数推移 |
|------|------|------|------------|
| 開始時 | — | — | 9 |
| PR #197 merge → #194 auto-close | -1 | -1 | 8 |
| PR #198 merge → #193 auto-close | -1 | -1 | 7 |
| PR #199 merge → #192 commit message で auto-close | -1 | -1 | 6 |
| #192 reopen (Phase B/C tracking) | +1 | +1 | 7 |
| **終了時** | — | **net -2** | **7** |

> **Net -2 達成**: CLAUDE.md「Issue は net で減らすべき KPI」を満たす。新規 Issue 起票なし。triage 基準 (rating ≥ 7 + confidence ≥ 80) 未達の review agent 提案 (Q1 dual-state / Q8 classify placement / type-design phantom type / etc.) は PR コメント / 見送り判断で処理し、Issue 化していない。

### セッション内教訓 (handoff 次世代向け)

1. **`firebase-functions-test` の `makeDocumentSnapshot` は他 test の admin SDK mock と干渉する**: `delete-account.test.js` が `getFirestore` を上書きする状態で `makeDocumentSnapshot` を呼ぶと `firestoreService.snapshot_ is not a function` で fail。回避策は handler を `_handleRecordingDeleted` として named export し、test では event 互換オブジェクト (`{ data: { data: () => ... }, params: ... }`) を直接渡して handler を call。`firebase deploy` は `CloudFunction` wrap 済 export のみ trigger 登録するため、plain function の named export はデプロイ対象外で安全。
2. **Sendable 維持のため enum associated value に `RecordingRecord` (SwiftData @Model) を持たせない**: PR #198 初回実装で `.retryable(recording: RecordingRecord, underlying: any Error)` としたら build error。`UUID + FirestoreError` (Sendable) に変更、View 側で `recordings.first(where: { $0.id == recordingId })` で対象を引き直す pattern が安全。
3. **`/review-pr` Evaluator の指摘は「実装の前提知識なし」評価のため誤認も含む**: PR #198 で Evaluator が「outer catch で FirestoreError 二重ログ発生」と指摘したが、Swift do-catch 仕様では `catch let firestoreError as FirestoreError` 内の throw は外側の `catch {}` に再 match しない (call site は呼び出し元へ propagate)。指摘を鵜呑みにせず Swift 仕様で検証してから採否判断。
4. **Cloud Function trigger 内では throw しない**: Firebase v2 trigger は throw すると exponential backoff で retry し続け、永久ループ + log spam + コスト増。Storage delete 失敗は `console.error` でログのみ残し、orphan は `scripts/delete-empty-createdby.mjs` 系で手動回収する設計が pragmatic。
5. **dev での実 trigger smoke は ADC user 権限の壁で困難**: `gcloud auth application-default login` で得た user credentials は Firestore security rules 適用下で member 権限なしテナントへの書き込み不可。SA key 同梱禁止の制約下で smoke する手段は (a) admin token + REST API、(b) dev iOS build 用意、(c) prod 配布後 Cloud Console 確認のいずれか。次セッションで判断。
6. **Issue close trigger としての commit message `Closes #X` は強力**: PR 本文から `Closes` を外しても commit message に残っていれば auto-close する。Phase 分割タスクで「auto-close したくない」場合は commit message から `Closes` を抜き、PR 本文には `Refs #X` のみ記載するのが正解 (本セッション #192 で auto-close → reopen 対応が発生)。

### CI の現状

- main `d5e20dc` (PR #199 merge 後): Functions & Rules Tests pass (1m3s)
- 直近 3 PR 全 CI pass

### 次セッション推奨アクション (優先順)

Issue #192 Phase B/C 完遂が最優先。dev deploy 済 + smoke 残のため、smoke 経路と prod deploy 順序の判断から再開。

1. **🔥 #192 Phase B 実 trigger smoke** (最優先): 以下のいずれかで dev `onRecordingDeleted` の発火確認
   - (a) gcloud admin token + Firestore REST API (`firestore.googleapis.com/v1/.../documents:commit`) で test doc create + delete、Cloud Function log で `[onRecordingDeleted] storage object deleted` を確認 (10-15 分、不確実)
   - (b) dev TestFlight build を用意 → 実機録音 + 削除で smoke (1-2h、build/upload 含む)
   - (c) Phase C を先行し prod TestFlight Build 37 配布後に Cloud Console で audio object 消滅確認 (Phase B/C 順序入替、prod risk あり)
2. **#192 Phase C: prod deploy + runbook** (Phase B smoke 後): `firebase deploy --only functions:onRecordingDeleted -P prod` + `docs/runbooks/` に Cloud Function 失敗時の手動 cleanup 手順 (`scripts/delete-empty-createdby.mjs` の使い方) を追記。完了後 Issue #192 を手動 close。
3. **TestFlight Build 36 / v0.1.1 ユーザーフィードバック反映**: 前セッション uploaded、本セッション削除動作確認 OK 報告済。新規バグ発覚時は triage 後に対応。
4. **#178 Stage 2 GHA + WIF 運用基盤** (enhancement, P2、ADR-009 follow-up): prod Firestore CI/CD 自動化基盤。#105 / #111 の前提にもなる。
5. **#105 deleteAccount E2E テスト** (Firebase Emulator Suite、I-Cdx-1)
6. **#111 Phase 0.9 prod tenants/279.allowedDomains 有効化**: TestFlight Build 36 ユーザー確認後に Apple ID × Google 連携を除く CRUD / Guest / allowedDomains 3 点確認できれば close 判断
7. **#92 / #90 Guest Tenant 関連** (enhancement)、**#65 Apple × Google account link** (enhancement)

### 関連リンク

- [PR #197 merged](https://github.com/system-279/carenote-ios/pull/197) — Issue #194 polling silent catch logger 可視化
- [PR #198 merged](https://github.com/system-279/carenote-ios/pull/198) — Issue #193 Firestore delete error 分類 + UI alert
- [PR #199 merged](https://github.com/system-279/carenote-ios/pull/199) — Issue #192 Phase A Cloud Function impl
- [Issue #192 reopened](https://github.com/system-279/carenote-ios/issues/192) — Phase B/C tracking
- [dev Firebase Console](https://console.firebase.google.com/project/carenote-dev-279/overview) — onRecordingDeleted ACTIVE 確認
- [Issue #194 CLOSED](https://github.com/system-279/carenote-ios/issues/194)
- [Issue #193 CLOSED](https://github.com/system-279/carenote-ios/issues/193)

---

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

