# ADR-004: M4A/AAC 録音フォーマット

## ステータス
Accepted (2026-03-03)

## コンテキスト
録音フォーマットを決定する必要があった。仕様書 v3 以前では WAV を採用していた。

## 決定
**M4A/AAC** (44.1kHz, mono, high quality) を録音フォーマットとして採用する。

## 理由
- ファイルサイズ: WAV 比で約 1/10 (モバイル通信・ストレージに有利)
- 音声品質: AAC High Quality は文字起こしに十分な品質
- 互換性: iOS ネイティブサポート、Gemini も M4A 入力に対応
- アップロード: Cloud Storage へのアップロード時間短縮

## 設定
```swift
[
    .commonFormat: .pcmFormatFloat32,  // 内部処理
    .sampleRate: 44100.0,
    .numberOfChannels: 1,              // mono
    .encoderAudioQualityKey: .high
]
```

## 影響
- `AudioRecorderService`: AVAudioRecorder の設定
- `StorageService`: アップロード時の MIME type (`audio/mp4`)
- `TranscriptionService`: Gemini API への MIME type 指定
