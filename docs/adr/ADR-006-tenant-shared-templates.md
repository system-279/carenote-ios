# ADR-006: テナント共有テンプレート（2層管理）

- **Status**: Accepted
- **Date**: 2026-03-28

## コンテキスト

文字起こしプロンプトのカスタムテンプレートは SwiftData（デバイスローカル）のみに保存されていた。テナント内の他ユーザーと共有できず、管理者が組織標準のテンプレートを配布する手段がなかった。

## 決定

テンプレートを**テナント共有（Firestore）** と**個人（SwiftData）** の2層で管理する。統合表示用に `TemplateItem` 型を導入し、プリセット・テナント共有・個人テンプレートを統一的に扱う。

### データ構造

| 種別 | 保存先 | 管理者 |
|------|--------|--------|
| プリセット | アプリ内ハードコード | 開発者 |
| テナント共有 | Firestore `tenants/{tenantId}/templates/` | admin |
| 個人 | SwiftData `OutputTemplate` | 各ユーザー |

### 権限

- テナント共有: admin のみ作成・編集・削除。メンバー全員が閲覧・利用可能
- 個人: 全ユーザーが作成・削除可能

### TemplateItem 統合型

`TemplateItem` は `OutputTemplate`（ローカル）と `FirestoreTemplate`（リモート）を統一的に扱うための値型。`source` enum（`.preset` / `.tenant` / `.personal`）で出所を区別し、`id` は `"\(source):\(rawId)"` 形式で名前空間を分離する。

## 検討した代替案

| 方式 | 不採用理由 |
|------|-----------|
| 全テンプレートを Firestore に移行 | オフライン時にテンプレートが使えなくなる。既存の SwiftData テンプレートとの互換性も問題 |
| 個人テンプレートも Firestore に保存 | `tenants/{tenantId}/users/{userId}/templates/` 構造はFirestoreの読み取りコスト増。現時点では複数デバイス同期の需要が低い |
| プロトコル準拠で統合 | `OutputTemplate` は `@Model`（class）、`FirestoreTemplate` は struct のため、共通プロトコルではスナップショット保存時の値セマンティクスが複雑化 |

## 影響

- `FirestoreModels.swift`: `FirestoreTemplate`, `TemplateItem` 追加
- `FirestoreService.swift`: テンプレート CRUD 4メソッド追加
- `firestore.rules`: `templates` コレクションルール追加
- `TemplateListView/ViewModel`: 3セクション表示
- `TemplateCreateView/ViewModel`: 保存先選択・編集モード
- `RecordingConfirmView/ViewModel`: `TemplateItem` ベースの統合表示
- `RecordingRecord.templateId`: ローカルテンプレート選択時のみ UUID 保存（テナント共有時は nil）
