# RUNBOOK: Phase 1 `transferOwnership` dev smoke test

**ステータス**: ユーザー実行待ち
**対象**: PR #119 で dev deploy 済の `transferOwnership` Callable Function を dev 環境で動作確認する
**関連**: ADR-008、Issue #110、PR #119、Issue #120（CLI 堅牢化 follow-up）

---

## 目的

prod deploy 前の gate として dev 環境で以下を確認する:

1. `dryRun=true` が collection ごとの件数を正しく返すこと
2. `dryRunId` で `confirm` が正しく実行され、`createdBy` / `addedBy` が `toUid` に書き換わること
3. `migrationLogs` / `migrationState` が想定通り記録されること
4. 権限エラー（非 admin / 他 tenant）で正しく拒否されること

---

## 選択肢: 2 通りの smoke test 方式

### A. `firebase functions:shell` 方式（推奨・最小コスト）

Authorization ヘッダ検証をバイパスし、`request.auth` を手動構築して Callable を呼び出せる。admin id token 発行の運用整備が不要。

### B. CLI (`call-transfer-ownership.mjs`) + 実 admin id token 方式（prod と同等）

本番相当の経路で検証する。admin id token の取得手順を整備する必要がある（Issue #120 の follow-up で RUNBOOK 予定）。

**初回 smoke test は A を推奨。B は Phase 1 prod deploy 前に少なくとも 1 回実施して本番相当経路の健全性を確認する。**

---

## 方式 A: `functions:shell` 手順

### 前提

- `gcloud auth login` 済（`system@279279.net`）
- `firebase` CLI v13+ が PATH に入っている
- dev emulator ポート (8080, 9099, 9199) が空いている or `--project carenote-dev-279` でクラウド関数を呼ぶ

### 1. seed データを dev に投入

```bash
# tenant-a に fromUid が所有する recording / template / whitelist を作成
# （dev の Firestore Console で手動作成でも可）

cat <<'EOF' > /tmp/seed-transfer-dev.mjs
import admin from "firebase-admin";
admin.initializeApp({ projectId: "carenote-dev-279" });
const db = admin.firestore();

const T = "smoke-tenant";
const FROM = "smoke-from-uid";
const TO = "smoke-to-uid";

// TO must exist in Auth with tenantId claim to pass validateToUidBelongsToTenant
await admin.auth().createUser({ uid: TO }).catch(() => {});
await admin.auth().setCustomUserClaims(TO, { tenantId: T, role: "member" });
await admin.auth().createUser({ uid: "smoke-admin" }).catch(() => {});
await admin.auth().setCustomUserClaims("smoke-admin", { tenantId: T, role: "admin" });

await db.doc(`tenants/${T}/recordings/rec-1`).set({ createdBy: FROM, title: "t1" });
await db.doc(`tenants/${T}/recordings/rec-2`).set({ createdBy: FROM, title: "t2" });
await db.doc(`tenants/${T}/templates/tmpl-1`).set({ createdBy: FROM });
await db.doc(`tenants/${T}/whitelist/wl-1`).set({ addedBy: FROM, email: "x@y" });

console.log("seed ok");
process.exit(0);
EOF

GOOGLE_APPLICATION_CREDENTIALS=/path/to/dev-admin-key.json \
node --experimental-vm-modules /tmp/seed-transfer-dev.mjs
```

※ dev service account key は `gcloud auth application-default login` で発行 or `functions:shell` 実行時の ADC を利用。

### 2. `functions:shell` で Callable 呼出

```bash
cd functions
firebase functions:shell --project carenote-dev-279
```

shell プロンプトで以下を順に実行:

```javascript
// dryRun
> transferOwnership({ dryRun: true, fromUid: "smoke-from-uid", toUid: "smoke-to-uid" }, { auth: { uid: "smoke-admin", token: { tenantId: "smoke-tenant", role: "admin" } } })
// → { dryRunId: "...uuid...", counts: { recordings: 2, templates: 1, whitelist: 1 } }

// confirm（上の dryRunId を使用）
> transferOwnership({ dryRunId: "<上の uuid>" }, { auth: { uid: "smoke-admin", token: { tenantId: "smoke-tenant", role: "admin" } } })
// → { ok: true, updated: { recordings: 2, templates: 1, whitelist: 1 } }
```

### 3. Firestore で副作用を確認

