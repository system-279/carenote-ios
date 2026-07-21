# ADR-013: GitHub Actions + Workload Identity Federation による Firestore rules/操作デプロイ基盤

**Status**: Accepted（dev 実装済み、prod は follow-up）
**Date**: 2026-07-21
**Supersedes**: ADR-009 の Stage 2 設計素描（プール/SA/権限の詳細をここで確定する）
**Related**: ADR-002（WIF auth flow、アプリのエンドユーザー認証、本ADRとは別物）、ADR-009（prod Firestore 直接書き込み Stage 1）、ADR-011（Gemini 3.5 Flash 移行、`platformConfig` ルールの追加元）、ADR-012（Vertex AI config の Firestore 化）、Issue #178

## Context

`feature/vertex-ai-config-firestore` ブランチで追加した `platformConfig` コレクション用 Firestore rules を dev 環境にデプロイしようとしたところ、ローカルの firebase CLI ログインアカウントが誤っていてデプロイできなかった。これを機に、ADR-009 が Stage 2 として構想だけ残していた「GitHub Actions + WIF」を、Issue #178 の Acceptance Criteria をベースに具体的に設計・実装した。

## Decision

### 既存 WIF プールを流用せず、専用プールを新設する

このプロジェクトには既に `carenote-pool`（ADR-002、アプリのエンドユーザー認証用、Firebase Auth ID Token → STS → SA impersonation）が存在するが、**これを流用しない**。

理由: `carenote-pool` を使ってアプリ本体の SA `carenote-ios-client` をimpersonateする既存の IAM binding が、
```
principalSet://iam.googleapis.com/projects/444137368705/locations/global/workloadIdentityPools/carenote-pool/*
```
という **プール単位のワイルドカード**になっている。同じプールに GitHub Actions 用 provider を追加すると、この `/*` はプロバイダを問わずマッチするため、CI の実行がアプリ本体の SA（Vertex AI・Cloud Storage 権限を持つ）を意図せず impersonate できてしまう。これは CI 侵害がそのままアプリのランタイム権限に直結する権限昇格リスクであり、新 provider 側の attribute-condition をいくら厳しくしても、既存 binding 自体が「プール所属」だけで成立するため防げない。

→ **`github-actions-pool`（新規プール）+ `github-provider`（新規 provider）を作成した**（`carenote-dev-279`、global）。

### provider の attribute-condition は repository_id / repository_owner_id で固定

GitHub OIDC の issuer（`https://token.actions.githubusercontent.com`）は全 github.com リポジトリ共通のため、provider の attribute-condition で対象リポジトリを固定しないと、世界中のどの GitHub リポジトリからの OIDC トークンでも交換が成立してしまう。

repository 名（`system-279/carenote-ios`）は rename・削除後の再作成で再利用されうるため、数値で不変な `repository_id`（`1171154320`）と `repository_owner_id`（`254709477`）で固定した：

```
assertion.repository_owner_id=='254709477' && assertion.repository_id=='1171154320'
```

attribute mapping には監査・将来のスコープ拡張のため `repository` / `repository_id` / `repository_owner_id` / `ref` / `environment` / `job_workflow_ref` を含めた。

### 専用の最小権限 SA を新設（既存 SA の流用は不可）

`firebase-adminsdk-fbsvc`（Cloud Functions 既定の Admin SDK SA）の流用は不可とした。これは Firebase 管理下の広範な権限を持ち、(a) CI 侵害時の被害範囲が甚大、(b) 監査ログ上「Functions ランタイム」と「CI」の actor が同一プリンシパルに融合し追跡が壊れる、という二重の問題がある。ADR-009 自身も Rationale で「Stage 2 で Firestore 書込み専用 SA + 最小権限の採用を検討」と予告済みであった。

→ **`gha-firestore-ops@carenote-dev-279.iam.gserviceaccount.com`** を新規作成し、以下の**2ロールのみ**を付与した:

| ロール | 用途 |
|---|---|
| `roles/datastore.user` | Firestore ドキュメント書込み（allowedDomains / whitelist / platformConfig / rollback 等） |
| `roles/firebaserules.admin` | `firestore.rules` の ruleset 作成・release 更新（`firebase deploy --only firestore:rules` 相当） |

**`roles/firebaseauth.admin` は付与しない。** `functions/index.js` の `beforeSignIn` を確認すると、admin/member の custom claim は `tenants/{tenantId}/whitelist/{entryId}` の `role` フィールドから次回サインイン時に導出される設計になっている。つまり Issue #178 が挙げる `admin-role-grant`/`admin-role-revoke` 操作は、whitelist ドキュメントを `roles/datastore.user` で書き換えるだけで実現でき、Identity Toolkit の custom claim を直接上書きする `roles/firebaseauth.admin`（＝任意ユーザーへの admin claim 注入が技術的に可能になる、著しく強い権限）を CI に常設する必要がない。即時反映が必要な緊急ケースは、既存の `scripts/set-tenant-claim.sh`（ローカル・`system@279279.net` の serviceAccountTokenCreator 経路）に残す。

