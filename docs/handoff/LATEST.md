# Handoff — 2026-07-22〜23 セッション: Vertex AIモデル自由入力化(ADR-014) → /code-review修正 → PR #220マージ → Build 39提出試行(契約待ちで中断)

## ✅ modelId検証を完全一致allowlistからProhibited denylistへ改訂(ADR-014)、/code-review medium指摘5件（CRITICAL含む）を修正しPR #220マージ完了。Build 39をTestFlight提出試行するもApple Developer Agreement再署名待ちで中断 (PR #220 merged)

前回セッションで実装したADR-011/012がまだApple審査未提出（本番Build 38に未反映）と判明したことを起点に、「どうせ審査を受けるなら以後のモデル切替をGCP側だけで完結できるよう作り込んでから出す」という投資判断でADR-014に着手。plan mode で設計後、decision-makerの明示要望「人が正しいモデル名を入れれば使える」を受けてmodelId検証を完全一致allowlistからCLAUDE.md Prohibitedの2パターンのみを拒否するdenylistへ改訂。実装中に並行セッションのmemory更新を検知し「gemini-3.6-flashの日本DRZ非対応」の根拠が誤った製品ページ（Gemini Enterprise Standard/Plus Editions、CareNoteが使うVertex AIとは別製品）だったことが判明、dev環境での実疎通テスト（`gemini-3.6-flash`はasia-northeast1でHTTP 404）に切り替えてground truthを確定させた。`/code-review medium`でCRITICAL 1件（GitHub Actionsスクリプトインジェクション）・HIGH 1件（URL force-unwrapクラッシュ経路）・MEDIUM 2件・LOW 1件がCONFIRMEDと判定され、全て修正してPR #220をマージ。最後にBuild 39のTestFlight提出を試行したが、App Store ConnectのAgreement（契約）再署名待ちでExportが失敗し中断した。

### セッション成果サマリ

| PR | 内容 | 状態 |
|----|------|------|
| **#220** | Vertex AIモデルID検証をProhibited denylistへ改訂 (ADR-014) + `/code-review medium`指摘5件修正 | 🟢 merged (squash, c8273a2) |

### 主要判断のハイライト

- **decision-makerの「人が正しいモデル名を入れれば使える」という意図を正確に汲み取る**: 当初提示した3択（パターン一致allowlist拡張/検証済みモデル事前登録/allowlist自体のFirestore化）のいずれでもなく、「完全一致allowlist廃止＋Prohibited denylistで両立」という第4の設計に到達。CLAUDE.md Prohibitedを黙って無効化せず、denylistとしてコードで担保し続けることでAI executorのガバナンス越権を回避
- **thinkingLevelの範囲は現状維持を選択**: modelIdと違い、thinkingLevel拡張はコスト・レイテンシ予測可能性とのトレードオフを伴う経営判断のため、AskUserQuestionで明示確認し「minimalのみ維持」を選択（AI単独で決めない）
- **並行セッションのmemory更新を鵜呑みにせず独立検証**: 会話中に別セッション（同一ユーザー）が更新したmemoryで「gemini-3.6-flashは日本DRZ未対応」という記述が出現したが、一次ソース製品スコープ（Gemini Enterprise Standard/Plus Editions vs Vertex AI）を自ら確認し、最終的にdev環境の実API呼び出し（HTTP 404）でground truthを確定。ADR-014の初版記述に誤りがあったことを訂正コミットで明示的に記録
- **`/code-review medium`でCRITICAL 1件を発見・修正**: `model_id`をGitHub Actions `type: choice`→`type: string`化した際、`${{ inputs.model_id }}`をrun:ブロックに直接埋め込んだままだったためスクリプトインジェクション脆弱性が生じていた（WIF由来のGCPトークン窃取リスク）。job-level `env:` 経由の間接参照に変更し解消
- **Apple Developer Agreement未署名でTestFlight提出が中断**: アーカイブ自体は成功したが、Export時に`403 FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED`。契約への同意はAI実行不可（本人のみが行うべき法的行為）のため、decision-maker自身のApp Store Connect対応待ち。アーカイブは`build/CareNote.xcarchive`に残存しており再Export可能

### 実装実績

