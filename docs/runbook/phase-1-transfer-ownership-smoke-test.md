# RUNBOOK: Phase 1 `transferOwnership` dev smoke test

**ステータス**: ユーザー実行待ち
**対象**: PR #119 で dev deploy 済の `transferOwnership` Callable Function (v2) を dev 環境で動作確認する
**関連**: ADR-008 §Phase 1、Issue #110、PR #119、Issue #120（CLI 堅牢化 follow-up）

## 完了条件チェックリスト

本 RUNBOOK は以下が全て埋まった時点で完了とする。未達のまま Issue #110 クローズ時の判断材料にしない。

- [ ] 方式 A (`functions:shell`) 実施結果を全項目埋める
- [ ] 方式 B (実 id token) は Phase 1 prod deploy 前に少なくとも 1 回実施
- [ ] cleanup スクリプト実行済（smoke テナント残骸なし）

---

## 目的

prod deploy 前の gate として dev 環境で以下を確認する（仕様詳細は ADR-008 §Phase 1 を参照）:

1. `dryRun=true` が collection ごとの件数を正しく返す
2. `dryRunId` で `confirm` 実行時に `createdBy` / `addedBy` が `toUid` に書き換わる
3. `migrationLogs` / `migrationState` が想定通り記録される
4. 権限エラー（非 admin / 他 tenant）で正しく拒否される

---

## 選択肢: 2 通りの smoke test 方式

### A. `firebase functions:shell` 方式（推奨・最小コスト）

Authorization ヘッダ検証をバイパスし、`request.auth` を手動構築して Callable を呼び出せる。admin id token 発行の運用整備が不要。

### B. CLI (`call-transfer-ownership.mjs`) + 実 admin id token 方式（prod と同等）

本番相当の経路で検証する。admin id token の取得 RUNBOOK は Issue #120 の follow-up で整備予定。整備前は方式 A のみ実施で良い。

**初回 smoke test は A を推奨。B は Issue #120 完了後に Phase 1 prod deploy 前に 1 回実施する。**

---

## 方式 A: `functions:shell` 手順

### 前提

- `gcloud auth application-default login` 済（`system@279279.net`）
- `firebase` CLI v15+ が PATH に入っている
- dev の `transferOwnership` Function が ACTIVE（PR #119 で deploy 済）

### 1. seed データを dev に投入

```bash
cat > /tmp/seed-transfer-dev.mjs <<'EOF'
import admin from "firebase-admin";
admin.initializeApp({ projectId: "carenote-dev-279" });
const db = admin.firestore();
const auth = admin.auth();

const T = "smoke-tenant";
const FROM = "smoke-from-uid";
const TO = "smoke-to-uid";

// toUid must exist in Auth with the same tenantId claim so that
// validateToUidBelongsToTenant passes. The admin is used as the caller.
for (const uid of [TO, "smoke-admin"]) {
  try { await auth.deleteUser(uid); } catch {}
}
await auth.createUser({ uid: TO });
await auth.setCustomUserClaims(TO, { tenantId: T, role: "member" });
await auth.createUser({ uid: "smoke-admin" });
await auth.setCustomUserClaims("smoke-admin", { tenantId: T, role: "admin" });

await db.doc(`tenants/${T}/recordings/rec-1`).set({ createdBy: FROM, title: "t1" });
await db.doc(`tenants/${T}/recordings/rec-2`).set({ createdBy: FROM, title: "t2" });
await db.doc(`tenants/${T}/templates/tmpl-1`).set({ createdBy: FROM });
await db.doc(`tenants/${T}/whitelist/wl-1`).set({ addedBy: FROM, email: "x@y" });

console.log("seed ok");
process.exit(0);
EOF

node /tmp/seed-transfer-dev.mjs
```

`gcloud auth application-default login` の credentials が ADC として読まれる。SA key JSON は不要。

### 2. `functions:shell` で Callable 呼出

```bash
cd functions
firebase functions:shell --project carenote-dev-279
```

`transferOwnership` は firebase-functions v2 の `onCall` なので、shell では**単一の `request` オブジェクト**を引数として渡す（`{ data, auth }` のフラット構造）。

```javascript
// dryRun
> transferOwnership({ data: { dryRun: true, fromUid: "smoke-from-uid", toUid: "smoke-to-uid" }, auth: { uid: "smoke-admin", token: { tenantId: "smoke-tenant", role: "admin" } } })
// → { dryRunId: "...uuid...", counts: { recordings: 2, templates: 1, whitelist: 1 } }

// confirm（上の dryRunId を使用）
> transferOwnership({ data: { dryRunId: "<上の uuid>" }, auth: { uid: "smoke-admin", token: { tenantId: "smoke-tenant", role: "admin" } } })
// → { ok: true, updated: { recordings: 2, templates: 1, whitelist: 1 } }
```

### 3. Firestore で副作用を確認

Firebase Console (dev) で `tenants/smoke-tenant/` 配下を確認:

- `recordings/rec-1.createdBy` → `"smoke-to-uid"` に更新
- `recordings/rec-2.createdBy` → `"smoke-to-uid"` に更新
- `templates/tmpl-1.createdBy` → `"smoke-to-uid"` に更新
- `whitelist/wl-1.addedBy` → `"smoke-to-uid"` に更新

`migrationLogs` ドキュメントを確認:
- `status: "completed"`
- `recordingsUpdated: 2`
- `templatesUpdated: 1`
- `whitelistUpdated: 1`
- `startedAt`, `completedAt` が timestamp で記録

