# Handoff — 2026-04-27 続報セッション 2: Phase 0.9 (allowedDomains) 状態確認 + Issue #111 close 条件明確化

## ✅ Phase 0.9 prod 設定 (2026-04-23 完了済) を再確認 + 実機 smoke test を社員ジョイン待ちでポストポーン継続

ユーザーから「内部のアプリリンクを知る社員はテナント内のドメインなら誰でも入れるか?」の確認質問を受け、Issue #111 (Phase 0.9: allowedDomains 有効化) を再評価。RUNBOOK の実施ログから prod 設定が **2026-04-23 21:00 JST に完了済** であること、かつ前提フェーズ (Phase -1/0/0.5/1/Node 22) もすべて prod deploy 済であることを確認。残作業は実機 smoke test の AC 検証のみと判明。

read-only verify で prod 技術設定の健全性 (`allowedDomains = ["279279.net"]` 維持 / `beforeSignIn` Cloud Function ACTIVE / 直近 7d エラー 0) を確認。実機 smoke test は新規 `@279279.net` 社員ジョイン時に自然観測する方針 (B2 ポストポーン) を確定し、Issue #111 に close 条件を明示してコメント追記、open 維持。あわせてユーザー質問「ホワイトリストの概念がなくなる?」に対し、`functions/index.js:41-73` の `beforeSignIn` 分岐確認結果から「whitelist は admin 任命・例外管理のために必須として残存、運用上の変化は一般社員が whitelist に記録されなくなる点」を明確化。

### セッション成果サマリ

| 変更 | リポジトリ | 内容 | 状態 |
|----|----------|------|------|
| **本 PR** | `system-279/carenote-ios` | `docs/runbook/phase-0-9-allowed-domains.md` 実施ログに 2026-04-27 確認エントリ追加 + `docs/handoff/LATEST.md` 続報セッション 2 追記 | 🔵 open |
| **GitHub Issue #111** | `system-279/carenote-ios` | prod 設定健全性確認 + close 条件明確化コメント | コメント追加 |
| **memory PR (別 push)** | `~/.claude` | `memory/project_carenote_app_review.md` に whitelist 運用変化セクション追加 | 後続 push |

### 主要判断のハイライト

- **「設定が未完了」と誤認していた状況を訂正**: ユーザー側で「ドメインだけで入れる状態にしたい」「まだできていないことに驚き」とのフィードバック。Issue #111 が open のため未完了と推定して `/impl-plan` 起動 → 実態は prod 設定 2026-04-23 完了済、Issue が open のままだったのは実機 smoke test 待ちのため。Issue タイトル「Phase 0.9: prod allowedDomains 有効化」が AC 全部を含む粒度のため、ステータス把握に runbook 実施ログまで遡る必要があった（次世代教訓: catchup で Issue タイトルだけでなく関連 RUNBOOK の実施ログまで遡る）
- **B2 ポストポーン継続を判定**: A1 (whitelist 未登録 `@279279.net` 社員のジョイン予定あり) + B2 (社員ジョイン待ち) を選択。能動テスト用アカウント `test-phase09@279279.net` 発行案 (B プラン) は採用せず、「次回新規社員ジョイン時に自然観測」が運用上のオーバーヘッド最小と判断。Issue #111 を open 維持し再開トリガーを RUNBOOK に明記
- **whitelist 概念は廃止せず併存**: ユーザーから「もはやホワイトリストという概念がなくなる?」の確認質問あり。`functions/index.js:41-73` の `beforeSignIn` 分岐確認の結果、whitelist は admin 権限付与・例外メンバー追加・権限変更のために必須として残存。allowedDomains 経由は強制的に `role: "member"`、admin 任命には依然として whitelist が必要。運用上の変化は「一般 `@279279.net` 社員は whitelist に記録されず Auth users にしか存在しない → 全メンバー一覧は Auth users API 経由で集計」
- **prod read-only verify はユーザー明示承認後に実行**: CLAUDE.md MUST に従い、prod project ID を含むコマンド (Firestore GET + Cloud Logging) はユーザー明示承認 (「実行承認」) を取得した後にのみ実行。書き込み操作は一切なし