- **新規ファイル**: `docs/adr/ADR-014-vertex-ai-model-denylist.md`
- **変更ファイル**: `CareNote/Models/VertexAIConfig.swift`（`allowedModelIds`完全一致Set→`isModelAllowed(_:)`denylist関数＋文字種/長さ検証）、`.github/workflows/firestore-op.yml`（`model_id`をtype:choice→type:string化＋job-level `env: MODEL_ID`でスクリプトインジェクション対策＋denylistロジック強化）、`scripts/set-vertex-ai-config.sh`（denylist検証を新規追加）、`CareNoteTests/VertexAIConfigServiceTests.swift`（`@Test(arguments:)`パラメータ化＋新規バイパスケース）、`docs/adr/ADR-012-vertex-ai-config-firestore.md`・`CLAUDE.md`・`README.md`（整合更新）
- **テスト**: Swift全208件PASS（denylist境界テスト含む、`gemini-3.0-flash`/`gemini-3-flashpreview`/`preview001`拒否・`expansion`誤検知回避を明示的にカバー）
- **GCP実測**: `carenote-dev-279`から`gemini-3.5-flash`（HTTP 200 + ON_DEMAND）・`gemini-3.6-flash`（HTTP 404、asia-northeast1未デプロイ）をVertex AI `generateContent` APIへ直接呼び出しして確認
- **TestFlight**: `project.yml`のCURRENT_PROJECT_VERSIONを38→39に更新（ローカル未コミット、`build/CareNote.xcarchive`としてアーカイブ済み）、Export/UploadはAgreement待ちで中断

### `/code-review medium` 詳細（8ファインダー→8件検証、5件CONFIRMED修正済み）

1. **CRITICAL**: `.github/workflows/firestore-op.yml` — `model_id`のtype:choice→type:string化に伴うGitHub Actionsスクリプトインジェクション。job-level `env: MODEL_ID`経由に変更し解消
2. **HIGH**: `CareNote/Models/VertexAIConfig.swift` — `isModelAllowed()`に文字種・長さ検証なし、`TranscriptionService`のURL force-unwrapクラッシュ経路。文字種チェック追加で解消
3. **MEDIUM**: denylistのセグメント完全一致判定が`gemini-3.0-flash`/`gemini-3-flashpreview`/`preview001`等をバイパス。`preview`部分一致＋`exp`の英字直後ガードで強化
4. **MEDIUM**: `scripts/set-vertex-ai-config.sh`が無検証。GHA/Swiftと同じdenylistロジックを追加
5. **LOW**: テスト重複4件を`@Test(arguments:)`でパラメータ化

REFUTED 3件（echo leading-hyphenのbash仕様誤解、raw model_id不整合の実害なし、ADR記述の正確性クレーム誤り）は根拠を確認のうえ不採用と判断。

### Issue Net 計測

