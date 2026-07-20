# ADR-011: Gemini 3.5 Flash への移行

## ステータス
Accepted (2026-07-21)

**Supersedes**: [ADR-003](./ADR-003-gemini-transcription.md)（Gemini 2.5 Flash 採用）
**Related**: [ADR-012](./ADR-012-vertex-ai-config-firestore.md)（モデル設定の Firestore 化）

## コンテキスト
Google が Gemini 2.5 系のモデルを 2026-10-16 に discontinue すると発表した。CareNote の文字起こしは ADR-003 で採用した `gemini-2.5-flash` に依存しており、discontinue 後は Vertex AI 呼び出しが失敗するため、期限までに後継モデルへ移行する必要がある。

`gemini-2.5-flash` の後継として `gemini-3.5-flash` を採用する。Gemini 3 Flash / Preview 系モデルは CLAUDE.md Prohibited により使用禁止のため対象外。

## 決定
**Vertex AI Gemini 3.5 Flash** (`gemini-3.5-flash`, `asia-northeast1`) を文字起こしに使用する。

### API 変更点
Gemini 3.5 系では thinking 制御 API が `thinkingConfig.thinkingBudget: Int`（トークン数指定）から `thinkingConfig.thinkingLevel: String`（`"minimal"` 等のレベル指定）に変更された。`TranscriptionService.swift` の `VertexAIRequest.ThinkingConfig` を追従させ、`thinkingBudget: 0` 相当の最小思考量として `thinkingLevel: "minimal"` を設定する。

## 理由
- discontinue 予告への期限内対応が必須（2026-10-16 までに完了しないと文字起こし機能が停止する）
- `gemini-3.5-flash` は `gemini-2.5-flash` と同じ Flash 系列で、マルチモーダル対応・コスト効率等 ADR-003 の採用理由を引き継ぐ
- Gemini 3 Flash / Preview モデルは CLAUDE.md Prohibited により選択肢から除外

## 制約
- `thinkingLevel` は `minimal` 以外に設定禁止（CLAUDE.md Prohibited、`thinkingBudget: 0` からの読み替え）
- Gemini 3 Flash / Preview モデルの使用禁止

## 影響
- `TranscriptionService`: `model` 定数を `gemini-3.5-flash` に更新、`ThinkingConfig` を `thinkingLevel: String` ベースに変更
- CLAUDE.md / README.md: モデル名・API パラメータ表記を更新
- ADR-003: 本 ADR により superseded、historical record として残置
- 今後同様のモデル強制切替が繰り返される可能性を踏まえ、モデル名を Firestore 設定値化してアプリ更新なしで切替可能にする対応を ADR-012 で別途行う

## 見送った選択肢
- **Cloud Functions 経由でのモデル呼び出し全面移設**: 文字起こし処理自体をサーバーサイド化すれば同様の課題は解消するが、既存アーキテクチャ（iOS → WIF → Vertex AI 直接呼び出し）からの移行コストが大きく、投資対効果が薄いと判断し見送り。モデル名の Firestore 設定化（ADR-012）で軽量に対応する
