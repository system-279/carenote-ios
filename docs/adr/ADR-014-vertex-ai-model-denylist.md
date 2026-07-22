# ADR-014: Vertex AI modelId 検証を完全一致allowlistからProhibited denylistへ改訂

## ステータス
Accepted (2026-07-22)

**Supersedes**: [ADR-012](./ADR-012-vertex-ai-config-firestore.md) の設計判断4（modelId/thinkingLevel 両方を完全一致allowlistで検証）のうち modelId 側のみ
**Related**: [ADR-011](./ADR-011-gemini-3-5-flash-migration.md)（Gemini 3.5 Flash 移行）

## コンテキスト
ADR-011/012 は現時点でまだ App Store 審査を経ておらず、本番の Build 38 / v1.0.1 には含まれていない。本番反映には少なくとも1回の審査が避けられないため、「どうせ審査を受けるなら、以後のモデル切替を GCP 側だけで完結できるよう作り込んでから出す」という投資判断を行った。

ADR-012 の modelId allowlist は `{"gemini-3.5-flash"}` の完全一致1件のみで、新しいモデルIDへの切替は依然としてアプリのソース変更・再ビルド・審査を要し、ADR-011 が解決しようとしたシナリオ（Google都合のモデル強制切替）を完全には解決していなかった（ADR-012 に既知の制約として明記済み）。

