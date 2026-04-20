"use strict";

const assert = require("assert");
const admin = require("firebase-admin");

// IMPORTANT: capture real firebase-admin/firestore bindings at module load time,
// BEFORE auth-blocking.test.js's before() hook monkey-patches getFirestore to an
// offline mock. Mocha runs all test-file module code first (captures at this
// point), then root before() hooks in registration order.
const { getFirestore: realGetFirestore } = require("firebase-admin/firestore");

// Load SUT at module time so its `getFirestore` destructure is bound to the
// real (unpatched) export, not the later offline mock.
const { transferOwnership, _internals } = require("../src/transferOwnership");

const functionsTest = require("firebase-functions-test");
const test = functionsTest();
const callTransfer = test.wrap(transferOwnership);

const TENANT_ID = "tenant-a";
const TENANT_ID_B = "tenant-b";
const ADMIN_UID = "admin-a";
const FROM_UID = "uid-old";
const TO_UID = "uid-new";
const OTHER_UID = "uid-unrelated";

let db;

before(() => {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
  db = realGetFirestore();
});

function adminAuth(tenantId = TENANT_ID, uid = ADMIN_UID) {
  return { uid, token: { tenantId, role: "admin" } };
}

function memberAuth(tenantId = TENANT_ID, uid = "member-a") {
  return { uid, token: { tenantId, role: "member" } };
}

async function clearTenant(tenantId) {
  const collections = ["recordings", "templates", "whitelist", "migrationState", "migrationLogs"];
  for (const name of collections) {
    const snap = await db.collection("tenants").doc(tenantId).collection(name).get();
    const batch = db.batch();
    for (const doc of snap.docs) {
      batch.delete(doc.ref);
    }
    if (!snap.empty) await batch.commit();
  }
}

async function seedRecording(tenantId, id, data) {
  await db.collection("tenants").doc(tenantId).collection("recordings").doc(id).set(data);
}

async function seedTemplate(tenantId, id, data) {
  await db.collection("tenants").doc(tenantId).collection("templates").doc(id).set(data);
}

async function seedWhitelist(tenantId, id, data) {
  await db.collection("tenants").doc(tenantId).collection("whitelist").doc(id).set(data);
}

async function getRecording(tenantId, id) {
  const snap = await db.collection("tenants").doc(tenantId).collection("recordings").doc(id).get();
  return snap.data();
}

async function getMigrationLogs(tenantId) {
  const snap = await db.collection("tenants").doc(tenantId).collection("migrationLogs").get();
  return snap.docs.map((d) => d.data());
}

async function getMigrationState(tenantId, id) {
  const snap = await db.collection("tenants").doc(tenantId).collection("migrationState").doc(id).get();
  return snap.exists ? snap.data() : null;
}

beforeEach(async () => {
  await clearTenant(TENANT_ID);
  await clearTenant(TENANT_ID_B);
});

after(() => {
  test.cleanup();
});

// ===== Authorization / argument validation =====

describe("transferOwnership: 認可 / 引数検証", () => {
  it("AC-6: 未ログインなら unauthenticated", async () => {
    await assert.rejects(
      () => callTransfer({ data: { dryRun: true, fromUid: "a", toUid: "b" }, auth: undefined }),
      (err) => err.code === "unauthenticated"
    );
  });

  it("AC-6: role != admin なら permission-denied", async () => {
    await assert.rejects(
      () => callTransfer({ data: { dryRun: true, fromUid: "a", toUid: "b" }, auth: memberAuth() }),
      (err) => err.code === "permission-denied"
    );
  });

  it("tenantId claim 欠落なら failed-precondition", async () => {
    await assert.rejects(
      () => callTransfer({
        data: { dryRun: true, fromUid: "a", toUid: "b" },
        auth: { uid: "admin-a", token: { role: "admin" } },
      }),
      (err) => err.code === "failed-precondition"
    );
  });

  it("AC-7: fromUid === toUid なら invalid-argument", async () => {
    await assert.rejects(
      () => callTransfer({ data: { dryRun: true, fromUid: "same", toUid: "same" }, auth: adminAuth() }),
      (err) => err.code === "invalid-argument"
    );
  });

  it("dryRun でも dryRunId でもない呼出 → invalid-argument", async () => {
    await assert.rejects(
      () => callTransfer({ data: { fromUid: "a", toUid: "b" }, auth: adminAuth() }),
      (err) => err.code === "invalid-argument"
    );
  });

  it("fromUid 欠落 → invalid-argument", async () => {
    await assert.rejects(
      () => callTransfer({ data: { dryRun: true, toUid: "b" }, auth: adminAuth() }),
      (err) => err.code === "invalid-argument"
    );
  });
});

