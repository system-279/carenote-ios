# ADR-005: Auth Blocking Function による認証・認可

## ステータス
採用 (2026-03-22) / 実装 (2026-03-31)

## コンテキスト
Firebase Auth の custom claims（tenantId, role）を手動で設定する運用は、ユーザー数の増加に伴いスケールしない。サインイン時に自動でclaims を設定する仕組みが必要。

## 決定
Firebase Auth Blocking Function（`beforeUserSignedIn`）を採用し、サインイン時にFirestoreのホワイトリストおよびallowedDomainsを照合してclaims を自動設定する。

### トリガー
- `beforeUserSignedIn`（v2 Identity trigger）
- リージョン: asia-northeast1

### 処理フロー
1. サインインユーザーのメールアドレスを取得
2. 全テナントを走査
3. `tenants/{tenantId}/whitelist` でメール完全一致を検索
4. 一致 → `{ tenantId, role }` を返す（claims自動設定）
5. 不一致 → `tenants/{tenantId}.allowedDomains` でドメイン一致を検索
6. ドメイン一致 → `{ tenantId, role: "member" }` を返す
7. いずれも不一致 → サインイン拒否

## 検討した代替案

| 方式 | 不採用理由 |
|------|-----------|
| `beforeUserCreated` | 既存ユーザーの再サインインでclaims が更新されない |
| Callable Function | iOS側実装の複雑化、claims反映タイミング不確実 |
| REST API直接呼び出し | GCPトークンがクライアント必要でセキュリティリスク |
| 手動スクリプト | 運用が破綻（ホワイトリスト登録とは別にスクリプト実行が必要） |

## 結果
- 手動claims設定が不要になる
- ロール変更が次回サインイン時に自動反映
- 未登録ユーザーのサインインが自動的に拒否される

## 制約
- テナント数が増加した場合、全テナント走査のパフォーマンスに注意（現時点では問題なし）
- Blocking Functionの実行時間制限（7秒）を超えないこと
