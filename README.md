# CareNote

ケアマネジャー向け録音・文字起こし iOS アプリ。

## 技術スタック

| カテゴリ | 技術 |
|---------|------|
| 言語 | Swift 6+ |
| UI | SwiftUI |
| アーキテクチャ | MVVM + Repository パターン (`@Observable`) |
| ローカル DB | SwiftData |
| 認証 | Google Sign-In → Firebase Auth |
| バックエンド | Firebase (Firestore, Storage) |
| 文字起こし | Vertex AI Gemini 2.5 Flash |
| GCP 認証 | Workload Identity Federation (WIF) |
| 録音 | AVAudioRecorder (M4A/AAC) |

## 前提条件

- macOS 15+ (Tahoe)
- Xcode 26.3+
- Swift 6.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- gcloud CLI (Firebase / GCP 操作用)

## セットアップ

```bash
# 1. リポジトリクローン
git clone https://github.com/system-279/carenote-ios.git
cd carenote-ios

# 2. Xcode プロジェクト生成
xcodegen generate

# 3. ビルド (CLI)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild build \
  -project CareNote.xcodeproj \
  -scheme CareNote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO

# 4. GoogleService-Info.plist を CareNote/ に配置 (Firebase Console から取得)
```

## ディレクトリ構成

```
CareNote/
├── App/          # @main, AppConfig
├── Features/     # 画面別モジュール
│   ├── Auth/           # Google Sign-In
│   ├── ClientSelect/   # 利用者選択
│   ├── SceneSelect/    # 場面選択
│   ├── Recording/      # 録音
│   ├── RecordingConfirm/ # 録音確認
│   └── RecordingList/  # 録音一覧
├── Services/     # ビジネスロジック
├── Repositories/ # SwiftData 抽象化層
├── Models/       # SwiftData @Model, Firestore Codable
└── Infrastructure/ # 環境管理
```

## GCP プロジェクト

| 環境 | プロジェクト ID | プロジェクト番号 |
|------|----------------|-----------------|
| Dev | `carenote-dev-279` | `444137368705` |
| Prod | `carenote-prod-279` | `781674225072` |

## ライセンス

Private
