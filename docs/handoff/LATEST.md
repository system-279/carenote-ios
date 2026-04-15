# Handoff — Build 34 審査提出準備完了 (2026-04-15)

## セッション成果

### Build 32 再リジェクト → Guest Tenant 戦略で Build 34 作成

Build 32 が 2026-04-07 に再度 Guideline 2.1(a) で却下（Sign in with Apple の赤字メッセージがエラーと判定）。

根本対策として「未登録 Apple ID → 独立した Guest Tenant (`demo-guest`) へ自動プロビジョニング」を設計・実装。Build 33 アップロード後にシーン表示バグを発見し、修正して Build 34 として再アップロード。

| PR | 内容 | 状態 |
|----|------|------|
| #87 | Apple Sign-In 用 Guest Tenant 自動プロビジョニング + アカウント削除 + Apple Refresh Token revoke | ✅ main |
| #88 | RecordingScene/OutputType の英語rawValue表示バグ修正 | ✅ main |
| #89 | ビルド番号 34 同期 | ✅ main |

### 審査通過対策サマリー

| Guideline | 対応 |
|-----------|------|
| **2.1(a) App Completeness** | demo-guest 自動プロビジョニングで Apple Sign-In が常時成功 |
| **4.8 Login Services** | Sign in with Apple 存続（Google 併用時の要件）|
| **5.1.1(v) Account Deletion** | Firebase Auth + Firestore + Storage + Apple refresh token revoke 全対応 |
| **2.3 Accurate Metadata** | UI 文言に審査特化表現なし（意図は ADR-007 に記録）|

### デプロイ済みインフラ

- **Cloud Functions Dev/Prod**: `beforeSignIn` (Apple分岐) / `deleteAccount` (callable)
- **Firestore Dev/Prod**: `tenants/demo-guest` ドキュメント作成済み
- **Prod whitelist**: `hy.unimail.11@gmail.com` を削除（本人の Apple 検証用に demo-guest 経路へ誘導）
- **Dev user customAttributes**: `hy.unimail.11@gmail.com` の永続 claims をクリア（テスト用）

## 現在の状態

- **ブランチ**: main
- **ビルド**: Build 34（App Store Connect にアップロード済、処理中〜ready to submit）
- **審査提出**: 未実施（ユーザー側操作待ち）

## 審査提出前チェックリスト（ユーザー操作）

1. App Store Connect で Build 34 が「提出準備完了」になることを確認
2. iOS App バージョン 1.0 の Build セクションで **Build 34** を選択
3. What's New に変更点を記載（例: Sign in with Apple ログイン体験の改善、アカウント削除機能追加、シーン表示修正）
4. Review Notes の内容確認（`docs/appstore-metadata.md` 反映済み）
5. 「App Review に再提出」

## オープンIssue

| # | タイトル | ラベル | 優先度 |
|---|---------|--------|-------|
| #71 | upload-testflight.sh に entitlements 検証ステップを追加 | P1, bug | 既存 |
| #65 | Apple ID アカウントリンク | enhancement | 将来対応 |
| #90 | Guest Tenant のスパム対策: TTL / レート制限 | enhancement | P2 |
| #91 | アカウント削除後のローカル SwiftData / Outbox クリーンアップ | bug | **P1**（セキュリティリスク） |
| #92 | Guest Tenant 利用者向けの「本番ログイン不可」案内UI | enhancement | P2 |
| #93 | deleteAccount Cloud Function の単体テスト追加 | enhancement | P2 |

## 審査通過見込み

**85〜90%**

残リスク (10〜15%):
- 実機 iPad Air M3 + iPadOS 26.4 での未検証（前回リジェクト環境）
- Guest Tenant 設計へのレビュアー解釈ミス（Review Notes で対策済）

## 次セッション推奨アクション

### 審査通過時
1. TestFlight で社内検証配布
2. Issue #91（Outbox クリーンアップ）を最優先で対応（セキュリティリスク）
3. Issue #90 / #92 の対応
4. #43 Google Docs エクスポート等、次機能へ

### 審査リジェクト時
1. リジェクト理由を精読
2. 5.1.1(v) 指摘の場合 → Apple revoke はベストエフォート実装済のため、実装詳細を Review Notes で説明
3. 2.1(a) 別観点の場合 → 指摘内容を ADR-007 の想定外ケースとして対応
4. `/codex review` で外部視点セカンドオピニオン取得

## 参考資料

- [PR #87 Guest Tenant 実装](https://github.com/system-279/carenote-ios/pull/87)
- [ADR-007 Guest Tenant 設計判断](../adr/ADR-007-guest-tenant-for-apple-signin.md)
- [Review Notes](../appstore-metadata.md)
