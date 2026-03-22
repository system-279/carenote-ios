# ADR-005: Auth Blocking Function によるホワイトリスト照合・自動 claims 設定

## ステータス
採用 (2026-03-22)

## コンテキスト
テナントごとにメールアドレスのホワイトリストを管理し、許可されたユーザーのみサインイン可能にする必要がある。
従来は Firebase Auth の custom claims をスクリプト (`set-tenant-claim.sh`) で手動設定していたが、admin がアプリ内でメンバー登録した際に別途スクリプト実行が必要で運用が破綻していた。

## 決定
Firebase Cloud Functions v2 の **Blocking Function (`beforeUserSignedIn`)** を採用し、毎回のサインイン時にホワイトリスト照合と custom claims 自動設定を行う。

### フロー
1. admin がアプリ内でメールアドレス + ロールをホワイトリストに登録（Firestore）
2. ユーザーが Google Sign-In を実行
3. `beforeUserSignedIn` が発火
4. 全テナントの `whitelist` コレクションからメールを検索
5. 一致 → `tenantId` + `role` を custom claims に設定 → サインイン許可
6. 不一致 → サインイン拒否（Firebase Auth レベル）

### ロール管理
- Firestore `tenants/{tenantId}/whitelist/{docId}` の `role` フィールドが権威ソース
- custom claims は Blocking Function が毎回サインイン時に上書き
- ロール変更はアプリ内で即座に Firestore を更新、次回サインインで反映

## 検討した代替案

| 方式 | 不採用理由 |
|------|-----------|
| `beforeUserCreated` | 新規ユーザー作成時のみ発火。既存ユーザーの再サインインに対応不可 |
| Callable Function | iOS 側の変更が必要。サインインフロー外で呼び出すため claims 反映タイミングが不確実 |
| REST API 直接呼び出し | GCP トークンがクライアントに必要でセキュリティリスク高 |
| 手動スクリプト | 運用が破綻（ホワイトリスト登録とは別にスクリプト実行が必要） |

## 影響
- `functions/index.js` に `beforeUserSignedIn` を追加
- Firebase Auth の Blocking Function として登録
- サインインのレイテンシが若干増加（Firestore クエリ分）
- テナント数が増加した場合、全テナント走査の最適化が必要（collectionGroup query 等）
