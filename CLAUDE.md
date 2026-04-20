# CareNote iOS - Claude Code Project Context

## Project Overview
- **App**: CareNote - ケアマネジャー向け録音・文字起こしアプリ
- **Platform**: iOS 17+
- **Language**: Swift 6+ / SwiftUI
- **Architecture**: MVVM with `@Observable` + Repository pattern
- **Package Manager**: Swift Package Manager

## Build & Test (XcodeBuildMCP)
このプロジェクトではすべての Xcode 操作に XcodeBuildMCP を使用する。
- Build: `mcp__xcodebuildmcp__build_sim_name_proj`
- Test: `mcp__xcodebuildmcp__test_sim_name_proj`
- Run: `mcp__xcodebuildmcp__build_run_sim_name_proj`
- Screenshot: `mcp__xcodebuildmcp__screenshot`

## Key Dependencies (SPM)
- Firebase iOS SDK 11.x+ (FirebaseAuth, FirebaseFirestore, FirebaseStorage)

## Directory Structure
```
CareNote/
├── App/          # @main, AppConfig
├── Features/     # 画面別 (Auth, ClientSelect, SceneSelect, Recording, RecordingConfirm, RecordingList)
│   └── {Feature}/
│       ├── {Feature}ViewModel.swift
│       └── {Feature}View.swift
├── Services/     # ビジネスロジック (AudioRecorder, WIFAuth, Transcription, Storage, Firestore, ClientCache, OutboxSync)
├── Repositories/ # SwiftData 抽象化層 (RecordingRepository, ClientRepository)
├── Models/       # SwiftData @Model, Enum, Firestore Codable
└── Infrastructure/ # 環境管理
```

## Coding Standards
- `@Observable` を使用（`ObservableObject` / `@Published` は使わない）
- `async/await` + `actor` で concurrency 管理
- SwiftData は Repository 層経由（View に `@Query` を直接使わない）
- `tenantId` のハードコーディング禁止（パラメータで受け取る）
- Swift Testing (`@Test`, `#expect`) を使用

## Multi-Tenant Architecture
- Firestore: `tenants/{tenantId}/...` 構造
- tenantId は Firebase Auth custom claim から取得
- セキュリティルール: テナントメンバーのみアクセス可

## Cloud Services
- **文字起こし**: Vertex AI Gemini 2.5 Flash (`gemini-2.5-flash`, asia-northeast1)
- **認証フロー**: Firebase Auth → WIF (STS token exchange) → SA Impersonation → GCP Access Token
- **ストレージ**: Cloud Storage for Firebase (`{project}-audio` バケット)
- **録音フォーマット**: M4A/AAC (44.1kHz, mono, high quality)

## TestFlight Deploy
- スクリプト: `./scripts/upload-testflight.sh`
- ビルド番号自動インクリメント → XcodeGen → Archive → App Store Connect Upload
- App Store Connect アプリ名: **CareNote AI** (Bundle ID: `jp.carenote.app`)
- Team ID: `C96A7EHVW8`

## GCP Projects
- Dev: `carenote-dev-279`
- Prod: `carenote-prod-279`
- GCP アカウント: `system@279279.net`（dev/prod 共通）
- GitHub アカウント: `system-279`

## Dev/Prod 分離（厳守）
dev/prod で同一 GCP アカウントを使用するため、操作ミスで prod を壊さないよう以下を厳守。

- `.envrc` で `carenote-dev` gcloud config が自動 active（project=`carenote-dev-279`）
- **prod 操作は常にコマンド単位で明示する**:
  - gcloud: `CLOUDSDK_ACTIVE_CONFIG_NAME=carenote-prod <cmd>` または `--project=carenote-prod-279`
  - Firebase: `firebase deploy -P prod`
- **`carenote-prod-279` / `carenote-prod` をコマンドに含める前に必ずユーザー確認**
- `gcloud config set project` で active config の project を上書きしない（prod 用は `carenote-prod` config 側に固定済み）
- `gcloud config configurations activate carenote-prod` を常用シェルで実行しない（一時的に触るときも `<cmd>` の先頭に env 変数で指定）
- 読み取り（Firestore `documents GET` 等）であっても prod に触る前に確認

## Prohibited
- `tenantId` ハードコーディング
- サービスアカウントキー（JSON）のアプリ同梱
- 音声ファイルの Firestore 保存（Cloud Storage を使用）
- `thinkingBudget` を 0 以外に設定
- Gemini 3 Flash / Preview モデルの使用
- `@Query` の View 直接使用
