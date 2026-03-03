# ADR-003: Gemini 2.5 Flash による文字起こし

## ステータス
Accepted (2026-03-03)

## コンテキスト
録音音声の文字起こしサービスを選定する必要があった。仕様書 v3 では Cloud Speech-to-Text V2 を採用していた。

## 決定
**Vertex AI Gemini 2.5 Flash** (`gemini-2.5-flash`, `asia-northeast1`) を文字起こしに使用する。

## 理由
- マルチモーダル対応: 音声ファイルを直接入力可能
- 高精度: 介護現場の専門用語に対応しやすい
- コスト効率: Flash モデルは低コスト・高速
- プロンプトエンジニアリング: 発話者分離、要約等を柔軟に制御可能

## 制約
- `thinkingBudget` は 0 に設定 (CLAUDE.md Prohibited)
- Gemini 3 Flash / Preview モデルは使用禁止

## 影響
- `TranscriptionService`: Vertex AI REST API 経由で Gemini 呼び出し
- 録音フォーマット: M4A/AAC (ADR-004 参照)