```bash
# 書き換わったドキュメントを確認
firebase firestore:get "tenants/smoke-tenant/recordings/rec-1" \
  --project carenote-dev-279
# → createdBy が "smoke-to-uid" に更新されていること

# migrationLogs に完了記録が残ること
firebase firestore:get "tenants/smoke-tenant/migrationLogs" \
  --project carenote-dev-279
# → completed ログ 1 件（fromUid, toUid, counts, timestamps）

# migrationState が idle に戻っていること
firebase firestore:get "tenants/smoke-tenant/migrationState/<fromUid>" \
  --project carenote-dev-279
# → state: "idle" or ドキュメント削除 (ADR-008 の仕様に従う)
```

### 4. 異常系（拒否ケース）を 1 つ確認

```javascript
// 非 admin で呼ぶと permission-denied
> transferOwnership({ dryRun: true, fromUid: "a", toUid: "b" }, { auth: { uid: "smoke-admin", token: { tenantId: "smoke-tenant", role: "member" } } })
// → HttpsError: permission-denied, "管理者のみ実行可能です"
```

### 5. seed cleanup

```bash
cat <<'EOF' > /tmp/cleanup-transfer-dev.mjs
import admin from "firebase-admin";
admin.initializeApp({ projectId: "carenote-dev-279" });
const db = admin.firestore();

const T = "smoke-tenant";
const recur = async (ref) => {
  const snap = await ref.get();
  await Promise.all(snap.docs.map(async d => {
    await recur(d.ref.collection("migrationLogs")).catch(() => {});
    await d.ref.delete();
  }));
};
await recur(db.collection(`tenants/${T}/recordings`));
await recur(db.collection(`tenants/${T}/templates`));
await recur(db.collection(`tenants/${T}/whitelist`));
await recur(db.collection(`tenants/${T}/migrationLogs`));
await recur(db.collection(`tenants/${T}/migrationState`));

for (const uid of ["smoke-from-uid", "smoke-to-uid", "smoke-admin"]) {
  await admin.auth().deleteUser(uid).catch(() => {});
}

console.log("cleanup ok");
process.exit(0);
EOF

node --experimental-vm-modules /tmp/cleanup-transfer-dev.mjs
```

---

## 方式 B: CLI + admin id token

### id token 取得手順（本 RUNBOOK 初版の範囲）

**NOTE (2026-04-21)**: Firebase Auth の admin user id token を確実に取得する RUNBOOK は Issue #120 の follow-up で整備予定。現時点では以下の手動手順でテスト可能:

1. iOS 実機 / シミュレータに admin アカウントでサインイン
2. デバッグ用に AuthViewModel 内で `Auth.auth().currentUser?.getIDToken { ... }` をログ出力（後で revert）
3. 出力された JWT を `--id-token` に渡す

```bash
node functions/scripts/call-transfer-ownership.mjs \
  --project carenote-dev-279 \
  --from-uid <fromUid> \
  --to-uid <toUid> \
  --dry-run \
  --id-token '<JWT from step 2>'
# → { dryRunId, counts } が出力される

node functions/scripts/call-transfer-ownership.mjs \
  --project carenote-dev-279 \
  --dry-run-id <uuid> \
  --confirm \
  --id-token '<JWT from step 2>'
```

**Prod 適用時は CONFIRM_PROD=yes を追加**（CLI が二重ロックをかける）:

```bash
CONFIRM_PROD=yes node functions/scripts/call-transfer-ownership.mjs \
  --project carenote-prod-279 --dry-run-id <uuid> --confirm \
  --id-token '<prod admin JWT>'
```

---

## 検証結果記録

<!-- 実施後に埋める -->

### 方式 A

- 実施日時: TBD
- 実施者: TBD
- dryRun counts が期待通り: ☐ PASS ☐ FAIL
- confirm で recordings / templates / whitelist 全て更新: ☐ PASS ☐ FAIL
- migrationLogs completed 記録: ☐ PASS ☐ FAIL
- 非 admin permission-denied: ☐ PASS ☐ FAIL

### 方式 B（prod deploy 前に 1 回）

- 実施日時: TBD
- 実施者: TBD
- dryRun: ☐ PASS ☐ FAIL
- confirm: ☐ PASS ☐ FAIL

---

## Rollback

`transferOwnership` Function 自体は副作用を伴うため、実行後の rollback はドキュメント単位の手動復旧が必要:

- `migrationLogs/<logId>.counts` を元に影響範囲を特定
- 各 recording / template / whitelist の `createdBy` / `addedBy` を元の `fromUid` に戻す

Function 削除（`firebase functions:delete transferOwnership`）は追加実行を止めるだけで過去の副作用は戻らない。

---

## 関連

- [ADR-008 アカウント所有権移行方式](../adr/ADR-008-account-ownership-transfer.md)
- PR #119 (Phase 1 実装)
- Issue #120 (CLI 堅牢化 follow-up; id token RUNBOOK 整備含む)
- Issue #110 (Phase 1 元チケット)
