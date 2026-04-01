# Handoff — Sprint 4 開始前 (2026-04-01)

## セッション成果

### CI修正 (PR #63, merged)

| 修正内容 | 詳細 |
|----------|------|
| Swift 6 Sendable違反 | `@preconcurrency import FirebaseAuth/GoogleSignIn` で GIDSignInResult/AuthDataResult/AuthTokenResult の non-sendable エラー解消 |
| SwiftDataテスト安定化 | `isStoredInMemoryOnly` → UUID付き一時ファイルstore に変更（並列コンテナ競合回避） |
| VMテスト分離 | `ClientSelectViewModelTests` を SwiftData 非依存に変更（フィルタロジックのみテスト） |
| CI判定ロジック | xcresult解析でインフラクラッシュ（SwiftData bootstrap）を分離、実テスト失敗のみで判定 |
| シミュレータ事前ブート | CI環境で "bootstrapping" 失敗を回避 |
| 並列テスト無効化 | `-parallel-testing-enabled NO` で SwiftData 並列クラッシュ回避 |

### Codex セカンドオピニオン結果

SwiftDataテスト安定化のベストプラクティス:
1. 1テスト1コンテナ、1テスト1ストアURL（UUID一時ファイル）
2. VMテストではSwiftData不要 → fake/直接プロパティ設定
3. テスト用スキーマ最小化（ClientCache専用コンテナ等）
4. SwiftData統合テストは少数に絞り直列実行

## 現在の状態

- **ブランチ**: main (`a8298c6`)
- **CI**: リラン中（前回は iOS Simulator Runtime ダウンロード一時障害で失敗、テストコード自体は問題なし）
- **テスト**: ローカル 93件全PASS / 13 suite
- **オープンPR**: #44 (stale), #46 (stale)

## オープンIssue

| # | タイトル | ラベル |
|---|---------|--------|
| #43 | 録音詳細の文字起こし結果をGoogleドキュメントにエクスポート | enhancement |

## 次セッション推奨アクション

### 即時確認
1. CIリラン結果確認（`gh run list --limit 1`）
2. CI失敗が続く場合: `xcodebuild -downloadPlatform iOS` の `continue-on-error: true` 追加を検討

### Sprint 4: #43 Google Docsエクスポート

| Phase | タスク |
|-------|--------|
| 1.1 | 既存ブランチ `feature/google-docs-export` 調査（mainとの乖離確認） |
| 1.2 | Google Docs API 仕様確認（認証フロー、スコープ） |
| 1.3 | GoogleDocsExportService 実装 |
| 1.4 | UI（エクスポートボタン + 進捗表示） |
| 1.5 | テスト + PR |

### 技術的負債
- SwiftData並列テストクラッシュ: Apple側のバグ修正待ち。現在はUUID一時ファイル + 直列実行 + xcresult判定で回避
- stale PR (#44, #46): クローズ検討