`migrationState/<dryRunId>` ドキュメントを確認:
- `status: "completed"` (terminal、doc は削除されない)
- `completedAt` が timestamp

スクリプト経由で確認したい場合:
```bash
cat > /tmp/verify-transfer-dev.mjs <<'EOF'
import admin from "firebase-admin";
admin.initializeApp({ projectId: "carenote-dev-279" });
const db = admin.firestore();
const T = "smoke-tenant";

const rec1 = await db.doc(`tenants/${T}/recordings/rec-1`).get();
console.log("rec-1.createdBy:", rec1.data()?.createdBy);

const logs = await db.collection(`tenants/${T}/migrationLogs`).get();
logs.forEach(d => console.log("migrationLog:", d.id, d.data()));

const states = await db.collection(`tenants/${T}/migrationState`).get();
states.forEach(d => console.log("migrationState:", d.id, d.data()));

process.exit(0);
EOF
node /tmp/verify-transfer-dev.mjs
```

### 4. 異常系（拒否ケース）を 1 つ確認

```javascript
// 非 admin で呼ぶと permission-denied
> transferOwnership({ data: { dryRun: true, fromUid: "a", toUid: "b" }, auth: { uid: "smoke-admin", token: { tenantId: "smoke-tenant", role: "member" } } })
// → HttpsError: permission-denied, "管理者のみ実行可能です"
```

### 5. seed cleanup

```bash
cat > /tmp/cleanup-transfer-dev.mjs <<'EOF'
import admin from "firebase-admin";
admin.initializeApp({ projectId: "carenote-dev-279" });
const db = admin.firestore();
const auth = admin.auth();

const T = "smoke-tenant";
const deleteCollection = async (path) => {
  const snap = await db.collection(path).get();
  for (const d of snap.docs) await d.ref.delete();
};
for (const sub of ["recordings", "templates", "whitelist", "migrationLogs", "migrationState"]) {
  await deleteCollection(`tenants/${T}/${sub}`);
}
await db.doc(`tenants/${T}`).delete().catch(() => {});

for (const uid of ["smoke-from-uid", "smoke-to-uid", "smoke-admin"]) {
  await auth.deleteUser(uid).catch(() => {});
}

console.log("cleanup ok");
process.exit(0);
EOF

node /tmp/cleanup-transfer-dev.mjs
```

---

## 方式 B: CLI + admin id token

### 前提

admin id token 取得の RUNBOOK は Issue #120 で整備予定。整備前は本方式をスキップして方式 A のみで検証する。整備後、Issue #120 の追加 RUNBOOK（`phase-1-admin-id-token.md` 等）を参照して実施。

### 基本フロー（Issue #120 完了後）

```bash
node functions/scripts/call-transfer-ownership.mjs \
  --project carenote-dev-279 \
  --from-uid <fromUid> \
  --to-uid <toUid> \
  --dry-run \
  --id-token '<admin user ID token>'
# → { dryRunId, counts } が出力される

node functions/scripts/call-transfer-ownership.mjs \
  --project carenote-dev-279 \
  --dry-run-id <uuid> \
  --confirm \
  --id-token '<admin user ID token>'
```

prod 適用時は `CONFIRM_PROD=yes` を追加（CLI が `call-transfer-ownership.mjs` の validate 関数で二重ロックをかける）:

```bash
CONFIRM_PROD=yes node functions/scripts/call-transfer-ownership.mjs \
  --project carenote-prod-279 --dry-run-id <uuid> --confirm \
  --id-token '<prod admin user ID token>'
```

---

## 検証結果記録

<!-- 実施後に埋める -->

### 方式 A

- 実施日時: TBD
- 実施者: TBD
- dryRun counts が期待通り: ☐ PASS ☐ FAIL
- confirm で recordings / templates / whitelist 全て更新: ☐ PASS ☐ FAIL
- `migrationLogs.status = "completed"` + `*Updated` 各件数記録: ☐ PASS ☐ FAIL
- `migrationState.status = "completed"`: ☐ PASS ☐ FAIL
- 非 admin permission-denied: ☐ PASS ☐ FAIL
- cleanup 実施済: ☐

### 方式 B（Issue #120 完了後、prod deploy 前に 1 回）

- 実施日時: TBD
- 実施者: TBD
- dryRun: ☐ PASS ☐ FAIL
- confirm: ☐ PASS ☐ FAIL

---

## Rollback

`transferOwnership` 実行後の rollback はドキュメント単位の手動復旧が必要（Function 自体に undo 機能はない）:

- `migrationLogs/<dryRunId>` から `fromUid` / `toUid` / `recordingsUpdated` / `templatesUpdated` / `whitelistUpdated` を確認し、影響範囲を特定
- 各 collection で `createdBy == toUid` (templates/recordings) / `addedBy == toUid` (whitelist) のドキュメントを再度 `fromUid` に書き戻す

Function 削除（`firebase functions:delete transferOwnership --project <proj>`）は追加実行を止めるだけで過去の副作用は戻らない。

---

## 関連

- [ADR-008 アカウント所有権移行方式](../adr/ADR-008-account-ownership-transfer.md)
- PR #119 (Phase 1 実装)
- Issue #120 (CLI 堅牢化 follow-up; admin id token 取得 RUNBOOK 整備を含む)
- Issue #110 (Phase 1 元チケット)