この設計の妥当性は実装当日に実例で裏付けられた: `gemini-3.6-flash` が 2026-07-21（前日）にGAし（[Google公式blog](https://blog.google/innovation-and-ai/models-and-research/gemini-models/gemini-3-6-flash-3-5-flash-lite-3-5-flash-cyber/)）、3.5 Flash比で出力コストが約17%安いことが判明した。完全一致allowlistのままでは、この種の乗り換えのたびに再度アプリ更新・審査が必要になる。

## 決定
`VertexAIConfig.isValid` の modelId 検証を、完全一致allowlist（`allowedModelIds: Set<String>`）から **CLAUDE.md Prohibited の2パターンのみを拒否する denylist**（`VertexAIConfig.isModelAllowed(_:)`）に変更する。thinkingLevel は現状の完全一致allowlist（`minimal` のみ）を据え置く。

### 設計判断

1. **denylistが拒否するのは以下の3種類**:
   - (a) 文字種・長さが不正な値: `[a-z0-9]` で始まり `[a-z0-9.-]` が続く1〜64文字のみ許容（`TranscriptionService` の `URL(string:)!` force-unwrap クラッシュを防ぐための必須ガード）
   - (b) 無印「Gemini 3 Flash」ベースモデル: `gemini-3-flash`・`gemini-3.0-flash` の完全一致、またはそれぞれに `-` を続けたID。マイナーバージョン付き（`gemini-3.5-flash`・`gemini-3.6-flash`・`gemini-3.1-flash-lite` 等）は対象外——ADR-011 が既に「`gemini-3.5-flash` は Prohibited の対象外」と判断した解釈をそのまま踏襲する
   - (c) preview/experimental系: ハイフン区切りの構成要素（`split(separator: "-")`）を単位に、`preview` を部分一致で含むもの（`gemini-3-flashpreview`・`preview001` のようなハイフン省略・サフィックス付きのバイパスも拒否するため）、または `experimental` 完全一致、または `exp` 完全一致・`exp` で始まり直後が英字でないもの（`exp2`/`exp-001` は拒否するが `expansion`/`experimental`〔別ルールで既に拒否〕は誤検知しない）
2. **`preview`/`exp`の判定粒度が異なるのは意図的**: `/code-review medium` で「`gemini-3-flashpreview`・`gemini-3.0-flash`・`preview001` 等がハイフン境界依存の完全一致では素通りする」という指摘（CONFIRMED）を受けて、`preview` は部分一致に強化した。一方 `exp` は `contains` にすると `expansion` 等の偶発一致を誤検知するため（ADR初版から継続する既知のトレードオフ）、「`exp`で始まり直後が非英字」という限定条件で部分一致相当のカバレッジを確保しつつ誤検知を避けている
3. **thinkingLevel は据え置き**: `thinkingLevel` は `minimal`/`low`/`medium`/`high` という閉じた4値の列挙（[Gemini公式docs](https://ai.google.dev/gemini-api/docs/generate-content/thinking)確認済み）であり、CLAUDE.md Prohibited は `minimal` 以外を明示的に禁止している。decision-maker はコスト・レイテンシの予測可能性を優先してこの制約の据え置きを選択した（thinkingLevelを上げるほど文字起こし1件あたりのコスト・レイテンシが増加するため）。よって modelId のような denylist化はせず、完全一致allowlist（`minimal` のみ）のまま
4. **出荷時デフォルトは `gemini-3.5-flash` を維持、`gemini-3.6-flash` へは切り替えない**（根拠は当初の記述から訂正、下記参照）。`gemini-3.5-flash` は CareNote が実際に使う Vertex AI `generateContent` API（`aiplatform.googleapis.com`）で asia-northeast1 の on-demand 呼び出しを実測済み（2026-07-20 / 2026-07-22 再実測、いずれも HTTP 200 + `trafficType: "ON_DEMAND"`、実プロジェクトのGCP環境から直接呼び出して確認）。`gemini-3.6-flash` は同一APIで同一リージョンへ実呼び出しした結果 **HTTP 404 Not Found**（`carenote-dev-279` から asia-northeast1 の `gemini-3.6-flash:generateContent` を実行、2026-07-22実測）——DRZ（データレジデンシー）以前に、そもそも asia-northeast1 にモデル自体がデプロイされていない（`gemini-3.1-flash-lite` が同様に404だった前例と同じパターン）。日本リージョン縛りの CareNote では現状 `gemini-3.5-flash` が唯一の現実的選択肢であり、この結論は確定情報に基づく。`gemini-3.6-flash` が将来 asia-northeast1 に展開されれば、運営者がFirestore設定を変更するだけで審査なしに切替可能になる（自由入力式のメリットそのもの）

   > **訂正（本ADR初版からの修正）**: 初版では `gemini-3.6-flash` の日本非対応を「`docs.cloud.google.com/gemini/enterprise/docs/locations` で確認済み」としていたが、このページは実際には **「Gemini Enterprise Standard/Plus Editions」という別製品**（CareNoteが使うVertex AI `generateContent` とは異なる製品ライン）のデータレジデンシーページであり、製品スコープの確認を怠っていた（AI駆動開発ハーネスの一般ルール `rules/tech-selection.md` §1.1「一次ソースの製品スコープ確認」に事例として追記済み）。正しい対象製品のドキュメント（`docs.cloud.google.com/vertex-ai/generative-ai/docs/learn/data-residency`）はJSレンダリングで表組み抽出不能だったため、CareNote が実際に呼び出す `generateContent` API へ直接実呼び出しして ground truth を確認する方式に切り替え、上記の HTTP 404 という決定的な結果を得た。結論（`gemini-3.5-flash` 維持）は初版から変わらないが、根拠は文書上の間接確認から実測による直接確認に置き換えた
5. **`allowlist` という呼称を仕組み全体からは廃止しないが、modelId側は実質的にdenylist方式**: `VertexAIConfig.allowedThinkingLevels`（据置）と `VertexAIConfig.isModelAllowed(_:)`（新規）を明確に呼び分け、コメントでも検証方式の違いを明記する

## 理由
- 「人が正しいモデル名を入れれば使える」という運営者体験は、GAされた正規モデル名であればdenylistの2パターンに一切該当しないため完全に満たされる
- CLAUDE.md Prohibited（decision-maker自身が定めた標準ルール）を黙って無効化せず、denylistとしてコードで担保し続けることで、AI executorが越権してガバナンスを弱めることを防ぐ
- thinkingLevelは閉じた4値かつコスト影響が大きいため、decision-makerの明示判断（本ADR起票時に確認済み: `minimal`のみ維持を選択）により対象外とした

## 制約・既知のリスク
- denylistは「Prohibitedに違反しない」ことしか保証せず、「Vertex AIで実際に動く」ことは保証しない。存在しない・リージョン非対応のモデルIDが設定された場合は実行時エラーとなり、Firestore設定の修正で復旧する（ADR-012 設計判断6の既知リスクを継続）
- modelIdの文字種・長さチェックは `CareNote/Models/VertexAIConfig.swift` の `isModelAllowed(_:)`・`.github/workflows/firestore-op.yml`・`scripts/set-vertex-ai-config.sh` の3箇所全てで実施する（`/code-review medium` で発見: 当初はGitHub Actionsのbashのみが文字種チェックを行い、アプリ本体（`isModelAllowed`）とスクリプトは非空文字列チェックのみだったため、`TranscriptionService` のURL組み立てでforce-unwrapクラッシュを起こしうる値が理論上通過し得た。3箇所を同一ロジックへ統一して解消）
- 実在性・リージョン対応・データレジデンシー適合性の検証は依然として運営者の責任（文字種・Prohibitedパターンの検証は3箇所とも行うが、そのモデルが実際にVertex AIで動くかは検証しない）
- denylistロジックはSwift・GitHub Actions bash・運営者向けシェルスクリプトの3箇所に独立実装されており、将来Prohibitedパターンが追加された際は3箇所同時更新が必要（単一のソースオブトゥルースを持たない設計上のトレードオフ、`/code-review medium` でも指摘済み）

## 影響
- `CareNote/Models/VertexAIConfig.swift`: `allowedModelIds`（完全一致Set）を`isModelAllowed(_:)`（denylist判定関数、文字種・長さチェック含む）に置換。`allowedThinkingLevels`・`default`は変更なし
- `.github/workflows/firestore-op.yml`: `model_id` 入力を `type: choice`（`gemini-3.5-flash`固定）から `type: string`（自由入力）に変更。job レベルの `env: MODEL_ID` を新設し、`run:` ブロック内で `${{ inputs.model_id }}` を直接埋め込む代わりに `$MODEL_ID` を参照するよう変更（`/code-review medium` で発見: `type: choice`→`type: string`化により、直接埋め込みパターンがGitHub Actionsの既知のスクリプトインジェクション脆弱性として悪用可能になっていた。WIF由来のGCPアクセストークンが同一ジョブ内で取得されるため、Firestore書込み権限からトークン窃取への昇格リスクがあった）。Validate inputsのbash再検証を同じdenylistロジックに置換（文字種・長さチェック含む）。`thinking_level`は変更なし
- `scripts/set-vertex-ai-config.sh`: `MODEL_ID`/`THINKING_LEVEL` の検証を新規追加（`/code-review medium` で発見: 運営者向けの唯一のドキュメント化された直接操作パスが無検証のままだったため、アプリ側検証の緩和により誤入力の実質的なセーフティネットが縮小していた）
- `CareNoteTests/VertexAIConfigServiceTests.swift`: denylist境界テストを`@Test(arguments:)`パラメータ化で追加（将来モデル名の採用・無印gemini-3-flash/gemini-3.0-flash拒否・preview系バイパス拒否・exp系拒否・expansion等の誤検知回避）
- `docs/adr/ADR-012-vertex-ai-config-firestore.md`: 「今回のスコープ外」に記載していた制約の1つが本ADRで解消された旨を追記
- `CLAUDE.md` / `README.md`: allowlist/denylistの説明を実態に合わせて更新

## 次のステップ（本ADRの範囲外）
本変更のマージ後、Build番号を上げてTestFlight・App Store Connectへ提出する（decision-makerがリリース操作を実行）。この審査通過後、prod環境の`platformConfig/vertexAi`シード（Issue #178 Stage 2完了後）をもって、本ADRが意図する「以後のモデル切替をGCP側だけで完結」が本番で有効になる。
