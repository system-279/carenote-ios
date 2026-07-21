# ADR-011: Gemini 3.5 Flash への移行

## ステータス
Accepted (2026-07-21)

**Supersedes**: [ADR-003](./ADR-003-gemini-transcription.md)（Gemini 2.5 Flash 採用）
**Related**: [ADR-012](./ADR-012-vertex-ai-config-firestore.md)（モデル設定の Firestore 化）

## コンテキスト
Google が Gemini 2.5 系のモデルを 2026-10-16 に discontinue すると発表した（`ai.google.dev/gemini-api/docs/deprecations`、2026-07-02 更新時点でも同日付。ただし同ページ自身が "the shutdown dates listed in the table indicate the earliest possible dates" と注記しており、確定日ではなく最早日）。CareNote の文字起こしは ADR-003 で採用した `gemini-2.5-flash` に依存しており、discontinue 後は Vertex AI 呼び出しが失敗するため、期限までに後継モデルへ移行する必要がある。

`gemini-2.5-flash` の後継として `gemini-3.5-flash` を採用する。Gemini 3 Flash / Preview 系モデルは CLAUDE.md Prohibited により使用禁止のため対象外。

## 決定
**Vertex AI Gemini 3.5 Flash** (`gemini-3.5-flash`, `asia-northeast1`) を文字起こしに使用する。

### API 変更点
Gemini 3.5 系では thinking 制御 API が `thinkingConfig.thinkingBudget: Int`（トークン数指定）から `thinkingConfig.thinkingLevel: String`（`"minimal"` 等のレベル指定）に変更された。`TranscriptionService.swift` の `VertexAIRequest.ThinkingConfig` を追従させ、`thinkingBudget: 0` 相当の最小思考量として `thinkingLevel: "minimal"` を設定する。

## 理由
- discontinue 予告への期限内対応が必須（2026-10-16 までに完了しないと文字起こし機能が停止する）
- `gemini-3.5-flash` は `gemini-2.5-flash` と同じ Flash 系列で、マルチモーダル対応・コスト効率等 ADR-003 の採用理由を引き継ぐ
- Gemini 3 Flash / Preview モデルは CLAUDE.md Prohibited により選択肢から除外
- asia-northeast1 での Standard PayGo（オンデマンド従量課金）を実機検証で確認済み（`carenote-dev-279` から `gemini-3.5-flash:generateContent` を実際に呼び出し、レスポンスの `trafficType: "ON_DEMAND"` で確認）。データレジデンシー・WIF 認証・GCS 音声 URI 直接入力など、既存の呼び出し方式をそのまま維持できる
- 代替候補として `gemini-3.1-flash-lite`（音声入力対応、非推奨化されていない、2.5 Flash比で若干安い $0.25/$1.50 という二次情報あり）も検討したが、asia-northeast1 での on-demand 呼び出しが **HTTP 404** となり選択肢から除外

## 制約
- `thinkingLevel` は `minimal` 以外に設定禁止（CLAUDE.md Prohibited、`thinkingBudget: 0` からの読み替え）
- Gemini 3 Flash / Preview モデルの使用禁止
- コスト増を許容した上での移行: Gemini 2.5 Flash（入力 $0.30 / 出力 $2.50 per 1M tokens）比で **入力5倍・出力3.6倍**（Gemini 3.5 Flash: 入力 $1.50 / 出力 $9.00）。性能向上はあるが、コスト増は「若干」ではなく大幅である点に留意

## 影響
- `TranscriptionService`: `model` 定数を `gemini-3.5-flash` に更新、`ThinkingConfig` を `thinkingLevel: String` ベースに変更
- CLAUDE.md / README.md: モデル名・API パラメータ表記を更新
- ADR-003: 本 ADR により superseded、historical record として残置
- 今後同様のモデル強制切替が繰り返される可能性を踏まえ、モデル名を Firestore 設定値化してアプリ更新なしで切替可能にする対応を ADR-012 で別途行う

## 見送った選択肢
- **Cloud Functions 経由でのモデル呼び出し全面移設**: 文字起こし処理自体をサーバーサイド化すれば同様の課題は解消するが、既存アーキテクチャ（iOS → WIF → Vertex AI 直接呼び出し）からの移行コストが大きく、投資対効果が薄いと判断し見送り。モデル名の Firestore 設定化（ADR-012）で軽量に対応する