// ===== dryRun =====

describe("transferOwnership: dryRun (AC-1)", () => {
  it("AC-1: 3 collection の件数を返し、migrationState に prepared で記録する", async () => {
    await seedRecording(TENANT_ID, "r1", { createdBy: FROM_UID, clientName: "A" });
    await seedRecording(TENANT_ID, "r2", { createdBy: FROM_UID, clientName: "B" });
    await seedRecording(TENANT_ID, "r3", { createdBy: OTHER_UID, clientName: "C" });
    await seedTemplate(TENANT_ID, "t1", { createdBy: FROM_UID, createdByName: "旧姓田中" });
    await seedWhitelist(TENANT_ID, "w1", { email: "a@x", addedBy: FROM_UID });

    const result = await callTransfer({
      data: { dryRun: true, fromUid: FROM_UID, toUid: TO_UID },
      auth: adminAuth(),
    });

    assert.equal(result.counts.recordings, 2);
    assert.equal(result.counts.templates, 1);
    assert.equal(result.counts.whitelist, 1);
    assert.ok(result.dryRunId, "dryRunId returned");

    const state = await getMigrationState(TENANT_ID, result.dryRunId);
    assert.equal(state.status, "prepared");
    assert.equal(state.fromUid, FROM_UID);
    assert.equal(state.toUid, TO_UID);
    assert.deepEqual(state.counts, { recordings: 2, templates: 1, whitelist: 1 });
  });

  it("対象 0 件でも dryRunId 発行", async () => {
    const result = await callTransfer({
      data: { dryRun: true, fromUid: FROM_UID, toUid: TO_UID },
      auth: adminAuth(),
    });
    assert.equal(result.counts.recordings, 0);
    assert.ok(result.dryRunId);
  });
});

// ===== confirm: happy path + invariants =====

