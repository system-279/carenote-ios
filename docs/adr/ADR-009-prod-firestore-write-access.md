# ADR-009: prod Firestore 直接書き込みの運用パターン

**Status**: Accepted（Stage 1 確定、Stage 2 follow-up、2026-04-23）
**Date**: 2026-04-23
**Supersedes**: なし
**Related**: Issue #111（Phase 0.9 allowedDomains 有効化）、`docs/runbook/phase-0-9-allowed-domains.md`

## Context

Phase 0.9 allowedDomains 有効化実施時、以下の制約が顕在化した。

- `gcloud firestore` には document 単体 patch サブコマンドが存在しない（runbook phase-0-9-allowed-domains.md L71 記載）
- Firebase Admin SDK 経由の Node.js 書き込みは ADC（user credential `system@279279.net`）では `PERMISSION_DENIED` となる
- Firestore Console 手動編集は再現性・監査性に欠け、緊急対応時の即応性も低い
- Service Account Key (JSON) のローカル配布は CLAUDE.md で禁止

prod Firestore 直接書き込み作業は継続的に発生する見積もり:

| カテゴリ | 例 | 頻度 |
|---------|-----|------|
| tenant 設定変更 | allowedDomains 追加/変更、機能フラグ | 四半期ごと |
| whitelist 管理 | 個別ユーザー招待・剥奪 | 月数回 |
| ロール管理 | admin 付与/剥奪 | 月数回 |
| 運用対応 | ユーザー問合せ由来のデータ修正 | 不定期 |
| データ調査 | migrationLogs / audit 確認 + 修正 | 不定期 |
| 緊急対応 | データ異常修復・緊急削除 | 低頻度だが即応必要 |
| rollback | 設定変更の取り消し | 不定期 |

## Decision

2 段構えで運用基盤を整備する。

### Stage 1（本 ADR で確定、2026-04-23 実施済）: ローカル CLI + SA impersonation

- **IAM binding**: `system@279279.net` に `firebase-adminsdk-fbsvc@carenote-prod-279.iam.gserviceaccount.com` の `roles/iam.serviceAccountTokenCreator` を付与（SA 単位・最小権限）
- **運用**: `gcloud auth print-access-token --impersonate-service-account=...` で一時 access token 発行 → Firestore REST API v1 で操作
- **適用場面**: 緊急対応、one-off 調査、ad-hoc 修正

### Stage 2（follow-up Issue）: GitHub Actions + Workload Identity Federation

- WIF pool + GitHub repo 紐付け
- 代表的な prod 操作を workflow 化（`allowed-domains-set`, `whitelist-add`, `rollback` 等）
- `workflow_dispatch` と PR-triggered 両対応
- **適用場面**: 定期運用、リスク高い変更、監査が必要な作業

## Rationale

### 選定しなかった代替案

| 代替 | 却下理由 |
|------|---------|
| A. Firestore Console 手動 | 再現性・監査性なし、CLI 化の目的に反する |
| B. `roles/datastore.user` をユーザーに直接付与 | 権限範囲が広すぎる（prod 全 Firestore 無条件操作可）。SA 単位 impersonation の方が最小権限 |
| C. SA key (JSON) ローカル配布 | CLAUDE.md で禁止、鍵漏洩リスク |
| D. 初回から GHA + WIF 一本 | 初期セットアップ 1-2h、緊急対応の即応性不足 |

### セキュリティ考慮

- IAM binding の範囲: SA 単位（プロジェクト全体への datastore 権限付与を回避）
- Audit log: impersonation 呼出しは `system@279279.net` が actor として記録される（responsibility trace 可能）
- Rollback: `gcloud iam service-accounts remove-iam-policy-binding` で即無効化可能

## Operational Guide

### prod Firestore 書き込み手順（Stage 1）

```bash
# 1. access token 取得
TOKEN=$(gcloud auth print-access-token \
  --impersonate-service-account=firebase-adminsdk-fbsvc@carenote-prod-279.iam.gserviceaccount.com)

# 2. Firestore REST API v1 で操作
curl -s -X PATCH \
  "https://firestore.googleapis.com/v1/projects/carenote-prod-279/databases/(default)/documents/<path>?updateMask.fieldPaths=<field>" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '<body>'
```

### 実例: Phase 0.9 allowedDomains 設定（2026-04-23 実施）

```bash
TOKEN=$(gcloud auth print-access-token \
  --impersonate-service-account=firebase-adminsdk-fbsvc@carenote-prod-279.iam.gserviceaccount.com)

curl -s -X PATCH \
  "https://firestore.googleapis.com/v1/projects/carenote-prod-279/databases/(default)/documents/tenants/279?updateMask.fieldPaths=allowedDomains" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"fields":{"allowedDomains":{"arrayValue":{"values":[{"stringValue":"279279.net"}]}}}}'
```

### IAM binding verification

```bash
gcloud iam service-accounts get-iam-policy \
  firebase-adminsdk-fbsvc@carenote-prod-279.iam.gserviceaccount.com \
  --project=carenote-prod-279
```

期待出力: `user:system@279279.net` が `roles/iam.serviceAccountTokenCreator` を持つ。

### IAM propagation 待ち

- binding 追加後の impersonation は 60〜90 秒の propagation 時間が必要
- 即時 `PERMISSION_DENIED` が出た場合は 1〜2 分待って再試行

## Consequences

### Positive

- prod Firestore 書き込みの CLI 化で再現性・監査性向上
- Console 操作依存の排除
- 緊急対応の即応性確保（Stage 1）
- Stage 2 整備で定期運用の自動化・監査強化（将来）

### Negative / Risk

- IAM binding 追加による攻撃面（`system@279279.net` の認証情報漏洩時に prod Firestore 全 write が可能）
- Stage 2 未整備期間は GHA ルート不在 → 定期作業も CLI で実施（audit 手動化）
- impersonation 権限が長期保持される（revoke 忘れリスク）

### Mitigation

- Stage 2（GHA + WIF）を follow-up Issue として起票、四半期以内に着手
- Stage 2 完了時点で Stage 1 の IAM binding 維持可否を再評価（残す場合は緊急対応用の fallback として位置づけ）
- `system@279279.net` の 2FA 有効化・定期見直し

## References

- Phase 0.9 RUNBOOK: `docs/runbook/phase-0-9-allowed-domains.md`
- Issue #111: Phase 0.9 prod allowedDomains 有効化
- 本 ADR 実施日の作業: 2026-04-23
- Firebase Admin SDK SA: `firebase-adminsdk-fbsvc@carenote-prod-279.iam.gserviceaccount.com`
