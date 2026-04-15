# Handoff — App Store Review Build 32 再リジェクト対応 / Build 33 準備 (2026-04-15)

## セッション成果

### Build 32 リジェクト → Guest Tenant 戦略へ転換

Build 32 が再度 Guideline 2.1(a) で却下（2026-04-07、iPad Air M3 + iPadOS 26.4）。Sign in with Apple で「このアカウントは登録されていません」の赤字メッセージが「エラー」と判定された。

| 対応項目 | 状態 |
|---------|------|
| Apple Sign-In 未登録 → demo-guest テナント自動プロビジョニング | ✅ Cloud Functions 実装・Dev/Prod デプロイ完了 |
| ログイン画面の赤字エラー撤廃（`.secondary` グレー化） | ✅ |
| アカウント削除機能（Guideline 5.1.1(v)） | ✅ Settings画面導線 + Cloud Function `deleteAccount`（recordings + Storage 音声削除）|
| ADR-007（Guest Tenant 設計） | ✅ |
| Review Notes 全面改訂 | ✅ Sign in with Apple 自動プロビジョニング経路を明示 |
| ビルド番号 33 へ更新 | ✅ |
| Quality Gate（simplify + safe-refactor + Evaluator） | ✅ 全PASS、HIGH指摘は対応済 or ADR既知制約化 |

### 設計の核心（ADR-007）

未登録 Apple ID は `tenants/demo-guest` へ自動割り当てし、独立空間で全機能を試用できる。
Google/Email は招待制を維持。実ユーザーフローへの影響ゼロ。
UI 文言には「審査用」と書かない（Guideline 2.3 リスク回避）。意図は ADR-007 にのみ記録。

### 既知の制約（ADR-007 §制約・懸念）

| # | 内容 | Issue化 |
|---|------|---------|
| 1 | demo-guest テナントの TTL/レート制限なし | 要 |
| 2 | Apple Refresh Token revoke 未実装 | 要 |
| 3 | 削除後のローカル SwiftData キャッシュ未クリア | 要 |
| 4 | Guest 利用者向けの「本番ログイン不可」UI なし | 要 |

## 現在の状態

- **ブランチ**: main（PR作成予定）
- **ビルド**: Build 33（TestFlight アップロード未実施）
- **Cloud Functions**: Dev/Prod ともに `beforeSignIn` v3, `deleteAccount` v1 ACTIVE
- **Firestore**: `tenants/demo-guest` Dev/Prod 両方に作成済み

## オープンIssue

| # | タイトル | ラベル | 状態 |
|---|---------|--------|------|
| #71 | upload-testflight.sh に entitlements 検証ステップを追加 | P1, bug | オープン |
| #65 | Apple ID アカウントリンク | enhancement | 将来対応 |

## 次セッション推奨アクション

1. **TestFlight アップロード**: `./scripts/upload-testflight.sh`
2. **App Store Connect で Build 33 を審査提出**
3. **Build 33 リジェクト時の備え**: ADR-007 既知制約 #2 (Apple revoke) を先回りして実装するか判断
4. **既知制約4件のIssue化**（Build 33 結果見てから）
5. #71 entitlements 検証ステップを upload-testflight.sh に追加