### impersonation binding は environment 属性で絞る

`gha-firestore-ops` への `roles/iam.workloadIdentityUser` binding は、pool 全体ではなく `attribute.environment/dev` を持つプリンシパルのみに限定した:

```
principalSet://iam.googleapis.com/projects/444137368705/locations/global/workloadIdentityPools/github-actions-pool/attribute.environment/dev
```

GitHub は Environment（後述）の protection rule を通過した job にしか対応する `environment` claim を発行しないため、**GitHub Environment の保護がそのまま GCP 側の信頼境界になる**。prod 展開時も同様に `attribute.environment/prod` で絞り、GitHub 側の `prod` Environment に required reviewer を設定することで二層防御にする。

### Data Access 監査ログを有効化

Firestore（`datastore.googleapis.com`）の `DATA_WRITE` Data Access 監査ログは GCP の既定で OFF になっている。Issue #178 の AC「操作内容を Cloud Logging に記録する」を満たすには明示的な有効化が必須なため、`carenote-dev-279` の IAM policy に `auditConfigs` を追加した（既存の27件の binding には一切手を加えていない）。

### rules デプロイと Firestore データ操作を workflow ファイルとして分離

インフラ（プール・provider・SA・impersonation binding・Environment）は Issue #178 の一部として共有するが、workflow ファイルは分離する:

- `.github/workflows/firestore-rules-deploy.yml`: `firestore.rules` のデプロイ専用
- `.github/workflows/firestore-op.yml`: allowedDomains / whitelist / admin-role / rollback 等の Firestore ドキュメント操作（Issue #178 本来のスコープ）

理由: rules デプロイは 1 回の誤操作で Firestore 全体のアクセス制御が変わりうる、影響度がデータ操作とは段違いの変更であるため。

## 検討したが見送った選択肢

- **既存 `carenote-pool` に GitHub provider を追加**: 前述のワイルドカード binding により却下
- **`firebase-adminsdk-fbsvc` の流用**: 権限過多・actor 追跡の観点から却下
- **CI SA に `roles/firebaseauth.admin` を付与**: whitelist 書込みで admin-role 操作が完結するため不要と判断
- **direct WIF（SA を介さず principalSet に直接ロール付与）**: `firebase-tools` との相性の不確実性から、SA impersonation 方式を採用

## 実装スコープ（本 ADR 時点）

**dev 環境（`carenote-dev-279`）のみ実装済み。** prod（`carenote-prod-279`）への展開は、prod IAM 権限付与という重みのある操作を含むため、dev での動作確認後に別途明示確認を得てから着手する。

## Consequences

### Positive
- Firestore rules デプロイ・データ操作がローカル CLI ログイン状態に依存しなくなる
- 専用最小権限 SA・environment 属性による二層防御で、既存のアプリ用 WIF・Cloud Functions SA とは完全に分離された攻撃面になる
- Data Access 監査ログにより、CI 経由の全書込みが actor 追跡可能になる

### Negative / Risk
- WIF プール・SA・IAM policy の管理対象が増える（IaC 化されていないため `gcloud` コマンドの実行記録が正になる）
- prod 展開までは、prod の定期運用は引き続き ADR-009 Stage 1（ローカル impersonation）に依存する

## 実装後に判明した修正（2026-07-21）

dev環境での初回dispatch検証で、`google-github-actions/auth`はデフォルトでは`outputs.access_token`を生成しないことが判明した（`token_format: 'access_token'`をwithブロックに明示しない限り空文字列になる）。`firestore-rules-deploy.yml`のverifyステップと`firestore-op.yml`の全操作ステップは`steps.auth.outputs.access_token`を前提にしていたため、このパラメータ欠落により実際には空のBearerトークンでcurlしていた（`firestore.rules`本体のデプロイはgcloud/firebase CLI側がcredential fileを直接参照するため無関係に成功していた）。両workflowファイルの認証ステップに`token_format: 'access_token'`を追加して修正した。

## References
- Issue #178: Stage 2 follow-up（本 ADR の実装対象）
- `docs/adr/ADR-002-wif-auth-flow.md`: アプリ用 WIF（本ADRとは別プール）
- `docs/adr/ADR-009-prod-firestore-write-access.md`: Stage 1（ローカル impersonation、緊急 fallback として維持）
- `functions/index.js` の `beforeSignIn`: admin/member role が whitelist ドキュメントから導出される実装（`firebaseauth.admin` 不要の根拠）
