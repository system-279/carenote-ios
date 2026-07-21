# ADR-012: Vertex AI モデル設定の Firestore 化

## ステータス
Accepted (2026-07-21)

**Related**: [ADR-011](./ADR-011-gemini-3-5-flash-migration.md)（Gemini 3.5 Flash 移行）

## コンテキスト
ADR-011 で対応した Gemini 2.5→3.5 Flash 移行のように、Google 側の都合によるモデル強制切替は今後も発生しうる。現状モデル名・`thinkingLevel` は `TranscriptionService.swift` にハードコードされており、切替のたびに iOS アプリのビルド・App Store 審査を経る必要があり運用負荷が高い。

Cloud Functions 経由で文字起こし処理自体をサーバーサイド化する全面移設も検討したが、既存アーキテクチャ（iOS → WIF → Vertex AI 直接呼び出し）からの移行コストに対して投資対効果が薄いと判断し見送った（ADR-011「見送った選択肢」）。

## 決定
モデル名・`thinkingLevel` を Firestore の `platformConfig/vertexAi`（テナント非依存、トップレベルコレクション）に設定値として持たせ、運営者が admin SDK 経由のスクリプト (`scripts/set-vertex-ai-config.sh`) でのみ更新できるようにする。iOS アプリはこの値を fetch して文字起こし呼び出しに反映するが、CLAUDE.md Prohibited 制約を担保するため必ず allowlist 検証を通す。

### 設計判断

1. **`transcriptionModelId` の記録は録音作成時 (`FirestoreService.createRecording`) のみ。`updateTranscription` は変更しない。** `RecordingListViewModel.saveTranscription()`（文字起こしの手動編集経路）も `updateTranscription` を呼ぶため、ここに必須パラメータを足すと意味論が破綻する。作成時一括書込みにすればこの問題を構造的に回避できる。
2. **`RecordingRecord`（SwiftData）へのフィールド追加はしない。** 値は Firestore のみで完結し、UI 表示要件もない。
3. **`revision` フィールドは見送り（YAGNI）。** プロンプトは既に `templatePromptSnapshot` でスナップショット済みで、`thinkingLevel` は事実上 `minimal` 固定のため、`transcriptionModelId` 単体で監査要件を満たせる。
4. **allowlist は `modelId`・`thinkingLevel` 両方に必須、完全一致。** 2つは独立した禁止事項（モデル名 / thinkingLevel 値）であり、`modelId` だけの検証では `thinkingLevel: "high"` のような設定が素通りしてしまう。
5. **キャッシュは `VertexAIConfigService.shared`（actor）+ メモリキャッシュのみ。永続化はしない。** `OutboxSyncService` はオンライン時のみ動作するため「オフライン時の config」はほぼ発生しない。
6. **allowlist が担保するのは CLAUDE.md Prohibited への準拠であり、ランタイム動作の保証ではない。** allowlist 内のモデルでもリージョン非対応等で実行時に失敗しうる（ADR-011 の `gemini-3.1-flash-lite` 404 の前例）。この場合は Firestore 設定を直せば復旧でき、アプリリリースは不要。自動リトライ等の追加保護は今回 YAGNI で見送った。

## 理由
- App Store 審査を経ずにモデル切替できることで、次回以降の discontinue 対応の運用負荷を大幅に下げられる
- allowlist 検証 + ソフトフェイルにより、Firestore 設定が不正でも CLAUDE.md Prohibited 違反や機能停止を起こさない
- Cloud Functions 全面移設と比べて実装コストが小さく、既存アーキテクチャへの変更を最小化できる

## 制約
- allowlist（`CareNote/Models/VertexAIConfig.swift`）は CLAUDE.md Prohibited の2制約と常に整合させる。Prohibited を変更する際は allowlist も同時に更新すること
- `platformConfig/vertexAi` へのクライアントからの書込みは Firestore Rules で全拒否（`allow write: if false`）。更新は運営者が `scripts/set-vertex-ai-config.sh` を実行する運用のみ

## /code-review 対応（2026-07-21）

`/code-review xhigh` で発見された5件の実質的な問題を修正した:

- **設計判断5の訂正**: 「メモリキャッシュのみ・永続化しない」自体は変更しないが、fetch失敗・allowlist不正値は**キャッシュしない**ように修正した（`VertexAIConfigService.resolveConfig()`）。修正前は失敗時のフォールバック値 (`.default`) も成功時と区別なく永続キャッシュしており、コールドスタート時の一過性障害（ネットワーク瞬断・Firestore認証未完了等）が発生すると、プロセス生存中ずっと `.default` に固定され復旧後も再fetchされなかった。加えて allowlist 不正値のフォールバックはログも一切残らず、運営者が設定ミスに気づく手段がなかった（ログを追加）。
- **`firestore-op.yml` の `set-vertex-ai-config` 操作**: `model_id`/`thinking_level` を `type: string` から `type: choice`（allowlist と同じ値を選択肢化）に変更し、Validate inputs ステップにも二重チェックを追加。従来は allowlist 外の値を書き込んでも CI は緑（自己言及的な verify のみ）になり、クライアント側は無ログでソフトフェイルするため運営者が気づけなかった。
- **`scripts/set-vertex-ai-config.sh`**: (a) `MODEL_ID`/`THINKING_LEVEL` の JSON 組立を生文字列結合から `jq -n --arg` に変更（ダブルクォート等を含む値でのペイロード破壊を防止）。(b) `curl` のレスポンスを HTTP ステータスとともに取得し、4xx/5xx 時は明示的にエラー終了するよう変更（従来は失敗時も `✅` 成功表示が出ていた）。
- **`firestore.rules`**: `recordings` の `allow update` に `transcriptionModelId` の不変性チェックを追加（`createdBy` と同じ pre/post 判定パターン）。従来は client 経由で作成後に自由に書き換え可能で、監査保証が rules レベルでは担保されていなかった。`functions/test/firestore-rules.test.js` にテストケースを追加。

なお、以下は今回のスコープ外として残す（別途対応が必要な既知の制約）:
- `allowedModelIds`/`allowedThinkingLevels` が Swift ソースにハードコードされているため、真に新規のモデルIDへの切替は依然としてアプリのソース変更・再ビルドを要する（ADR-011 のシナリオそのものを完全には解決しない）
- `OutboxSyncService` の `transcriptionModelId` が `transcriptionService` から独立したパラメータであり、両者の一致を強制する仕組みがない
- リトライ（`RecordingListViewModel.retryRecording()`）後に別モデルで文字起こしが行われても `transcriptionModelId` は作成時の値のまま更新されない

## 影響
- `CareNote/Models/VertexAIConfig.swift`（新規）: 設定値の型・デフォルト・allowlist
- `CareNote/Services/VertexAIConfigService.swift`（新規）: fetch → allowlist検証 → メモリキャッシュ → ソフトフェイル
- `CareNote/Services/FirestoreService.swift`: `fetchVertexAIConfig()` 追加、`FirestoreRecording.transcriptionModelId` の読み書き
- `CareNote/Services/TranscriptionService.swift`: `model`/`thinkingLevel` を注入可能に変更（デフォルト値あり）
- `CareNote/Services/OutboxSyncService.swift`: `transcriptionModelId` を受け取り録音作成時に記録
- `CareNote/Features/RecordingConfirm/RecordingConfirmViewModel.swift`: `defaultSyncServiceFactory` を async化し config 解決を組み込み
- `firestore.rules`: `platformConfig/{docId}` の読み取り専用ルール追加
- `scripts/set-vertex-ai-config.sh`（新規）: 運営者によるモデル切替スクリプト
