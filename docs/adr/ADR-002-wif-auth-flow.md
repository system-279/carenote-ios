# ADR-002: Workload Identity Federation (WIF) 認証フロー

## ステータス
Accepted (2026-03-03)

## コンテキスト
iOS アプリから GCP サービス (Vertex AI, Cloud Storage) にアクセスするための認証方式を決定する必要があった。

## 決定
**Workload Identity Federation (WIF)** を採用し、サービスアカウントキー (JSON) をアプリに同梱しない。

## 認証フロー
1. Firebase Auth で Google Sign-In → Firebase ID Token 取得
2. STS Token Exchange: Firebase ID Token → Federated Token
3. SA Impersonation: Federated Token → GCP Access Token
4. GCP Access Token で Vertex AI / Cloud Storage にアクセス

## 理由
- SA キーのアプリ同梱はセキュリティリスク (リバースエンジニアリング)
- WIF は Google 推奨の認証パターン
- Firebase ID Token ベースのため認証プロバイダーに非依存

## 影響
- `WIFAuthService`: STS + SA Impersonation の実装
- `AppConfig`: GCP プロジェクト番号・SA メール設定
