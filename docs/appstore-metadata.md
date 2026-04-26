# App Store Connect メタデータ

## 基本情報

| 項目 | 値 |
|------|-----|
| アプリ名 | CareNote AI |
| サブタイトル | ケアマネジャー向け録音・文字起こし |
| Bundle ID | jp.carenote.app |
| カテゴリ（プライマリ） | ビジネス |
| カテゴリ（セカンダリ） | 仕事効率化 |
| 年齢区分 | 4+ |
| 配布方式 | Unlisted App Distribution |

## URL

| 項目 | URL |
|------|-----|
| プライバシーポリシー | https://carenote-prod-279.web.app/privacy.html |
| サポート | https://carenote-prod-279.web.app/ |

## 説明文（日本語）

CareNote AIは、ケアマネジャーの記録業務を効率化するアプリです。

訪問や会議の音声をワンタップで録音し、AI（Google Vertex AI Gemini）が高精度に文字起こしを行います。介護現場特有の用語にも対応し、議事録や面談記録などの作成時間を大幅に削減します。

主な機能:
- 高品質な音声録音（M4A/AAC形式）
- AIによる自動文字起こし
- 用途別の出力テンプレート（議事録、面談記録、モニタリングなど）
- テナント（事業所）単位のデータ管理
- チームでのテンプレート共有

セキュリティ:
- Google Sign-Inによる認証
- テナント単位のアクセス制御
- データは日本リージョン（東京）に保存
- 転送時・保存時ともに暗号化

本アプリは事業所単位でご利用いただけます。ご利用をご希望の場合は、サポートまでお問い合わせください。

## キーワード

ケアマネジャー,録音,文字起こし,介護,ケアノート,AI,議事録,面談記録,ケアマネ

※ 100文字以内、カンマ区切り

## プロモーションテキスト（オプション）

ケアマネジャーの記録業務をAIで効率化。訪問・会議の録音をワンタップで文字起こし。

## App Privacy（データ収集申告）

### 収集するデータ

| データタイプ | 具体的な内容 | 利用目的 | ユーザーにリンク |
|------------|-------------|---------|--------------|
| 連絡先情報 | メールアドレス | アプリ機能（認証） | はい |
| ユーザーコンテンツ | 音声、その他のユーザーコンテンツ | アプリ機能 | はい |
| 識別子 | ユーザーID | アプリ機能 | はい |

### トラッキング
- トラッキングなし（ATT不要）

## スクリーンショット

### 必要サイズ
- iPhone 6.7インチ（必須）: 1290 x 2796 px
- iPhone 6.5インチ（推奨）: 1284 x 2778 px

### 撮影対象画面
1. サインイン画面
2. 利用者選択画面
3. 録音画面
4. 文字起こし結果画面
5. テンプレート選択画面

## 審査メモ（Review Notes）

> **運用ノート**: 本セクションは App Store Connect の「App Reviewに関する情報 → メモ」欄に貼り付ける完全版。次回審査提出時はこのセクション全文を copy & paste する。
>
> **重要**: 提出前に必ず `demo-reviewer@carenote.jp` の権限を**両系統で確認**すること:
> - Firestore: `tenants/279/whitelist/{id}` の `role` が `admin`
> - Firebase Auth: customAttributes が `{"tenantId":"279","role":"admin"}`
>
> 権限判定の実体は **Firebase Auth custom claim** (`firestore.rules` の `isAdmin()` 参照)。whitelist の role は admin UI 表示用なので、実権限と乖離しないよう両方を一致させる。

```
For App Review: Please use the demo account via "Email Login" on the sign-in screen for the full review.

This is an invite-only business app distributed as Unlisted. Access is managed per organization (tenant), and only pre-registered accounts can sign in.

本アプリは招待制の業務用アプリです（Unlisted App Distribution）。
事業所（テナント）単位で利用者を管理しており、管理者が事前に登録したアカウントのみサインインできます。

【テスト用デモアカウント / Demo Account for Review】
- メール / Email: demo-reviewer@carenote.jp
- パスワード / Password: CareNote2026Review!
- 権限 / Role: 管理者 (admin) — tenant 279
- ログイン方法 / How to sign in:
  1. サインイン画面下部の「メールでログイン / Email Login」をタップ
  2. 上記メールアドレスとパスワードを入力
  3. 「ログイン」ボタンをタップ

【Sign in with Apple について / About Sign in with Apple】
- Sign in with Apple は誰でも利用可能です。未登録の Apple ID でサインインすると、体験用の独立したテナント（Guest Tenant）に自動的に割り当てられ、全機能を試用できます。
- Sign in with Apple is available to everyone. When an unregistered Apple ID signs in, the user is automatically assigned to an isolated Guest Tenant where all app features can be tried.

【Google Sign-In について / About Google Sign-In】
- Google Sign-In は招待制です（事前に管理者に登録されたアカウントのみ利用可能）。
- Google Sign-In is invite-only (only accounts pre-registered by an administrator can sign in).

【推奨される審査手順 / Recommended Review Steps】
1. Sign in with Apple でレビュアーご自身の Apple ID からサインイン（自動で Guest Tenant へ割り当て）
2. または、上記デモアカウント（メール/パスワード）でメールログインから全機能をテスト

【v1.0.1 新機能 / What's New in v1.0.1】

■ アカウント引き継ぎ機能 (admin 専用) / Account Transfer (Admin Only)
管理者が、改姓・組織変更等で uid が変わったメンバーのデータ（録音・テンプレート・ホワイトリスト登録）を旧 uid から新 uid に引き継げる機能を追加しました。

A new admin-only feature allowing administrators to transfer data (recordings, templates, whitelist entries) from an old user uid to a new uid (for cases like name change or account migration).

[テスト手順 / Test Steps]
1. 上記デモアカウント (demo-reviewer@carenote.jp) でメールログイン
   Sign in with the demo account above via Email Login
2. 画面下部のタブから「設定」を開く
   Open "Settings" from the bottom tab bar
3. 管理者メニュー内の「アカウント引き継ぎ」をタップ
   Tap "アカウント引き継ぎ / Account Transfer" in the Admin Menu section
4. 旧 uid 入力欄に "test-old-uid"、新 uid 入力欄に "test-new-uid" を入力
   Enter "test-old-uid" in the old uid field and "test-new-uid" in the new uid field
5. 「件数プレビュー (dryRun)」ボタンをタップ
   Tap "件数プレビュー (dryRun)" button
6. UI がエラーメッセージを表示すること（存在しない uid のため、入力検証が機能していることが確認できます）
   The UI displays an error message (confirming input validation works for non-existent uids)

[Important / 重要]
- 「件数プレビュー」(dryRun) は読み取り専用で、データを書き換えません。安全にテスト可能です。
  The "dryRun" button is read-only and does not modify any data. It is safe to test.
- 「引き継ぎを実行」(confirm) ボタンは本番データを書き換えるため、審査中は実行をお控えください。
  Please do NOT tap the "実行 / Execute" button during review, as it modifies production data.

【アカウント削除 / Account Deletion】
- 設定画面の「アカウントを削除 / Delete Account」から、アカウント完全削除が可能です（Guideline 5.1.1(v) 準拠）。
- Account deletion is available under Settings → "アカウントを削除 / Delete Account" (complies with Guideline 5.1.1(v)).
```

### 審査メモの What's New 部分は版ごとに差し替え

新機能を追加するバージョンでは「【vX.Y.Z 新機能】」セクションを追記し、admin 限定機能の場合はテスト手順 + dryRun/confirm 等の安全運用注意を必ず明記する。