### 実装実績

- **変更ファイル**: 2 ファイル (carenote-ios) + 1 ファイル (~/.claude memory)
  - `docs/runbook/phase-0-9-allowed-domains.md` — 実施ログ「2026-04-27 22:30 JST」セクション追記 (+45 行、健全性確認結果 + close 条件 + 観測コマンド 3 種)
  - `docs/handoff/LATEST.md` — 本セッション handoff を先頭に追加
  - `~/.claude/memory/project_carenote_app_review.md` — 「テナント加入動線 (allowedDomains + whitelist 併存設計)」セクション新設
- **prod 操作**: read-only 2 件 (Firestore GET + Cloud Logging) のみ、書き込みなし
- **GitHub Issue 操作**: #111 にコメント追加、open 維持
- **iOS コード変更**: なし (ドキュメント + memory のみ)

### Issue Net 計測

| 開始時 | 終了時 | Net |
|--------|--------|-----|
| 7 件 (#192/#178/#111/#105/#92/#90/#65) | 7 件 (同上) | **0** |

> **Net 0 の意味**: Issue #111 は close 条件を明確化したコメント追記、open 継続 (B2 ポストポーン)。新規 Issue 起票なし、close なし。triage 基準を満たす新規バグ発見なし

### セッション内教訓 (handoff 次世代向け)

1. **Issue open = 未着手 と即断しない**: Issue タイトルが大粒度な場合、prod 設定は完了していて AC 検証だけ pending、というケースがある。catchup の段階で Issue タイトルだけ見るのではなく、関連 RUNBOOK の実施ログまで遡って状態を把握する。今回 Issue #111「Phase 0.9 有効化」は実態が「設定完了 + smoke test 待ち」だった
2. **ポストポーン Issue は再開トリガーを「機械的判定可能」に**: 「次回ジョイン時」だけだと曖昧 → 「Cloud Logging で新規 `@279279.net` の `beforeSignIn` 成功ログが出現した時点」のような自動検出可能な signal を併記する。今回は RUNBOOK 実施ログに観測コマンド 3 種を埋め込み、社員ジョイン後にコピペで実行できる状態にした
3. **whitelist 廃止と聞かれたら「役割が変わる」と答える**: allowedDomains 有効化で「一般 member は whitelist 不要」になるが、admin 任命と例外管理には引き続き必須。`beforeSignIn` の分岐 (whitelist → allowedDomains → Apple → deny) は whitelist が先に評価されるため、admin の role 指定は whitelist 経由のみ
4. **「メンバー一覧」の所在変化を運用ドキュメントに反映**: allowedDomains 有効化後、一般 `@279279.net` 社員は whitelist に痕跡を残さず Firebase Auth users にしか存在しない。今後「メンバー一覧」が必要なら Auth users API で集計する設計が必要 → 別 Issue 起票候補 (要件次第)

### CI の現状

- main `efdaf3b` (PR #209 merge 後): clean
- 本セッションは documents のみのため CI 影響なし

### 次セッション推奨アクション (優先順)

1. **memory PR (~/.claude) push + merge**: `memory/project_carenote_app_review.md` の Phase 0.9 状態 + whitelist 運用変化セクション追記
2. **新規 `@279279.net` 社員ジョイン時の Cloud Logging 観測 + Issue #111 close**: 社員初回ログイン後 24h 以内に RUNBOOK の close 条件 4 項目を確認 → Issue close
3. **Build 38 配信後の admin UI smoke test**: admin UI でアカウント引き継ぎ self-service 実機確認 (Phase B 機能の本番検証、前 handoff の宿題)
4. **既存 Issue 群** (#192 / #178 / #105 / #92 / #90 / #65): 当面は smoke 結果次第、優先度低
5. **Info.plist `ITSAppUsesNonExemptEncryption: false` 追加** (任意、別 PR、前 handoff の宿題)
6. **Build 37 (v0.1.2) 取り扱い**: 90 日で TestFlight 自動 expire (明示削除不要、前 handoff の宿題)

### 関連リンク

- [Issue #111](https://github.com/system-279/carenote-ios/issues/111) — Phase 0.9: prod tenants/279.allowedDomains 有効化 (open 維持、close 条件本セッションで明確化)
- [docs/runbook/phase-0-9-allowed-domains.md](../runbook/phase-0-9-allowed-domains.md) — Phase 0.9 RUNBOOK (実施ログに 2026-04-27 確認エントリ追加)
- [ADR-007 Guest Tenant for Apple Sign-In](../adr/ADR-007-guest-tenant-for-apple-signin.md) — Apple Sign-In Guest Tenant 設計 (allowedDomains の判定優先順)
- [ADR-005 Auth Blocking Function](../adr/ADR-005-auth-blocking-function.md) — beforeSignIn 全体設計
- `functions/index.js:41-73` — beforeSignIn の whitelist + allowedDomains 分岐実装
- `~/.claude/memory/project_carenote_app_review.md` (グローバル) — Phase 0.9 状態 + whitelist 運用変化セクション

---

# Handoff — 2026-04-27 続報セッション: Build 38 / v1.0.1 APPROVED → Unlisted 配信開始

## ✅ Build 38 / v1.0.1 が App Review 通過 → Unlisted release 完了 + memory に Unlisted 新版仕様を整理

前 handoff で「Build 38 / v1.0.1 を App Review 提出済 (Submission ID `736694f6-01af-4b69-8d28-8420cba31aa6`)、審査待ち最大 48 時間」と記録した状態から、本セッション開始時点で **APPROVED → デベロッパによるリリース待ち** に進行していたことをユーザー画面共有で確認。「価格および配信状況」で Unlisted 設定が v1.0 から自動継承されていることを確認し、「このバージョンをリリース」押下で **同一 Unlisted URL で v1.0.1 配信開始**。提出から約 24h で APPROVED → 同日 release という最速ペース（リジェクト履歴 4 回ありにも関わらず）。あわせて memory に Unlisted 新版リリース手順（再申請不要・公式仕様）を整理し、Claude の誤案内を自戒として記録した。

### セッション成果サマリ

| PR | リポジトリ | 内容 | 状態 |
|----|----------|------|------|
| **#157 (commit 603fc68)** | `yasushi-honda/claude-code-config` | `memory/project_carenote_app_review.md` に Build 38 配信開始反映 + Unlisted 新版リリース手順（再申請不要・公式仕様）追加 + Unlisted URL 明示記載 | 🔵 open（既存 PR に追加コミット） |
| **本 PR** | `system-279/carenote-ios` | `docs/handoff/LATEST.md` に 2026-04-27 続報セッション追記 | 🔵 open |

App Review 結果: **APPROVED**（Submission ID `736694f6-01af-4b69-8d28-8420cba31aa6`、提出 2026-04-26 → APPROVED 2026-04-27、所要約 24h）
配信状態: **Build 38 / v1.0.1 Unlisted 配信中**（URL: `https://apps.apple.com/us/app/carenote-ai/id6760607218`、Build 35 / v1.0 から自動更新で配布範囲継承）

### 主要判断のハイライト

- **「Unlisted release = 別フロー / 申請メール必要」は誤り**: Claude が catchup 直後に「Unlisted は Apple へ申請メール送信が必要、ワンクリックでは切り替えできない」と誤って案内。ユーザー指示で WebSearch + Apple 公式 ([Unlisted App Distribution](https://developer.apple.com/support/unlisted-app-distribution/)) を確認 → **同 App ID 配下の新版は自動的に Unlisted のまま配信される**（既に v1.0 で許可取得済なら v1.0.1 も継承）。rules/tech-selection.md §1「外部サービスの手順を答える前に必ず公式ドキュメント確認」の遵守不足
- **「価格および配信状況」で Unlisted 設定の自動継承を画面確認**: 「アプリの配信方法」欄に「リンクにアクセス可能なユーザのみが App Store でアプリを見つけたり、ダウンロードできます。」と表示 + 「非表示アプリのURL」欄に v1.0 と同じ URL が表示されていれば継承成功。「保存」ボタンが grey-out なら設定変更不要
- **リリース操作は外部影響 hard-to-reverse のため Claude は押さず、ユーザー手動押下**: 「このバージョンをリリース」は押下時刻が公開時刻になる、取り下げは別フローという特性のため、最終操作はユーザー承認のうえユーザーが押下
- **memory PR #157 への追加コミットで継続**: 同 PR が「Build 38 提出反映」として open のまま残っていた → 「配信開始反映」も同 PR の趣旨に含まれるため新規 PR を作らず追加コミット (`docs/memory-build-38-submission` branch、commit 603fc68)
- **Apple Vision Pro 配信もチェック済**: 「価格および配信状況」画面で「このアプリを Apple Vision Pro で配信可能にする」がチェック済を確認、v1.0 から自動継承（v1.0.1 も互換性ありとマーク）

### 実装実績

- **変更ファイル**: 2 ファイル / +36/-10（PR #157 追加コミット、`memory/project_carenote_app_review.md` + `memory/MEMORY.md`）+ 本 PR の handoff 追記
- **memory 追加内容**:
  - 「Unlisted 新版リリース手順（再申請不要・公式仕様）」セクション新設（5 段階手順 + 公式引用 + 過去の誤解を自戒として記録）
  - Build 38 行を「審査中」→「APPROVED → Unlisted 配信中 (2026-04-27)」に更新
  - 配布方式セクション: 現在配布中を Build 38 / v1.0.1 に、Unlisted URL 明示、Apple Vision Pro 配信継承を追記
  - 「完全着地」フローを Unlisted 仕様準拠に再番号（6→6/7/8）
  - 関連リンクに Apple 公式 Unlisted Distribution ページ + Unlisted URL を追加
- **MEMORY.md 索引**: Build 21-37 → 21-38、配布運用記述を「Unlisted 配布運用 + 新版手順（再申請不要）」に拡充
- **iOS コード変更**: なし（本セッションは memory + handoff のみ）

### Issue Net 計測

| 開始時 | 終了時 | Net |
|--------|--------|-----|
| 7 件 (#192/#178/#111/#105/#92/#90/#65) | 7 件（同上） | **0** |

> **Net 0 の意味**: 本セッションは Build 38 / v1.0.1 の Unlisted release 操作 + memory 整理のみ。実装系 Issue 着手なし、新規 Issue 起票なし（triage 基準を満たす新規バグ発見なし）。Issue #111 (Phase 0.9 close 判断) は配信後 smoke test 待ち、現状維持

### セッション内教訓 (handoff 次世代向け)

1. **Unlisted 新版は再申請不要・自動継承（公式仕様）**: 一度 Unlisted 配布許可を取得した App ID 配下の新版は、特別な操作なしに Unlisted のまま配信される。`AppStoreUnlisted@apple.com` への申請メール送信は **不要**。「価格および配信状況」で Unlisted 設定が維持されているか確認 → 「このバージョンをリリース」を押すだけ
2. **外部サービスの手順を答える前に公式ドキュメント確認 (rules/tech-selection.md §1 再確認)**: Claude が「Unlisted は別フロー、申請メール必要」と誤案内した直接原因は、最新の Apple 公式仕様を確認せずに記憶ベースで答えたこと。Apple のような頻繁に仕様が変わる外部サービスは特に WebSearch + 公式 URL で確認必須
3. **リリース操作 (hard-to-reverse + 外部影響) は Claude が押さない**: 「このバージョンをリリース」は押下時刻が公開時刻になり、取り下げは別フロー。最終操作はユーザー承認のうえユーザーが押下するのが原則。Claude は手順案内 + 確認サポートに留める
4. **memory PR が open なら同趣旨の続報は追加コミットで継続**: 新規 PR を乱立させず、既存 PR の趣旨範囲内なら追加コミットで継続。今回 PR #157 の「Build 38 提出反映 + 提出 runbook」に「配信開始反映 + Unlisted 新版手順」を追加するのは自然な継続
5. **画面共有スクリーンショットからの状態判定が確実**: ユーザーの「審査通過した？」のような曖昧な質問より、ユーザー画面のスクリーンショットを直接見て「1.0.1 デベロッパによるリリース待ち」「1.0.1 配信準備完了」のような UI 表示から状態を確定する方が確実。memory 等のテキスト情報と画面表示が乖離している事例あり (Build 35 v0.1.0 vs 実態 v1.0)

### CI の現状

- main `69a3ba0` (PR #208 merge 後): 前回 commit (`3bd38ad`、Build 38 / v1.0.1 bump) の iOS Tests CI は green (22m42s)
- 本 PR は handoff のみのため CI 影響なし

### 次セッション推奨アクション (優先順)

1. **~/.claude PR #157 review + merge** (追加コミット 603fc68 込み): memory への Build 38 配信開始反映 + Unlisted 新版手順整理を main 反映
2. **Build 38 配信後の smoke test**:
   - 既存メンバー (`@279279.net`) 1 名で App Store 自動更新確認
   - admin UI でアカウント引き継ぎ self-service 実機確認 (Phase B 機能の本番検証)
   - **Issue #111 close 判断**: allowedDomains 自動加入 + admin UI smoke 完了 → close
3. **`pre-push-quality-check.sh` の cwd 認識 bug 修正 (別 PR)**: `tool_input.command` から `cd <path> && git push` パターンを抽出 → そのディレクトリで `git branch --show-current` 判定する logic に修正
4. **Build 37 (v0.1.2) 取り扱い**: 提出されないまま 90 日で TestFlight 自動 expire（明示削除不要）
5. **Info.plist `ITSAppUsesNonExemptEncryption: false` 追加** (任意、別 PR): 次回 upload 以降の暗号化質問省略
6. **既存 Issue 群** (#192 / #178 / #105 / #92 / #90 / #65): 当面は配信後 smoke 結果次第、優先度低

### 関連リンク

- [PR #157 (yasushi-honda/claude-code-config)](https://github.com/yasushi-honda/claude-code-config/pull/157) — memory に Build 38 配信開始反映 + Unlisted 新版手順追加（追加コミット 603fc68）
- [Apple Developer Support — Unlisted App Distribution](https://developer.apple.com/support/unlisted-app-distribution/) — 公式仕様: 同 App ID 配下の新版は自動 Unlisted 継承、再申請不要
- App Store Connect Submission ID: `736694f6-01af-4b69-8d28-8420cba31aa6` (Build 38 / v1.0.1、2026-04-26 提出 → 2026-04-27 APPROVED → 同日 release)
- Unlisted URL: `https://apps.apple.com/us/app/carenote-ai/id6760607218`
- 現行配信: **Build 38 / v1.0.1**（2026-04-27 開始）
- `~/.claude/memory/project_carenote_app_review.md` (グローバル) — Build 38 配信開始反映 + Unlisted 新版手順追加 (PR #157 追加コミット)

---

## 📚 過去のセッション

500 行制限のため、2026-04-26 夕方以前のセッション詳細は [docs/handoff/archive/2026-04-history.md](archive/2026-04-history.md) に退避済。

直近 archive 移動 (2026-04-27 続報セッション 2 で実施):
- 2026-04-26 夕〜2026-04-27 早朝: Build 38 / v1.0.1 App Review 提出 + 提出 runbook 化
- 2026-04-26 朝: Build 37 提出不可判明 → Build 38 / v1.0.1 として再 upload
- 2026-04-26 早朝: 「完全着地」フロー Phase B 完遂 + Build 37 / v0.1.2 TestFlight upload
- 2026-04-25 朝〜午後: PR #191 follow-up 3 件 (#194/#193/#192) 完遂 + Cloud Function dev deploy
- 2026-04-24 夜 → 2026-04-25 未明: Issue #182 delete Firestore sync 完全解消 + Build 36 / v0.1.1 TestFlight リリース

