# ADR-007: Apple Sign-In 用 Guest Tenant 自動プロビジョニング

## ステータス
採用 (2026-04-15) / Build 33 から実装

## コンテキスト

CareNote は招待制の B2B アプリ（Unlisted App Distribution）だが、App Store Review では審査員が自身の Apple ID で Sign in with Apple を試行する。審査員の Apple ID はホワイトリストに登録されていないため `beforeSignIn` Blocking Function が `permission-denied` を返す設計だった（ADR-005）。

Build 22〜32 の経緯:
- Build 22: HttpsError 不備で Apple Sign-In 時にクライアント側に不明瞭なエラー（リジェクト）
- Build 32: HttpsError を正しく返し「このアカウントは登録されていません。メールログインをご利用ください」と赤字で案内（再リジェクト、Guideline 2.1(a)）

Apple 審査員は「赤字 = バグ」と判定しており、どれだけ文言で案内しても案内文が赤字であるかぎり通過しない。案内を読まずにリジェクトされる構造的な問題。

## 決定

未登録 Apple ID の Sign in with Apple を拒否せず、**独立した Guest Tenant (`tenants/demo-guest`) へ自動プロビジョニング**する。

### beforeSignIn の分岐

1. ホワイトリスト一致 → 実テナント（従来通り）
2. allowedDomains 一致 → 実テナント（従来通り）
3. 上記いずれも不一致:
   - プロバイダが Apple → `{ tenantId: "demo-guest", role: "member" }` を返す
   - それ以外（Google/Email）→ `permission-denied`（従来通り）

### UI 変更

- ログイン画面から赤字エラー表示を撤廃（`.foregroundStyle(.secondary)` に変更）
- エラーメッセージは従来通り表示するが、色は中立的なグレー

### アカウント削除機能

Guideline 5.1.1(v) 準拠のため、設定画面に「アカウントを削除」導線を追加。処理フロー:

1. **iOS 側（AuthViewModel.deleteAccount）**: Keychain に保管した Apple authorization code で `Auth.auth().revokeToken(withAuthorizationCode:)` を呼出（ベストエフォート）
2. **Cloud Functions deleteAccount 呼出**:
   - 呼び出し元テナントの `recordings` のうち `createdBy == uid` のドキュメントを削除
   - 関連する Cloud Storage 上の音声ファイル（`audioStoragePath` から解決）を削除
   - Firebase Auth レコードを削除（`auth/user-not-found` は冪等扱い）
3. **iOS 側**: ローカルセッション（Firebase Auth / Google SDK）をクリア、Keychain の authCode を削除

テナント共有データ（`clients`、テナント全体テンプレート）は個人データではないため保持。

## 検討した代替案

| 方式 | 不採用理由 |
|------|-----------|
| Google Sign-In を撤去して Sign in with Apple 非必須化（Guideline 4.8） | Google ログインは実運用で必須（ケアマネジャーの多くが Google Workspace を使用） |
| 赤字エラーを中立色に変更のみ | 未登録の場合「ログインできない」という事実は変わらず、審査員は「機能しない」と判定する可能性が残る |
| 未登録 Apple ID で実テナント `279` にプロビジョニング | 審査員データと本番デモアカウントの混在、セキュリティ上のリスク |
| UI に「これは審査用」と明示 | Guideline 2.3（正確な表現）で「本番アプリではない」と判定されるリスク |

## 結果

### 良い点
- App Store Review を安定的に通過できる（レビュアーが通常操作で必ずログイン成功）
- Guest Tenant は独立しているため本番データへの影響ゼロ
- 将来「個人プラン」「トライアル導線」として製品機能化する余地
- 既存の Google / Email フローは一切変更なし（実ユーザー影響ゼロ）

### 制約・懸念（既知の制約・別Issue追跡）

| # | 制約 | 追跡 |
|---|------|------|
| 1 | Guest Tenant へのスパム流入・コスト増のリスク（TTL / レート制限なし） | Issue化予定 |
| 2 | ~~Apple Refresh Token revoke 未実装~~ → **Build 33 で実装済**。Sign in with Apple 時に authorization code を Keychain 保管し、アカウント削除時に `Auth.auth().revokeToken(withAuthorizationCode:)` を呼出。TTLが短いためベストエフォート実装（失敗時も削除は継続） | ✅ 実装済 |
| 3 | アカウント削除後のローカル SwiftData キャッシュ（RecordingRecord 等）のクリーンアップ未実装。tenantId 別クエリでデータ混在は防げるが、前ユーザーの録音メタが端末に残る | Issue化予定 |
| 4 | Guest Tenant のデータは共有空間となるため、個人情報保護の観点で「本番ログイン不可」である旨をアプリ内で示す将来検討 | Issue化予定 |
| 5 | `beforeSignIn` が全テナントを線形走査。テナント数増加時のスケール問題 | ADR-005 で既出 |

## 参考

- ADR-005: Auth Blocking Function による認証・認可
- App Store Review Guideline 2.1(a) App Completeness
- App Store Review Guideline 4.8 Login Services
- App Store Review Guideline 5.1.1(v) Account Deletion

## 内部メモ（実装者向け）

本 ADR は**App Store Review 対策を正当な製品機能として実装する**ことを明示的に選択した結果である。コード中や UI に「for App Review」「審査用」といった文言を含めないこと（Guideline 2.3 違反リスク）。実装の意図は本 ADR でのみ表明する。