describe("transferOwnership: confirm (AC-2 / AC-3 / AC-5)", () => {
  async function setupDryRun() {
    await seedRecording(TENANT_ID, "r1", {
      createdBy: FROM_UID,
      clientName: "山田太郎",
      transcription: "original",
      audioStoragePath: "gs://bucket/tenant-a/r1.m4a",
      recordedAt: admin.firestore.Timestamp.fromDate(new Date("2026-04-01")),
    });
    await seedRecording(TENANT_ID, "r2", { createdBy: FROM_UID, clientName: "B" });
    await seedRecording(TENANT_ID, "r3", { createdBy: OTHER_UID, clientName: "C" });
    await seedTemplate(TENANT_ID, "t1", {
      createdBy: FROM_UID,
      createdByName: "旧姓田中",
      name: "訪問",
      outputType: "transcription",
    });
    await seedWhitelist(TENANT_ID, "w1", {
      email: "old@x.com",
      role: "admin",
      addedBy: FROM_UID,
    });

    const dryRun = await callTransfer({
      data: { dryRun: true, fromUid: FROM_UID, toUid: TO_UID },
      auth: adminAuth(),
    });
    return dryRun.dryRunId;
  }

  it("AC-2: confirm で 3 collection の対象フィールドが toUid に書換わる", async () => {
    const dryRunId = await setupDryRun();
    const result = await callTransfer({ data: { dryRunId }, auth: adminAuth() });
    assert.equal(result.ok, true);
    assert.equal(result.updated.recordings, 2);
    assert.equal(result.updated.templates, 1);
    assert.equal(result.updated.whitelist, 1);

    const r1 = await getRecording(TENANT_ID, "r1");
    const r3 = await getRecording(TENANT_ID, "r3");
    assert.equal(r1.createdBy, TO_UID);
    assert.equal(r3.createdBy, OTHER_UID, "unrelated uid untouched");

    const t1 = (await db.collection("tenants").doc(TENANT_ID).collection("templates").doc("t1").get()).data();
    assert.equal(t1.createdBy, TO_UID);

    const w1 = (await db.collection("tenants").doc(TENANT_ID).collection("whitelist").doc("w1").get()).data();
    assert.equal(w1.addedBy, TO_UID);
  });

  it("AC-3 (MUST): Partial Update — 対象外フィールド (createdByName, transcription, audioStoragePath, email, role) が不変", async () => {
    const dryRunId = await setupDryRun();
    await callTransfer({ data: { dryRunId }, auth: adminAuth() });

    const r1 = await getRecording(TENANT_ID, "r1");
    assert.equal(r1.clientName, "山田太郎", "recordings.clientName 不変");
    assert.equal(r1.transcription, "original", "recordings.transcription 不変");
    assert.equal(r1.audioStoragePath, "gs://bucket/tenant-a/r1.m4a", "recordings.audioStoragePath 不変");

    const t1 = (await db.collection("tenants").doc(TENANT_ID).collection("templates").doc("t1").get()).data();
    assert.equal(t1.createdByName, "旧姓田中", "templates.createdByName 不変 (意図的スナップショット)");
    assert.equal(t1.name, "訪問", "templates.name 不変");

    const w1 = (await db.collection("tenants").doc(TENANT_ID).collection("whitelist").doc("w1").get()).data();
    assert.equal(w1.email, "old@x.com", "whitelist.email 不変");
    assert.equal(w1.role, "admin", "whitelist.role 不変");
  });

  it("AC-5: confirm 後に migrationLogs に completed 記録される", async () => {
    const dryRunId = await setupDryRun();
    await callTransfer({ data: { dryRunId }, auth: adminAuth() });

    const logs = await getMigrationLogs(TENANT_ID);
    assert.equal(logs.length, 1);
    const log = logs[0];
    assert.equal(log.status, "completed");
    assert.equal(log.dryRunId, dryRunId);
    assert.equal(log.fromUid, FROM_UID);
    assert.equal(log.toUid, TO_UID);
    assert.equal(log.tenantId, TENANT_ID);
    assert.equal(log.recordingsUpdated, 2);
    assert.equal(log.templatesUpdated, 1);
    assert.equal(log.whitelistUpdated, 1);
    assert.ok(log.startedAt);
    assert.ok(log.completedAt);
  });

  it("confirm 後、migrationState.status = completed", async () => {
    const dryRunId = await setupDryRun();
    await callTransfer({ data: { dryRunId }, auth: adminAuth() });
    const state = await getMigrationState(TENANT_ID, dryRunId);
    assert.equal(state.status, "completed");
  });
});

// ===== confirm: already-exists / not-found =====

describe("transferOwnership: idempotency (AC-8)", () => {
  it("AC-8: 同じ dryRunId で 2 回 confirm → already-exists", async () => {
    await seedRecording(TENANT_ID, "r1", { createdBy: FROM_UID, clientName: "A" });
    const { dryRunId } = await callTransfer({
      data: { dryRun: true, fromUid: FROM_UID, toUid: TO_UID },
      auth: adminAuth(),
    });
    await callTransfer({ data: { dryRunId }, auth: adminAuth() });

    await assert.rejects(
      () => callTransfer({ data: { dryRunId }, auth: adminAuth() }),
      (err) => err.code === "already-exists"
    );
  });

  it("未発行の dryRunId → not-found", async () => {
    await assert.rejects(
      () =>
        callTransfer({
          data: { dryRunId: "00000000-0000-0000-0000-000000000000" },
          auth: adminAuth(),
        }),
      (err) => err.code === "not-found"
    );
  });
});

// ===== 500+ 件 chunked batch =====