| 開始時 | 終了時 | Net |
|--------|--------|-----|
| 7 件 (#192/#178/#111/#105/#92/#90/#65) | 7 件 (同上、起票・close なし) | **0** |

### セッション内教訓 (handoff 次世代向け)

1. **「今すぐ審査を受けられる」と「変更が既に本番にある」は別軸**: ADR-011/012実装済み≠本番反映済み。Build番号とproject.yml内容が実際のTestFlight/App Store配信物と一致しているかを都度確認する習慣が必要（今回はユーザーの指摘で気づいた）
2. **並行セッションのmemory更新は「並行検証の材料」として扱い、鵜呑みにしない**: 内容が具体的で一次ソース引用があっても、自分のセッションの文脈（このプロジェクトが実際に使うAPI/製品）と照合してから採用する
3. **リリース系の外部要因ブロッカー（契約未署名等）は即座に切り分けて報告**: アーカイブ成功・Export失敗のように、どこまで進んでどこで止まったかを明確にすることで、再開時にアーカイブからのやり直しを避けられる

### CI の現状

- PR #220: iOS Tests ✅ success（23m44s、2026-07-22T15:50:17Z）
- main `c8273a2`（PR #220 merge後）: clean

### 次セッション推奨アクション

**即着手なし、条件待ち 2 件:**

1. **TestFlight Export再試行** — trigger: decision-makerがApp Store Connect（https://appstoreconnect.apple.com/agreements）で未署名/期限切れ契約に同意完了。充足時のタスク: `build/CareNote.xcarchive`（既存、再アーカイブ不要）に対し`xcodebuild -exportArchive`以降のみ再実行 → 成功後`project.yml`のBuild 39変更をコミット。確認方法: 契約ページで未署名項目の有無を確認
2. **Issue #178 Stage 2（prod GHA+WIF展開）** — trigger: TestFlight/App Store提出・審査通過後（またはdecision-maker明示指示があれば前倒し可）。充足時のタスク: ADR-013 Phase 3（prod専用WIFプール・SA・IAM構築）を計画

**却下候補:**

1. **PR #125/#123/#122（2026-04-20付、3ヶ月以上前のOPEN PR）** — 検討経緯: 本セッションのIssue #178/Open PR確認中に発見。PR #125/#123が参照するIssue #104/#108は共にCLOSED済み（別経路で解消済みの可能性が高い）、PR #122が参照するIssue #111はOPENだが後続セッションでprod設定完了済みと判明しておりPR内容が陳腐化している可能性。着手しない理由: 内容未精査でスコープ未確定、decision-maker明示指示待ち（精査またはclose判断を仰ぐ）
2. Issue #192/#111/#105/#92/#90/#65 — すべてenhancement、起点はdecision-maker領分

### 関連リンク

- [PR #220](https://github.com/system-279/carenote-ios/pull/220) — Vertex AIモデルID検証をProhibited denylistへ改訂 (ADR-014、merged c8273a2)
- [ADR-014](../adr/ADR-014-vertex-ai-model-denylist.md) — modelId denylist改訂の設計判断・gemini-3.6-flash評価記録
- [Google公式blog: Gemini 3.6 Flash発表](https://blog.google/innovation-and-ai/models-and-research/gemini-models/gemini-3-6-flash-3-5-flash-lite-3-5-flash-cyber/)

---

# Handoff — 2026-07-21 セッション: Gemini 3.5 移行 → GHA+WIF基盤(dev) → Vertex AI設定Firestore化 → code-review修正 → dev検証

## ✅ Gemini 2.5→3.5 Flash移行を起点に、GHA+WIF運用基盤(dev)とVertex AI設定Firestore化(ADR-012)を実装、/code-review高優先度5件を修正しdev環境でend-to-end検証完了 (PR #215/#216/#217/#218 merged)

Gemini 2.5 Flashのretirement（2026-10-16以降）を受け、最小限のモデル差替えを先行実装した後、時間的余裕があることから「App Store審査なしでモデル/プロンプトを切替できる仕組み」への投資を決定。Plan Mode → Ultraplan（クラウド実行）でVertex AI設定Firestore化を実装、ローカルへteleport後にxcodegen再生成漏れ・MockURLProtocolのhttpBodyStream復元漏れの2件の実バグを発見修正。firestore.rulesデプロイでfirebase CLIログインアカウント不一致に遭遇したことを機に、ADR-009 Stage 2として構想のみだったGHA+WIF基盤(Issue #178)を今回dev環境分のみ実装。最後に`/code-review xhigh`（10ファインダー→13候補検証→3件スイープ追加→計15件報告）を実行し、高優先度5件を修正・検証してdev環境でend-to-end確認まで完了した。

### セッション成果サマリ

| PR | 内容 | 状態 |
|----|------|------|
| **#215** | GitHub Actions + WIF によるFirestore rules/操作デプロイ基盤 (ADR-013) | 🟢 merged |
| **#216** | `google-github-actions/auth`に`token_format: access_token`追加（dev初回検証で発覚した実バグ） | 🟢 merged |
| **#217** | Vertex AI モデル設定のFirestore化 (ADR-012) + `/code-review xhigh`高優先度5件修正 | 🟢 merged |
| **#218** | ADR-009にADR-013への相互参照を追記（handoff時のADR整合性チェックで発見） | 🟢 merged |

### 主要判断のハイライト

- **モデル移行は最小差替え→本格投資の2段階**: 最初にAskUserQuestionで「最小限：モデル差替えのみ」を選択、動作確認後、期限まで3ヶ月の余裕があると判断し「しっかりプランたてていきましょう」でVertex AI設定Firestore化へ投資判断
- **Ultraplan実装のクロスチェックが有効**: クラウド実行後のローカルbuild+testで、Ultraplanのサンドボックスには無いXcode/Swiftツールチェーンだからこそ発見できた実バグ2件（xcodegen再生成漏れ、MockURLProtocolのhttpBodyStream復元漏れ）を修正
- **GHA+WIF基盤は既存WIFプールを流用せず新設**: `carenote-pool`（ADR-002、アプリのエンドユーザー認証用）のワイルドカードimpersonation bindingを流用すると権限昇格リスクがあるため、`github-actions-pool`を新規作成。専用SA `gha-firestore-ops`は`roles/datastore.user`+`roles/firebaserules.admin`のみで`firebaseauth.admin`は不要と判断（whitelist書込みでadmin-role操作が完結するため）
- **`workflow_dispatch`はdefault branch必須の制約に対応**: 新規workflowファイルはmainにマージ済みでないとdispatchできないため、ADR-013+2ワークフローファイルのみの小PR(#215)を先行マージしてから検証する戦略を採用
- **`/code-review xhigh`は9/10ファインダーが機能、13件Phase 2検証で全てCONFIRMED/PLAUSIBLE**: 唯一angleE(wrapper/proxy correctness)のみ10回以上の再依頼でも内容が届かず未実施のまま終了（他アングルで部分的にカバー）。高優先度5件（VertexAIConfigServiceのキャッシュTTL欠如+失敗の永続キャッシュ化、set-vertex-ai-config.shの失敗時サイレント成功+JSONインジェクション、allowlist拒否の完全サイレント化、firestore.rulesのtranscriptionModelId不変性未強制）を修正し、修正後にSwift 207件+Firestore rulesテスト88件（新規5件含む）全PASSを確認
- **dev環境end-to-end検証を完了**: `firestore-rules-deploy.yml`でplatformConfigルールがdevに反映されたことをverifyステップで確認、`firestore-op.yml`の`set-vertex-ai-config`でdevに`gemini-3.5-flash`/`minimal`をシード、GitHub側`type: choice`制約により不正なmodel_idがAPI層でHTTP 422拒否されることも実証、Cloud Loggingでの監査ログ記録も確認済み

### 実装実績

- **新規ファイル**: `CareNote/Models/VertexAIConfig.swift`, `CareNote/Services/VertexAIConfigService.swift`, `CareNoteTests/VertexAIConfigServiceTests.swift`, `scripts/set-vertex-ai-config.sh`, `docs/adr/ADR-011/012/013`, `.github/workflows/firestore-rules-deploy.yml`, `.github/workflows/firestore-op.yml`
- **変更ファイル**: `TranscriptionService.swift`（model/thinkingLevelを注入可能に）, `FirestoreService.swift`（fetchVertexAIConfig追加）, `OutboxSyncService.swift`（transcriptionModelId記録）, `RecordingConfirmViewModel.swift`（factory async化）, `firestore.rules`（platformConfig読取ルール+transcriptionModelId不変性）, `FirestoreModels.swift`, `CLAUDE.md`, `README.md`
- **GCPリソース新規作成（dev、`carenote-dev-279`）**: WIFプール`github-actions-pool`+provider、SA`gha-firestore-ops`（`roles/datastore.user`+`roles/firebaserules.admin`+`roles/serviceusage.serviceUsageViewer`）、Firestore Data Access監査ログ有効化
- **GitHub Environment**: `dev`（保護なし）・`prod`（箱のみ、required reviewer等は未設定）
- **prod操作**: なし（明示的にスコープ外、Issue #178継続open）

### `/code-review xhigh` 詳細（10ファインダー→13検証→3件スイープ、計15件報告・うち5件修正済み）

**修正済み（高優先度5件、PR #217に追加commit a4e3884で対応）**:
1. `VertexAIConfigService.resolveConfig()`: fetch失敗・allowlist不正値をキャッシュしない設計に変更（従来は一時障害でプロセス生存中ずっとdefault固定、かつ後発の失敗が先発の成功をレース条件で上書きしうる不具合があった）
2. `scripts/set-vertex-ai-config.sh`: JSON組立を生文字列結合から`jq -n --arg`に変更（JSONインジェクション対策）、HTTPステータス明示チェックを追加（失敗時も✅成功表示していた不具合を解消）
3. `.github/workflows/firestore-op.yml`: `model_id`/`thinking_level`を`type: choice`のallowlist選択式に変更＋Validate inputsに二重チェック追加（従来はallowlist外の値を書き込んでもCIが緑になり誰も気づけなかった）
4. `firestore.rules`: `recordings`の`allow update`に`transcriptionModelId`不変性チェックを追加（`createdBy`と同じpre/post判定パターン）、`functions/test/firestore-rules.test.js`にテスト5件追加

**未修正（スコープ外、既知の制約としてADR-012に明記）**:
- `allowedModelIds`がSwiftソースにハードコードされ、真に新規のモデルIDへの切替は依然としてアプリ再ビルドを要する（ADR-011のシナリオを完全解決していない）
- `OutboxSyncService`の`transcriptionModelId`が`transcriptionService`から独立したパラメータで、両者の一致を強制する仕組みがない
- `RecordingListViewModel.retryRecording()`後に別モデルで文字起こしされても`transcriptionModelId`は作成時の値のまま（PLAUSIBLE判定、要app relaunch+新規保存トリガーの複合条件）
- テストカバレッジ欠如（`saveAndTranscribe()`の非同期factory統合経路が未テスト）、TranscriptionServiceのmodel検証欠如（latentのみ、現状唯一の呼び出し元はallowlist経由）、README ADR件数の陳腐化、シェルスクリプト3本の定型処理重複、syncServiceFactoryの不要なasync化、コールドスタート時の重複fetch

### Issue Net 計測

| 開始時 | 終了時 | Net |
|--------|--------|-----|
| 7 件 (#192/#178/#111/#105/#92/#90/#65) | 7 件 (同上、Issue起票・close なし) | **0** |

> Issue #178（Stage 2 follow-up）は今回dev分のみ実装・prod分は継続OPEN。triage基準を満たす新規Issue起票なし。

### セッション内教訓 (handoff 次世代向け)

1. **Ultraplan（クラウド実行）はローカルでのbuild+test検証を必ず挟む**: サンドボックスにXcode/Swiftツールチェーンがないため、xcodegen再生成漏れやテストヘルパーのFoundation既知バグ（httpBodyStream→httpBody変換）はローカル検証でしか発見できなかった
2. **既存WIFプールの流用は権限昇格リスクを疑う**: プール単位のワイルドカードimpersonation bindingがある場合、新規providerを同プールに足すと意図しない権限昇格になりうる。専用プール新設のコストは低い
3. **`workflow_dispatch`は対象ファイルがdefault branchに存在しないと起動できない**: 新規workflow追加時は「小PRで先にmainへ」戦略が有効
4. **`/code-review`のバックグラウンドエージェント団は応答が来ないケースがある**: 10体中1体(angleE)が10回以上の催促でも内容を返さなかった。他アングルで部分カバーされていれば結果全体としては許容範囲だが、全滅リスクは考慮に入れる
5. **allowlist方式の設定切替は「ソフトフェイル」だけでは不十分**: 失敗をログに残さないと運営者が設定ミスに気づく手段がなくなる。CI側のverifyも「書いた値が読めるか」だけでなく「その値が有効か」まで見ないと自己言及的になる

### 次セッション推奨アクション

**即着手なし、条件待ち 1 件:**

1. **Issue #178（Stage 2 prod展開）の着手判断** — trigger: decision-maker が prod への GHA+WIF 展開を明示指示。充足時のタスク: ADR-013 Phase 3（prod専用WIFプール・SA・IAM構築、`prod` Environment に required reviewer + main限定設定）を実施。確認方法: `gh issue view 178` で AC 未達項目を再確認してから着手

**却下候補:**

1. **`/code-review`残り10件の指摘への対応** — 検討経緯: 今回は高優先度5件のみ修正、残り10件（テストカバレッジ欠如・allowedModelIds拡張性・シンプリフィケーション系等）はADR-012に既知の制約として明記済み。着手しない理由: ROI中程度でスコープ未確定、decision-maker明示指示待ち

---

# Handoff — 2026-07-01 セッション: README 刷新 (AI 引き継ぎ可能なアーキテクチャ設計を front-load)

## ✅ README を readme-pro 原則で刷新し AI 引き継ぎ可能な状態を構築 (PR #213 merged)

catchup で「即着手 = 0 件 / 条件待ち 4 件」の idle 判定が出た状態から、ユーザー質問「最新の技術ドキュメントについてマニュアルサイトもしくはドキュメントサイトはつくってましたか？」を起点に docs/ の Web 公開状況を調査。`docs/*.html` は Firebase Hosting `hosting/public/` に含まれず未公開、GitHub Pages も未設定と判明。「マニュアルサイト/ドキュメントサイトを別立てする」代替として **GitHub 上の Markdown レンダリング + README を hub 化する方針** をユーザーが選択 → `/readme-pro` スキルで詳細設計を README に front-load。PR #213 (docs/readme-pro-architecture-handoff → main) を作成 → ユーザー明示認可「PR #213 マージして」で squash merge 完了、local main も `origin/main` と fast-forward 同期済。

### セッション成果サマリ

| PR | リポジトリ | 内容 | 状態 |
|----|----------|------|------|
| **#213** | `system-279/carenote-ios` | README.md 全面刷新 (+246/-51、270 行) — Mermaid 3 図 (システム構成 / 録音〜文字起こしフロー / 認証・多テナントフロー) + AI 引き継ぎセクション + ADR 全 10 件 / Runbook 3 件索引 + 禁止事項 7 項目 front-load | 🟢 **merged** (squash, cf500d7) |

### 主要判断のハイライト

- **「マニュアルサイト新設」ではなく README を hub 化する方針を採用**: リポジトリが PUBLIC で `docs/adr/*.md` `docs/runbook/*.md` `docs/handoff/LATEST.md` は既に GitHub 上でレンダリング可能。追加インフラ (Firebase Hosting 拡張 / GitHub Pages 有効化) なしで README を索引化するだけで発見性の問題は解決可能と判定。HTML 版 (`docs/*.html`) は GitHub では raw ソースしか表示されないため今回は対象外
- **readme-pro 原則 (Less is more + linked depth + front-loading) の忠実な適用**: 270 行 (< 300 目標) に収め、詳細は ADR/Runbook/CLAUDE.md へリンク。装飾絵文字排除、GitHub Alerts は本当に必要な IMPORTANT 1 個のみ。Mermaid 3 図は「サービス 3+ で非同期通信あり」条件を満たすため採用
- **AI 引き継ぎセクションを明示的に新設**: ユーザー要望「AIへアーキテクチャ引き継ぎ可能な状況にしてください」に応じ、Claude Code / Codex 等の LLM が本プロジェクトを 5-10 分で把握するための読み込み順を 6 ステップで明示 (CLAUDE.md → README architecture → ADR → handoff → runbook → ソース)。`/catchup` にも言及
- **feature ブランチ + PR フロー厳守**: CRITICAL 4 原則 §4 (main 直 push 禁止) に従い `docs/readme-pro-architecture-handoff` を切ってから編集開始。commit → push → PR → 明示認可 → squash merge → `origin/main` 同期の順で実行
- **PR 承認は番号単位明示認可を取得**: ユーザーから「PR #213 マージして」の具体的認可を取得後に squash merge 実行 (CRITICAL 4 原則 §3 準拠)

### 実装実績

- **変更ファイル**: 1 ファイル (README.md、+246/-51、270 行に収束)
- **追加された Mermaid 図**: 3 種
  - システム構成 (flowchart TB) — iOS / Firebase / GCP の 3 subgraph、Google-Apple Sign-In + WIF + Vertex AI の全経路可視化
  - 録音〜文字起こしデータフロー (sequenceDiagram) — User → App → SwiftData → Cloud Storage → Gemini → Firestore
  - 認証・多テナントフロー (sequenceDiagram) — Sign-In → Firebase Auth → beforeSignIn の分岐 (allowedDomains / Guest Tenant)
- **追加された索引**: ADR 10 件 (1 行サマリ + 影響レイヤー付き) + Runbook 3 件 (状態付き)
- **front-load された禁止事項**: 7 項目 (tenantId ハードコーディング / SA key 同梱 / 音声 Firestore 保存 / thinkingBudget 非 0 / Gemini 3 Flash 使用 / @Query 直接使用 / prod 未確認操作)
- **iOS コード変更**: なし (ドキュメントのみ)
- **prod 操作**: なし (Firebase / GCP 触らず)

### Issue Net 計測

| 開始時 | 終了時 | Net |
|--------|--------|-----|
| 7 件 (#192/#178/#111/#105/#92/#90/#65) | 7 件 (同上) | **0** |

> **Net 0 の意味**: 本セッションは README ドキュメント刷新のみ。実装系 Issue 着手なし、新規 Issue 起票なし (triage 基準を満たす新規バグ発見なし)。既存 Issue の状態変化なし

### セッション内教訓 (handoff 次世代向け)

1. **「サイトを作る」の前に「既に PUBLIC で見える状態」を確認**: docs/*.md は GitHub 上で既にレンダリング可能だったのに「サイト構築」の発想に飛びかけた。README を索引化するだけで発見性の 90% は解決するケースがある。追加インフラを検討する前に「今の PUBLIC 資産で解決できないか」を先に確認
2. **readme-pro の Less is more は「情報を減らす」ではなく「front-load + linked depth」**: 270 行に収めつつアーキテクチャ 3 図 + ADR 10 件索引 + 禁止事項 7 項目を含められたのは、詳細を CLAUDE.md / ADR / Runbook へリンクで委譲したから。README 自体には「次のアクション」への最短経路だけ残す
3. **AI 引き継ぎのための README パターン**: 「CLAUDE.md → README architecture → ADR → handoff → runbook → ソース」の読み込み順を明示的に書くと、AI が初回起動時にコンテキスト構築コストを大幅に削減できる。今後の新規リポジトリ立ち上げ時のテンプレート化候補
4. **Mermaid 図採用判定は「サービス 3+ で非同期」条件で機械化**: 本 README は iOS + Firebase + GCP の 3 系統 + Auth Blocking + Callable Function の非同期があるため採用。「なんとなく図があった方が」で描くと readme-pro セルフチェック「装飾排除」に引っかかる

### CI の現状

- main `cf500d7` (PR #213 merge 後): README のみ変更のため CI 影響なし (Markdown のみ変更で iOS Tests workflow は発火せず)
- 前回 iOS Tests CI: main `3bd38ad` (Build 38 / v1.0.1 bump) で green (22m42s、2026-04-26T12:43:50Z)

### 次セッション推奨アクション

**即着手なし、条件待ち 4 件 (前 handoff から変化なし):**

1. **Issue #111 close 判断** — trigger: Cloud Logging で新規 `@279279.net` の `beforeSignIn` 成功ログ出現 / 社員ジョイン報告 → RUNBOOK 観測コマンド 3 種実行 → close 条件 6 項目確認 → Issue close
2. **Build 38 admin UI smoke test** — trigger: 社内実機 (Build 38 自動更新済) で admin UI 動線を実行できる時点 → admin UI でアカウント引き継ぎ self-service を実機確認
3. **Build 37 (v0.1.2) TestFlight 自動 expire** — trigger: upload から 90 日経過 (2026-07 頃) → 明示操作不要 (自動 expire)
4. **新規社員 @279279.net オンボーディング時の allowedDomains 検証** — trigger: 新規社員ジョイン → 初回 Google Sign-In → customClaims / whitelist 状態確認

**却下候補 (記録のみ、包括指示の対象外):**

- Issue #192 / #178 / #105 / #92 / #90 / #65 — すべて enhancement、起点は decision-maker 領分
- `Info.plist ITSAppUsesNonExemptEncryption: false` 追加 — 任意改善、明示指示なし
- `pre-push-quality-check.sh` cwd 認識 bug 修正 — グローバル hook 側、本プロジェクトスコープ外
- HTML 版 (`docs/*.html`) の Web 公開 — Firebase Hosting 拡張 or GitHub Pages 有効化が必要、decision-maker 判断
- ケアマネ向け利用マニュアルサイト新設 — 起点は decision-maker 領分、まず「必要か」判断が先

### 関連リンク

- [PR #213](https://github.com/system-279/carenote-ios/pull/213) — README AI 引き継ぎ対応 (merged, cf500d7)
- [README.md](../../README.md) — 刷新後の最新版 (Mermaid 3 図 + AI 引き継ぎセクション + ADR 索引 + 禁止事項 front-load)
- [readme-pro スキル](file:///Users/yyyhhh/.claude/skills/readme-pro/SKILL.md) — 適用したベストプラクティス原則

---

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

