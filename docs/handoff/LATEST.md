# Handoff — Build 35 審査提出完了 (2026-04-16)

## セッション成果

Build 32 再リジェクト（2.1(a)）を受け、Apple 審査通過のための包括的な対策を実装し **Build 35 を App Store Review に提出**。

| PR | 内容 | 状態 |
|----|------|------|
| #87 | Apple Sign-In 用 Guest Tenant 自動プロビジョニング + アカウント削除 + Apple Refresh Token revoke | ✅ main |
| #88 | RecordingScene/OutputType の英語rawValue 表示バグ修正 | ✅ main |
| #89 | ビルド番号 34 同期 | ✅ main |
| #94 | ハンドオフドキュメント更新 | ✅ main |
| #95 | 録音一覧に Firestore → SwiftData 初回同期を追加 | ✅ main |
| #96 | ビルド番号 35 同期 | ✅ main |

### 審査通過対策サマリー

| Guideline | 対応 |
|-----------|------|
| **2.1(a) App Completeness** | demo-guest 自動プロビジョニングで Apple Sign-In が常時成功、赤字エラー撤廃 |
| **4.8 Login Services** | Sign in with Apple 存続（Google 併用時の要件）|
| **5.1.1(v) Account Deletion** | Firebase Auth + Firestore + Storage + Apple refresh token revoke 全対応 |
| **2.3 Accurate Metadata** | UI 文言に審査特化表現なし（意図は ADR-007 に記録）|

### 実務バグ修正（Build 35 で追加対応）

- **機種変更時のデータ喪失問題**: `RecordingListViewModel.loadRecordings()` が SwiftData のみを参照していたため、再インストール後に Firestore の既存録音が表示されなかった
- **解決**: Firestore → SwiftData 初回同期を実装（PR #95）。tenant 切替検知もあわせて実装しテナント越境を防止
- **実機検証で確認**: y.honda@279279.net の tenant 279 admin で 8件の録音が正しく表示される状態に復旧

### デプロイ済みインフラ

- **Cloud Functions Dev/Prod**: `beforeSignIn` (Apple分岐) / `deleteAccount` (callable) ACTIVE
- **Firestore Dev/Prod**: `tenants/demo-guest` ドキュメント作成済み
- **Prod whitelist 変更**: `hy.unimail.11@gmail.com` を削除（本人の Apple 検証で demo-guest 経路を通すため）
- **Dev user customAttributes クリア**: `hy.unimail.11@gmail.com` の永続 claims を削除（Dev でのテスト用）

## 現在の状態

- **ブランチ**: main
- **ビルド**: Build 35（App Store Connect 審査待ち、2026-04-16 提出）
- **審査通過見込み**: **90%+**

## 直近のタイムライン

- 2026-04-02: Build 32 提出
- 2026-04-07: Build 32 リジェクト（2.1(a) Apple Sign-In エラー）
- 2026-04-15: Build 33/34 アップロード（シーン表示バグ発覚で未提出）
- 2026-04-16: Firestore 同期問題修正 → Build 35 アップロード → **App Review 再提出**

## オープンIssue

| # | タイトル | ラベル | 優先度 |
|---|---------|--------|-------|
| #71 | upload-testflight.sh に entitlements 検証ステップを追加 | P1, bug | 既存 |
| #65 | Apple ID アカウントリンク | enhancement | 将来対応 |
| #90 | Guest Tenant のスパム対策: TTL / レート制限 | enhancement | P2 |
| #91 | アカウント削除後のローカル SwiftData / Outbox クリーンアップ | bug | **P1**（セキュリティリスク） |
| #92 | Guest Tenant 利用者向けの「本番ログイン不可」案内UI | enhancement | P2 |
| #93 | deleteAccount Cloud Function の単体テスト追加 | enhancement | P2 |

## 次セッション推奨アクション

### 審査通過時（"配信準備完了" 通知）
1. TestFlight 内部配布 + 社内検証
2. **Issue #91 を最優先で対応**（Outbox 誤送信セキュリティリスク）
3. #90 / #92 / #93 順次対応
4. アカウント削除 UX 強化（影響明示 + テキスト確認入力）を Build 36+ で実装
5. #43 Google Docs エクスポート等、次機能へ

### リジェクト時
1. リジェクト理由を精読、ADR-007・Review Notes の設計意図と照合
2. Guideline 別 playbook:
   - 2.1(a) → 実機再現 + Cloud Functions ログ確認
   - 5.1.1(v) → 削除フロー詳細説明（revoke 実装済みを Review Notes に追加）
   - 4.8 → Sign in with Apple 配置位置確認
3. `/codex review` で外部視点セカンドオピニオン取得

## CI / 既知問題

- CI #96 失敗: GitHub Actions の iOS Simulator Runtime 接続失敗（exit 70、環境問題）、コード起因ではない

## 参考資料

- [PR #87 Guest Tenant 実装](https://github.com/system-279/carenote-ios/pull/87)
- [PR #95 Firestore 同期](https://github.com/system-279/carenote-ios/pull/95)
- [ADR-007 Guest Tenant 設計判断](../adr/ADR-007-guest-tenant-for-apple-signin.md)
- [Review Notes](../appstore-metadata.md)