describe("transferOwnership: 大量データ (AC-4)", () => {
  it("AC-4: 600 件 recordings でも全件更新完走", async function () {
    this.timeout(60000);
    const N = 600;
    const BATCH = 400;
    // Bulk seed via chunked writes.
    for (let offset = 0; offset < N; offset += BATCH) {
      const batch = db.batch();
      for (let i = offset; i < Math.min(N, offset + BATCH); i++) {
        const ref = db
          .collection("tenants").doc(TENANT_ID)
          .collection("recordings").doc(`r-${String(i).padStart(4, "0")}`);
        batch.set(ref, { createdBy: FROM_UID, idx: i });
      }
      await batch.commit();
    }

    const dryRun = await callTransfer({
      data: { dryRun: true, fromUid: FROM_UID, toUid: TO_UID },
      auth: adminAuth(),
    });
    assert.equal(dryRun.counts.recordings, N);

    const result = await callTransfer({ data: { dryRunId: dryRun.dryRunId }, auth: adminAuth() });
    assert.equal(result.updated.recordings, N);

    // Verify: no doc left with createdBy == FROM_UID
    const leftover = await db
      .collection("tenants").doc(TENANT_ID).collection("recordings")
      .where("createdBy", "==", FROM_UID)
      .count().get();
    assert.equal(leftover.data().count, 0);

    // Verify: all updated to TO_UID
    const switched = await db
      .collection("tenants").doc(TENANT_ID).collection("recordings")
      .where("createdBy", "==", TO_UID)
      .count().get();
    assert.equal(switched.data().count, N);
  });
});

// ===== deleteOldAuthUser がスコープ外 (AC-9) =====

describe("transferOwnership: スコープ制約 (AC-9)", () => {
  it("AC-9: SUT ファイルに deleteOldAuthUser / auth.deleteUser を含まない", () => {
    const fs = require("fs");
    const src = fs.readFileSync(require.resolve("../src/transferOwnership"), "utf8");
    assert.ok(!/deleteOldAuthUser/.test(src), "deleteOldAuthUser 未実装であること");
    assert.ok(!/\bauth\(\)\.deleteUser\b/.test(src), "admin Auth deleteUser 呼出なし");
    assert.ok(!/getAuth\(\)/.test(src), "Auth SDK 参照なし");
  });
});

// ===== 0 件 confirm =====

describe("transferOwnership: 0 件 confirm (境界値)", () => {
  it("対象 0 件の dryRunId で confirm しても completed に遷移し、migrationLogs に記録される", async () => {
    const { dryRunId } = await callTransfer({
      data: { dryRun: true, fromUid: FROM_UID, toUid: TO_UID },
      auth: adminAuth(),
    });

    const result = await callTransfer({ data: { dryRunId }, auth: adminAuth() });
    assert.equal(result.ok, true);
    assert.equal(result.updated.recordings || 0, 0);
    assert.equal(result.updated.templates || 0, 0);
    assert.equal(result.updated.whitelist || 0, 0);

    const state = await getMigrationState(TENANT_ID, dryRunId);
    assert.equal(state.status, "completed");

    const logs = await getMigrationLogs(TENANT_ID);
    assert.equal(logs.length, 1);
    assert.equal(logs[0].status, "completed");
  });
});

// ===== 中断再開 (AC-10) =====

