# ADR-001: Google Sign-In 採用

## ステータス
Accepted (2026-03-03)

## コンテキスト
仕様書 v4.0 では Apple Sign-In を採用していたが、ユーザーの要望により認証プロバイダーを変更する必要があった。

## 決定
**Google Sign-In のみ** を認証プロバイダーとして採用する。

## 理由
- ユーザーの直接的な要望
- WIFAuthService は Firebase ID Token ベースのため、認証プロバイダー変更の影響が限定的
- GoogleSignIn-iOS SDK (v9.0.0+) は SwiftUI ネイティブの `GoogleSignInButton` を提供
- Apple Sign-In entitlement が不要になり、開発者アカウント設定が簡素化

## 影響
- `project.yml`: GoogleSignIn-iOS パッケージ追加、Apple Sign-In entitlement 削除
- `AuthViewModel`: `signInWithGoogle()` 実装
- `SignInView`: `GoogleSignInButton` 使用
- WIFAuthService, 全サービス層: 変更不要
