---
name: CareNote iOS App Review 経緯と運用ルール
description: CareNote iOS プロジェクトの Apple App Review 審査経緯（Build 21-38）、リジェクト原因と教訓、Unlisted 配布運用、デモアカウント、再発防止チェックリスト、提出操作 runbook
type: project
originSessionId: 63efdbb5-99c6-434b-a4d4-2f461d7f2ba1
---
# CareNote iOS — Apple App Review 全経緯

プロジェクト最重要情報の一つ。Build 番号別の審査経緯、リジェクト教訓、配布運用、提出操作 runbook を集約。

## Build 別審査経緯（時系列）

> **2026-04-26 訂正**: Build 35 を v0.1.0 と記録していたが、App Store Connect 上は **v1.0** で配信中であることが判明。表示が正。upload-testflight.sh で archive 時に渡された MARKETING_VERSION と App Store Connect 上の表示値が乖離した可能性あり。

| Build | MARKETING_VERSION (App Store Connect) | 提出日 | ステータス | リジェクト/通過理由 |
|-------|---------------------------------------|--------|-----------|-------------------|
| 21 | 1.0 | 2026-04-02 | REJECTED | Guideline 4.8 (Sign in with Apple 未実装) + 2.1(a) (デモアカウント未提供) |
| 22 | 1.0 | 2026-04-03 | REJECTED | Guideline 2.1(a): Apple Sign-In 時の**赤字エラー表示**を「バグ」と判定（文言案内は読まれず） |
| 32 | 1.0 | — | (設計転換契機) | 「赤字=バグ判定」を機能設計で解く方針に転換 → ADR-007 (Guest Tenant 自動プロビジョニング) |
| 33 | — | — | APPROVED 推定 | Guest Tenant 対応 (PR #87) で Sign in with Apple フロー通過、配布開始 |
| **35** | **1.0** | **2026-04-16** | **APPROVED** | **2026-04-18 から App Store Unlisted で公開中（自社メンバー使用中）** |
| 36 | 0.1.1 | — | TestFlight upload のみ | PR #191/#195 (delete sync + version bump)、未提出 |
| 37 | 0.1.2 | — | TestFlight upload のみ、**提出不可** (ダウングレード) | PR #202/#203、v1.0 配信中につき v0.1.2 < v1.0 で拒否される |
| **38** | **1.0.1** | **2026-04-26** | **APPROVED → Unlisted 配信中** (2026-04-27) | PR #205 で v0.1.2 → v1.0.1 再 bump、Phase B (transferOwnership iOS admin UI) + bug fix 統合。Submission ID `736694f6-01af-4b69-8d28-8420cba31aa6`。提出から約 24h で APPROVED → 同日 Unlisted release |

## リジェクト教訓（再発防止）

### 1. 赤字エラー表示 = バグ判定（最重要）
- **問題**: いくら丁寧な案内文を書いても、赤字色表示だけで審査員は「機能しない」と判定
- **解決パターン**: 文言で誤解を解こうとせず、**機能設計で解く**
- **具体例**: 未登録 Apple ID をエラー拒否 → Guest Tenant 自動プロビジョニング（ADR-007）
- **将来チェック**: 新画面追加時、エラー系 UI が赤字単色表示になっていないか検証

### 2. デモアカウント必須（Guideline 2.1(a)）
- **招待制 / Unlisted アプリは審査員用テストアカウント不在 → 即リジェクト**
- 現在のデモ: `demo-reviewer@carenote.jp` / `CareNote2026Review!` / tenant 279 admin
  - Auth uid: `hwwDRF6XgidoHjyoCShQvx8R2v43`
  - Firestore: `tenants/279/whitelist/D8a63ZM5iijgeBSIbRSQ`
- App Store Connect の Review Notes に明示済（`docs/appstore-metadata.md`）
- **Phase 0.9 等の Rules 変更時は whitelist 登録維持を確認**（Phase 0.9 前提ゲート）

#### 2026-04-26 教訓: 権限判定は **二系統** あり、提出前に両方確認必須

Build 38 提出時、memory には「demo-reviewer は tenant 279 admin」と記述されていたが、実態は両系統とも `member` で Phase B (admin 限定機能) のテスト不能状態だった。Apple 審査員が demo-reviewer でログインしても admin メニュー自体が表示されない構造。

**権限判定の二系統**（`firestore.rules` の `isAdmin()` 参照）:

| データ場所 | 役割 | 確認方法 |
|----------|------|---------|
| `tenants/279/whitelist/{id}` の `role` | 事前登録時の意図 / admin UI 表示用 | Firestore REST API `runQuery` |
| **Firebase Auth custom claim `role`** | **Rules の実権限判定ソース** | Identity Toolkit API `accounts:lookup` |

**Rules 実装** (`firestore.rules` L14-17):
```
function isAdmin(tenantId) {
  return isTenantMember(tenantId)
    && request.auth.token.role == 'admin';   // ← custom claim
}
```

iOS 側 (`AuthViewModel.swift`) は ID Token の `claims["role"]` を見て `isAdmin` を判定 → SettingsView の admin メニュー表示制御に使用。

**確認コマンド**:

```bash
TOKEN=$(CLOUDSDK_ACTIVE_CONFIG_NAME=carenote-prod gcloud auth print-access-token)

# 1. Firestore whitelist の role
curl -sS -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  "https://firestore.googleapis.com/v1/projects/carenote-prod-279/databases/(default)/documents/tenants/279:runQuery" \
  -d '{"structuredQuery":{"from":[{"collectionId":"whitelist"}],"where":{"fieldFilter":{"field":{"fieldPath":"email"},"op":"EQUAL","value":{"stringValue":"demo-reviewer@carenote.jp"}}}}}'

# 2. Firebase Auth custom claim
curl -sS -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "x-goog-user-project: carenote-prod-279" \
  "https://identitytoolkit.googleapis.com/v1/projects/carenote-prod-279/accounts:lookup" \
  -d '{"email":["demo-reviewer@carenote.jp"]}'
```

**復旧方法**（Build 38 提出前に実施した W1/W2）:

```bash
# W1: Auth custom claim 更新
curl -sS -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "x-goog-user-project: carenote-prod-279" \
  "https://identitytoolkit.googleapis.com/v1/projects/carenote-prod-279/accounts:update" \
  -d '{
    "localId": "hwwDRF6XgidoHjyoCShQvx8R2v43",
    "customAttributes": "{\"tenantId\":\"279\",\"role\":\"admin\"}"
  }'

# W2: Firestore whitelist role 更新
curl -sS -X PATCH \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  "https://firestore.googleapis.com/v1/projects/carenote-prod-279/databases/(default)/documents/tenants/279/whitelist/D8a63ZM5iijgeBSIbRSQ?updateMask.fieldPaths=role" \
  -d '{"fields":{"role":{"stringValue":"admin"}}}'
```

### 3. Sign in with Apple は必須（Guideline 4.8）
- 第三者ログイン提供時は Apple Sign-In も提供必須
- 削除不可、機能後退禁止

## 配布方式

### App Store Unlisted Distribution（本番運用）
- **現在配布中: Build 38 / v1.0.1**（2026-04-27 開始、Build 35 / v1.0 から自動更新で配布範囲継承）
- **Unlisted URL**: `https://apps.apple.com/us/app/carenote-ai/id6760607218`（App ID `6760607218`、v1.0 から不変・継承）
- App Store 検索には出ない、URL 配布制（招待制業務アプリ向け）
- **再 App Review 必要**: 新版配布の度に審査通過必須（ただし Unlisted 配布許可自体は再申請不要・下記参照）
- 新メンバー追加時の追加審査は不要（同 build を URL から download）
- **Apple Vision Pro 配信**: チェック済（v1.0 から自動継承、互換アプリとして配信可能）

### Unlisted 新版リリース手順（再申請不要・公式仕様）

**MUST**: 一度 Unlisted 配布許可を取得した App ID 配下の新版は、**自動的に Unlisted のまま配信される**。Apple への再申請メール (`AppStoreUnlisted@apple.com`) 送信は **不要**。

公式仕様（[Apple Developer Support — Unlisted App Distribution](https://developer.apple.com/support/unlisted-app-distribution/)）:
> Once your app's unlisted distribution request is approved, the distribution method changes to Unlisted in the Pricing and Availability section, and **future versions of your app will remain unlisted**.
> Future submissions under the same App ID remain unlisted automatically.

**新版リリース手順**（Build 38 / v1.0.1 release で確認）:

1. 新 build を upload + App Review 提出 → APPROVED 待ち（手動リリース設定で提出）
2. APPROVED 後、App Store Connect 配信タブで「{version} デベロッパによるリリース待ち」状態を確認
3. 左サイドバー「価格および配信状況」で配信方法 = **Unlisted** が維持されていることを確認
   - 「アプリの配信方法」欄に「リンクにアクセス可能なユーザのみが App Store でアプリを見つけたり、ダウンロードできます。」と表示されていれば Unlisted
   - 「非表示アプリのURL」欄に v1.0 と同じ Unlisted URL が表示されていれば継承成功
   - 「保存」ボタンが grey-out 状態 = 設定変更不要（既に正しい状態）
4. 「配信」セクションの新バージョン → 右上 **「このバージョンをリリース」** をクリック
5. 既存 Unlisted URL で新版が配信開始、既存ユーザーには App Store 自動更新で配信

**過去の誤解（自戒）**: 2026-04-27 セッションで「Unlisted release は別フロー、Apple へ申請メール送信が必要」と Claude が誤って案内。実際は同 App ID 配下なら自動継承（公式仕様）。**外部サービスの手順を答える前に必ず公式ドキュメントで確認**（rules/tech-selection.md §1）。

### TestFlight（開発・smoke 用、永続運用には不向き）
- ビルド 90 日 expire、社員全員配布には不適切
- 開発時の動作確認に使用

### 配布制約
- 同一 MARKETING_VERSION の再 upload 不可（"Invalid Pre-Release Train" エラー）
- → semver patch bump 必須
- 同時に複数バイナリ審査不可（提出中の build を取り下げない限り次は出せない）
- **新リリース > 旧リリース (semver) 必須**: ダウングレードは App Store Connect で受付不可、または App Review でリジェクト
  - 例: 現行 v1.0 → 次は最低 v1.0.1 / v1.1 / v2.0 等
  - **MARKETING_VERSION bump 時は必ず App Store Connect 側の現行 release version を確認** (推測ではなく実画面で確認、Image スクリーンショット or `履歴` セクション)
  - 教訓: 2026-04-26 セッションで Build 37 を v0.1.2 として upload したが、現行 v1.0 配信中のため提出不可と判明 → Build 38 / v1.0.1 に再 bump (PR #205)

## 次回審査提出時のチェックリスト

提出前に必ず確認:

- [ ] MARKETING_VERSION を semver bump（前回審査通過版から、**必ず App Store Connect 上の現行 version を画面で実確認**）
- [ ] CURRENT_PROJECT_VERSION (build番号) もインクリメント
- [ ] Sign in with Apple entitlement が含まれている（`upload-testflight.sh` の lint で自動検証）
- [ ] デモアカウント `demo-reviewer@carenote.jp` が **両系統で admin** であること:
  - [ ] Firestore: `tenants/279/whitelist/D8a63ZM5iijgeBSIbRSQ` の `role: "admin"`（runQuery で確認）
  - [ ] Firebase Auth: customAttributes が `{"tenantId":"279","role":"admin"}`（accounts:lookup で確認）
  - 不一致時は W1/W2 で復旧（上記「2026-04-26 教訓」の復旧コマンド参照）
- [ ] エラー表示 UI が赤字単色表示になっていない（新画面追加時）
- [ ] 新規追加した admin 限定機能が demo-reviewer (admin 権限) でテスト可能
- [ ] App Store Connect の Review Notes（appstore-metadata.md §審査メモ）にデモアカウント情報・新機能の使い方を記載
- [ ] App Store Connect 上で v1.0 から自動継承されない項目を v1.0.1 等の新バージョンページで個別記入:
  - [ ] このバージョンの最新情報 (What's New)
  - [ ] ビルド選択（新 build を紐付け）
  - [ ] App Store バージョンのリリース方法（**「手動でリリース」推奨** — Unlisted 配布のため自分のタイミングで release）
  - [ ] App Reviewに関する情報のメモ欄（v1.0 の旧簡略版を Phase X 込み完全版に置換）

## 「完全着地」の正しい依存関係

新機能（例: Phase 2 admin UI）を本番メンバーに使ってもらうための必須経路:

```
1. 機能実装 + iOS Tests CI green
2. project.yml の MARKETING_VERSION + build番号 bump（必ず App Store Connect 上の現行 version を実画面で確認）
3. ./scripts/upload-testflight.sh で TestFlight upload（自動 entitlements lint 含む）
4. App Store Connect で TestFlight build 選択 → App Store 提出（手動、リリース方法「手動でリリース」推奨）
5. App Review 通過待ち（通常 1-3 日、リジェクト履歴ある場合は再提出含めて 1-2 週）
6. APPROVED 後「価格および配信状況」で配信方法 = Unlisted 維持を確認（同 App ID 配下は自動継承、再申請メール不要）
7. 「配信」セクションの該当バージョン → 右上「このバージョンをリリース」で配信開始
8. 既存メンバーは App Store からアップデート、新メンバーは Unlisted URL から download
```

**所要期間目安**: 機能完成から本番配布まで最短 3-5 日、リジェクト発生時 +1 週

## 過去の重大インシデント

### 2026-04-23: Phase 0.5 Rules deploy で稼働中 Build 35 と不整合 → 業務停止
- **原因**: Rules を新 iOS コード前提で deploy、稼働中 Build 35 (古い iOS) との整合確認漏れ
- **影響**: 録音保存 → 文字起こし完了が permission-denied で失敗、自社業務停止
- **教訓**: Rules 変更時は「新 iOS × 新 Rules」だけでなく「**稼働中 Build × 新 Rules**」も検証必須
- **再発防止**: ADR-010 § 再発防止プロトコル、`docs/runbook/prod-deploy-smoke-test.md`

## App Store Connect 提出操作 runbook（暗黙知）

Build 38 / v1.0.1 提出時 (2026-04-26) に確立した手順。次回以降そのまま再現可能。

### 1. 全体フロー（3 段階）

```
[v1.0 (現行配信)]
     ↓ ① 新バージョン作成
[v1.0.1 提出準備中]
     ↓ ② 各項目入力 → 「保存」
[v1.0.1 (保存済)]
     ↓ ③ 「審査用に追加」 → 「提出物の下書き」に移動
[提出物の下書き (1)]
     ↓ ④ 「審査へ提出」
[v1.0.1 審査待ち]   ← 提出完了
```

ボタン名は紛らわしいが、**「審査用に追加」と「審査へ提出」は別ステップ**。前者で「下書き」リストに追加、後者で初めて審査キューに入る。

### 2. 新バージョン作成

App Store Connect 配信タブ → 左サイドバー「iOSアプリ」の右の「**+**」（青い ⊕ アイコン） → 「新規バージョン」 → バージョン番号入力（例: 1.0.1）→ 作成。

ダイアログから「新規バージョンまたはプラットフォーム」が出るが「**プラットフォームを追加**」（macOS / tvOS 等）と間違えないよう注意。

### 3. v1.0 から自動継承される項目（v1.0.1 で再入力不要）

- プレビューとスクリーンショット
- 概要（説明文）
- キーワード
- サポートURL
- バージョン（1.0.1 として作成時に確定）
- 著作権
- App Reviewに関する情報の **サインイン情報** (`demo-reviewer@carenote.jp`)
- App Reviewに関する情報の **連絡先情報**
- App Reviewに関する情報の **メモ欄の旧内容**（要置換）
- **Export Compliance（暗号化使用）の回答**（最終提出時に追加質問が出ない、確定済として扱われる）

### 4. v1.0.1 で必ず入力する項目

| 項目 | 内容 |
|------|------|
| このバージョンの最新情報 (What's New) | 新機能と修正内容を簡潔に記述。空のままだと提出不可 |
| ビルド | 「ビルドを追加」→ 該当 build の radio 選択 → 完了 |
| メモ（Review Notes） | 旧 v1.0 の簡略版が継承されるが、新機能（admin 限定機能等）のテスト手順を必ず追記。`docs/appstore-metadata.md §審査メモ` 全文を貼り付ける |
| App Storeバージョンのリリース | **「このバージョンを手動でリリースする」推奨**（Unlisted 配布なので、審査通過後に自分のタイミングで release） |

### 5. メモ欄の置換について（重要）

v1.0 から自動継承される旧メモ（簡略版）に、新メモを追加すると **append 動作になる**（連結された状態で保存される）ため、**全削除してから貼り付け**が必須。

**Playwright/JS で操作する場合**: React controlled component の textarea は単純な `fill()` だと append される場合がある。`page.evaluate()` で **native value setter** を使って value を直接書き換え、`dispatchEvent('input')` で React state を更新する:

```js
const nativeSetter = Object.getOwnPropertyDescriptor(
  HTMLTextAreaElement.prototype, 'value'
).set;
nativeSetter.call(textarea, '');                              // クリア
textarea.dispatchEvent(new Event('input', { bubbles: true })); // React state 同期
nativeSetter.call(textarea, newMemoContent);                  // 新規入力
textarea.dispatchEvent(new Event('input', { bubbles: true }));
```

メモ欄上限は 4,000 文字（残り文字数 status で確認）。Phase B 込み完全版で約 2,867 文字、残り 1,133 文字程度。

### 6. 審査提出後

```
左サイドバー: 1.0.1 審査待ち   ← この状態になっていれば提出成功
ダイアログ: 「1項目が提出されました 審査には最大48時間かかります」
URL: /apps/{appId}/distribution/reviewsubmissions/details/{submissionId}
```

通知メール（Apple → y.honda@279279.net）で結果が届く。通常 1-3 日。

### 7. Playwright で App Store Connect を操作する場合の暗黙知

- **既存ブラウザ (Safari/Chrome) のセッションは Playwright ブラウザに引き継がれない**: 通常は再ログイン + 2FA 必要
  - ただし Playwright MCP のブラウザは前回 Playwright セッションの cookie を保持する場合あり（今回は再ログイン不要だった）
- React controlled component への入力は、上記 §5 の native setter + dispatchEvent パターンが確実
- 最終操作（保存、審査用に追加、審査へ提出）の前に必ず **人間目視確認**（提出後の取り下げは手間がかかる）
- ラジオボタンは `getByRole('radio', { name: '...' })` でクリック可能、checked 状態は `radios.find(r => r.checked)` で確認
- ビルド選択ダイアログは radio クリック → 完了ボタンが enabled になったらクリック

## 関連リンク・参照

- [ADR-007 Guest Tenant for Apple Sign-In](../../Projects/279/carenote-ios/docs/adr/ADR-007-guest-tenant-for-apple-signin.md)
- [docs/appstore-metadata.md](../../Projects/279/carenote-ios/docs/appstore-metadata.md) — §審査メモ が提出時の貼り付け元
- [scripts/upload-testflight.sh](../../Projects/279/carenote-ios/scripts/upload-testflight.sh)
- Issue #67 (CLOSED): App Store Review リジェクト対応
- Issue #71 (CLOSED): upload-testflight.sh 入口で entitlements 検証
- Submission ID `736694f6-01af-4b69-8d28-8420cba31aa6`: Build 38 / v1.0.1（2026-04-26 提出 → 2026-04-27 APPROVED → 同日 Unlisted 配信開始）
- [Apple Developer Support — Unlisted App Distribution](https://developer.apple.com/support/unlisted-app-distribution/)（公式仕様: 同 App ID 配下の新版は自動 Unlisted 継承、再申請不要）
- Unlisted URL: `https://apps.apple.com/us/app/carenote-ai/id6760607218`

## SwiftUI / Swift 6 strict concurrency の落とし穴

### `@MainActor` 隔離の伝播

- SwiftUI `View` struct は **暗黙的に `@MainActor` 隔離**される (Swift 6+)
- View 内の `static func` も自動的に MainActor 隔離 → 非 MainActor テストから呼べない
- 解決: pure function (state 非依存) は `nonisolated static func` を明示

### ローカルと CI の Xcode バージョン差

- ローカル Xcode (iOS 26.2 SDK) は strict concurrency check が **警告のみ**で通ることがある
- CI (Xcode 16.3) は **error 化**して build 失敗
- 教訓: SwiftUI View 内の static func は最初から `nonisolated` を付ける、または非 View struct に切り出す
- 事例: PR #202 で `AccountTransferView.message(for:)` がローカル PASS / CI FAIL → `nonisolated static func` で修正 (commit 3a721a6)

## テナント加入動線 (allowedDomains + whitelist 併存設計、2026-04-27 反映)

prod tenant `279` で `allowedDomains = ["279279.net"]` 有効化済 (2026-04-23 完了)、Build 38 / v1.0.1 配信中。「ドメインだけで入れる」状態は技術的に実現済、実機 smoke test (Issue #111 close 条件) のみ pending。

### `beforeSignIn` 判定優先順 (`functions/index.js:41-73`)

```
1. whitelist 完全一致 → 実テナント + whitelist の role (admin/editor/member)
2. allowedDomains ドメイン一致 → 実テナント + role: "member" 固定
3. Apple Sign-In → demo-guest tenant
4. その他 → permission-denied
```

### whitelist は廃止せず併存（重要）

allowedDomains 有効化後も whitelist は以下用途で **必須として残存**:

- admin / editor 権限の付与（allowedDomains 経由は強制 `role: "member"`、admin 任命は whitelist 経由のみ）
- 非 `@279279.net` ドメインの例外メンバー追加（業務委託など）
- 既存メンバーの権限変更（member → admin 等）
- demo-reviewer のような審査用 admin の権限維持（whitelist + Auth custom claim 二系統一致が必須、2026-04-26 復旧事故参照）

### 運用上の変化（重要）

- 一般 `@279279.net` 社員: whitelist 不要、初回ログインで自動 member 加入、whitelist サブコレクションには **記録されない**
- 「全メンバー一覧」が必要なら Firebase Auth users API で集計する設計が必要（whitelist 件数 ≠ メンバー総数）
- iOS `AccountTransferView.swift` の whitelist 件数表示は admin + 例外メンバー数のみで、実メンバー数とは乖離する

### Phase 0.9 (Issue #111) の現状

- prod 技術設定: 2026-04-23 21:00 JST 完了 (SA impersonation + Firestore REST API、ADR-009 Stage 1)
- `beforeSignIn` Cloud Function: ACTIVE / GEN_2、直近 7d エラー 0 件 (2026-04-27 確認)
- 実機 smoke test: 新規 `@279279.net` 社員ジョイン時に自然観測 (B2 ポストポーン、Issue #111 open 維持)

**close 条件** (元 AC 全 6 項目、RUNBOOK `docs/runbook/phase-0-9-allowed-domains.md` の 2026-04-27 エントリに観測コマンド埋め込み済):
- (allowedDomains 正常系) 新規 `@279279.net` 社員初回 Google Sign-In 成功
- (allowedDomains 正常系) Cloud Logging で `beforeSignIn` の allowedDomains match 経路確認
- (allowedDomains 正常系) Auth user の `customClaims.tenantId === "279"` / `role === "member"` 反映確認
- (allowedDomains 正常系) `tenants/279/whitelist` に当該 entry が **存在しない** こと（allowedDomains 経由を担保）
- (Apple Guest 経路) 許可外ドメイン × Apple Sign-In が `demo-guest` 振り分け（Build 33 以降通過実績ありで実質充足扱い可、次回 App Store Review 提出時の審査員操作で事実上検証）
- (既存ログイン非破壊) 既存 `@279279.net` 社員のログインが allowedDomains 有効化後も継続成功（直近 7d Cloud Logging エラー 0 件で実質確認済）

### 比喩で表現

- **Before** (allowedDomains 未設定): 招待制レストラン（リストにある人だけ入れる）
- **After** (allowedDomains 有効、現状): 社員証で入れるオフィス + VIP リスト（社員証 = `@279279.net`、VIP リスト = whitelist で role 指定）

VIP リスト（whitelist）はなくならず、特別待遇（admin 権限）の付与と社員以外の招待用に残る。

## 更新履歴

- 2026-04-25: 初版作成（Build 35 配布中、Build 36 TestFlight upload 済、Phase B 実装着手前）
- 2026-04-26: SwiftUI / Swift 6 strict concurrency の落とし穴セクション追加（PR #202 で発見）
- 2026-04-26 (2nd): **Build 別 version 訂正** (Build 35 = v1.0、v0.1.0 ではない) + ダウングレード回避ルール追加。Build 37 提出不可判明 → Build 38 / v1.0.1 として再 upload
- 2026-04-26 (3rd): **Build 38 / v1.0.1 App Review 提出反映** (Submission ID `736694f6-01af-4b69-8d28-8420cba31aa6`)。demo-reviewer 権限の二系統（whitelist + Auth claim）不整合事故と W1/W2 復旧の記録、提出操作 runbook 追加（3 段階フロー、自動継承項目、メモ欄置換の React state 注意、Playwright 操作暗黙知）
- 2026-04-27: **Build 38 / v1.0.1 APPROVED → Unlisted 配信開始**。Unlisted URL を明示記載 (`https://apps.apple.com/us/app/carenote-ai/id6760607218`)。Unlisted 新版リリース手順（再申請不要・公式仕様）セクション追加。「完全着地」フローを Unlisted 仕様準拠に再番号 (6→6/7/8)。過去の誤解（Claude が「再申請メール必要」と誤案内）を自戒として記録
- 2026-04-27 (続報 2): **Phase 0.9 (allowedDomains) 状態確認 + whitelist 運用変化セクション追加**。prod 設定は 2026-04-23 完了済、`beforeSignIn` 直近 7d エラー 0 で健全。実機 smoke test は新規 `@279279.net` 社員ジョイン待ち (B2 ポストポーン、Issue #111 open 維持)。「テナント加入動線 (allowedDomains + whitelist 併存設計)」セクション新設で whitelist 概念は admin 任命・例外管理のため残存することを明示、運用変化（一般社員は whitelist に記録されない → 全メンバー一覧は Auth users API 経由で集計）を整理