describe("transferOwnership: 中断再開 (AC-10)", () => {
  it("failed 状態から同じ dryRunId で retry すると checkpoint から再開する", async () => {
    await seedRecording(TENANT_ID, "r1", { createdBy: FROM_UID });
    await seedRecording(TENANT_ID, "r2", { createdBy: FROM_UID });
    await seedRecording(TENANT_ID, "r3", { createdBy: FROM_UID });

    const { dryRunId } = await callTransfer({
      data: { dryRun: true, fromUid: FROM_UID, toUid: TO_UID },
      auth: adminAuth(),
    });

    // Simulate partial execution: manually set status=failed with checkpoint after r1.
    const stateRef = db
      .collection("tenants").doc(TENANT_ID)
      .collection("migrationState").doc(dryRunId);
    // Actually rewrite r1 directly to simulate previously applied batch
    await db.collection("tenants").doc(TENANT_ID).collection("recordings").doc("r1").update({ createdBy: TO_UID });
    await stateRef.update({
      status: "failed",
      checkpoint: { recordings: "r1" },
      updated: { recordings: 1 },
    });

    const result = await callTransfer({ data: { dryRunId }, auth: adminAuth() });
    assert.equal(result.ok, true);
    // Delta from retry = 2 (r2, r3), total = 1 (previous) + 2 (delta) = 3
    assert.equal(result.updated.recordings, 3);

    const leftover = await db
      .collection("tenants").doc(TENANT_ID).collection("recordings")
      .where("createdBy", "==", FROM_UID)
      .count().get();
    assert.equal(leftover.data().count, 0);
  });

  it("stale running 状態 (runningAt 15 分以上前) から retry 可能 (Cloud Function timeout 復旧)", async () => {
    await seedRecording(TENANT_ID, "r1", { createdBy: FROM_UID });
    const { dryRunId } = await callTransfer({
      data: { dryRun: true, fromUid: FROM_UID, toUid: TO_UID },
      auth: adminAuth(),
    });

    // Simulate a previous Cloud Function invocation that died without writing
    // completed/failed: status=running with a stale runningAt.
    const stateRef = db
      .collection("tenants").doc(TENANT_ID)
      .collection("migrationState").doc(dryRunId);
    const stale = admin.firestore.Timestamp.fromMillis(Date.now() - 20 * 60 * 1000);
    await stateRef.update({ status: "running", runningAt: stale });

    // Retry should succeed (not already-exists) because runningAt is stale.
    const result = await callTransfer({ data: { dryRunId }, auth: adminAuth() });
    assert.equal(result.ok, true);
    const r1 = await getRecording(TENANT_ID, "r1");
    assert.equal(r1.createdBy, TO_UID);
  });

  it("fresh running 状態 (runningAt が最近) は retry 時に already-exists で拒否", async () => {
    await seedRecording(TENANT_ID, "r1", { createdBy: FROM_UID });
    const { dryRunId } = await callTransfer({
      data: { dryRun: true, fromUid: FROM_UID, toUid: TO_UID },
      auth: adminAuth(),
    });
    const stateRef = db
      .collection("tenants").doc(TENANT_ID)
      .collection("migrationState").doc(dryRunId);
    // Fresh running (1 second ago) — active invocation in progress.
    const fresh = admin.firestore.Timestamp.fromMillis(Date.now() - 1000);
    await stateRef.update({ status: "running", runningAt: fresh });

    await assert.rejects(
      () => callTransfer({ data: { dryRunId }, auth: adminAuth() }),
      (err) => err.code === "already-exists"
    );
  });
});

// ===== Unit-ish tests for internals (no emulator required, but run together) =====

describe("transferOwnership: _internals.validateArgs", () => {
  it("dryRun + 有効な uid 組 → mode=dryRun", () => {
    const r = _internals.validateArgs({ dryRun: true, fromUid: "a", toUid: "b" });
    assert.deepEqual(r, { mode: "dryRun", fromUid: "a", toUid: "b" });
  });

  it("dryRunId → mode=confirm", () => {
    const r = _internals.validateArgs({ dryRunId: "xyz" });
    assert.deepEqual(r, { mode: "confirm", dryRunId: "xyz" });
  });

  it("null / undefined data → throws", () => {
    assert.throws(() => _internals.validateArgs(null), (err) => err.code === "invalid-argument");
    assert.throws(() => _internals.validateArgs(undefined), (err) => err.code === "invalid-argument");
  });

  it("空文字 dryRunId → throws", () => {
    assert.throws(() => _internals.validateArgs({ dryRunId: "" }), (err) => err.code === "invalid-argument");
  });

  it("空文字 fromUid → throws", () => {
    assert.throws(
      () => _internals.validateArgs({ dryRun: true, fromUid: "", toUid: "b" }),
      (err) => err.code === "invalid-argument"
    );
  });
});
