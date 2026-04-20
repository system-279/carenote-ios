"use strict";

const crypto = require("node:crypto");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

// Region is pinned to asia-northeast1 to match the rest of the functions module.
const REGION = "asia-northeast1";

// Under the 500-write Firestore batch limit. Headroom for concurrent migrationState
// checkpoints written from the same transaction context.
const BATCH_SIZE = 400;

// A `running` migrationState held longer than this is considered stale (caller
// process likely died mid-execution) and may be retried. Must exceed the
// Cloud Function max timeout (540s) with margin so we never misclassify an
// active run as stale.
const STALE_RUNNING_MS = 15 * 60 * 1000; // 15 minutes

// 3 subcollections that carry a uid-shaped field per ADR-008 Phase 0.
// { name: subcollection name under tenants/{tid}, field: document field to rewrite }
const COLLECTIONS = Object.freeze([
  Object.freeze({ name: "recordings", field: "createdBy" }),
  Object.freeze({ name: "templates", field: "createdBy" }),
  Object.freeze({ name: "whitelist", field: "addedBy" }),
]);

/**
 * Validate Callable request.data and decide operation mode.
 * - mode = "dryRun" : requires fromUid + toUid (distinct non-empty strings)
 * - mode = "confirm" : requires dryRunId (non-empty string)
 * Throws HttpsError on invalid input.
 */
function validateArgs(data) {
  if (!data || typeof data !== "object") {
    throw new HttpsError("invalid-argument", "Request data missing");
  }
  const { fromUid, toUid, dryRun, dryRunId } = data;

  if (dryRunId !== undefined && dryRunId !== null) {
    if (typeof dryRunId !== "string" || dryRunId.length === 0) {
      throw new HttpsError("invalid-argument", "dryRunId must be non-empty string");
    }
    return { mode: "confirm", dryRunId };
  }

  if (dryRun !== true) {
    throw new HttpsError(
      "invalid-argument",
      "Either dryRun=true (to preview) or dryRunId (to confirm) is required"
    );
  }
  if (typeof fromUid !== "string" || fromUid.length === 0) {
    throw new HttpsError("invalid-argument", "fromUid (non-empty string) is required");
  }
  if (typeof toUid !== "string" || toUid.length === 0) {
    throw new HttpsError("invalid-argument", "toUid (non-empty string) is required");
  }
  if (fromUid === toUid) {
    throw new HttpsError("invalid-argument", "fromUid must differ from toUid");
  }
  return { mode: "dryRun", fromUid, toUid };
}

/**
 * Authorize the caller and pick the tenant from their token.
 * Tenant is never taken from request.data to keep cross-tenant writes
 * structurally impossible.
 */
function authorizeCaller(request) {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "ログインが必要です");
  }
  const role = request.auth?.token?.role;
  if (role !== "admin") {
    throw new HttpsError("permission-denied", "管理者のみ実行可能です");
  }
  const tenantId = request.auth?.token?.tenantId;
  if (typeof tenantId !== "string" || tenantId.length === 0) {
    throw new HttpsError("failed-precondition", "tenantId claim missing from caller token");
  }
  return { callerUid: uid, tenantId };
}

async function countMatchingDocs(db, tenantId, collection, field, uid) {
  const snap = await db
    .collection("tenants").doc(tenantId).collection(collection)
    .where(field, "==", uid)
    .count()
    .get();
  return snap.data().count;
}

/**
 * Phase 1: preview (dryRun) — counts matching docs per collection and creates
 * a migrationState doc in status=prepared. Returns dryRunId + counts.
 */
async function runDryRun({ db, tenantId, fromUid, toUid }) {
  const counts = {};
  for (const { name, field } of COLLECTIONS) {
    counts[name] = await countMatchingDocs(db, tenantId, name, field, fromUid);
  }
  const dryRunId = crypto.randomUUID();
  await db
    .collection("tenants").doc(tenantId)
    .collection("migrationState").doc(dryRunId)
    .set({
      status: "prepared",
      fromUid,
      toUid,
      counts,
      createdAt: FieldValue.serverTimestamp(),
    });
  return { dryRunId, counts };
}

/**
 * Atomically transition migrationState from prepared/failed to running.
 * Throws already-exists if running/completed.
 *
 * A `running` state whose `runningAt` timestamp is older than STALE_RUNNING_MS
 * is considered stale (previous invocation crashed/was killed before writing
 * completed/failed) and is eligible for retry. This is the recovery path for
 * the 540s Cloud Function timeout case where no catch block ever fires.
 */
async function acquireRunningLock(db, stateRef, now = Date.now()) {
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(stateRef);
    if (!snap.exists) {
      throw new HttpsError("not-found", "dryRunId not found (expired or never existed)");
    }
    const data = snap.data();
    if (data.status === "completed") {
      throw new HttpsError("already-exists", "Migration already completed");
    }
    if (data.status === "running") {
      const runningAtMs = data.runningAt?.toMillis ? data.runningAt.toMillis() : 0;
      if (runningAtMs && now - runningAtMs < STALE_RUNNING_MS) {
        throw new HttpsError("already-exists", "Migration already running");
      }
      // Stale: proceed to re-acquire. Previous run's checkpoint survives and
      // will be picked up by runCollectionUpdate.
    } else if (data.status !== "prepared" && data.status !== "failed") {
      throw new HttpsError(
        "failed-precondition",
        `Unexpected migrationState.status: ${data.status}`
      );
    }
    tx.update(stateRef, {
      status: "running",
      startedAt: data.startedAt || FieldValue.serverTimestamp(),
      runningAt: FieldValue.serverTimestamp(),
      lastFailure: FieldValue.delete(),
    });
    return data;
  });
}

/**
 * Apply chunked batch updates for one collection, writing checkpoints into
 * migrationState so that a crashed run can resume from the last committed batch.
 * Returns the number of docs updated in this invocation (not including any
 * already-updated docs carried over from a previous failed run).
 */
async function runCollectionUpdate({
  db,
  tenantId,
  collection,
  field,
  fromUid,
  toUid,
  stateRef,
  resumeFromDocId,
}) {
  let lastDocId = resumeFromDocId || null;
  let updated = 0;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    let q = db
      .collection("tenants").doc(tenantId).collection(collection)
      .where(field, "==", fromUid)
      .orderBy("__name__")
      .limit(BATCH_SIZE);
    if (lastDocId) {
      q = q.startAfter(lastDocId);
    }
    const snap = await q.get();
    if (snap.empty) {
      break;
    }
    const batch = db.batch();
    for (const doc of snap.docs) {
      batch.update(doc.ref, { [field]: toUid });
    }
    await batch.commit();
    updated += snap.size;
    lastDocId = snap.docs[snap.docs.length - 1].id;
    await stateRef.update({
      [`checkpoint.${collection}`]: lastDocId,
      [`updated.${collection}`]: FieldValue.increment(snap.size),
    });
    if (snap.size < BATCH_SIZE) {
      break;
    }
  }
  return updated;
}

/**
 * Phase 1: confirm — transitions prepared→running, rewrites all 3 collections,
 * writes migrationLogs, transitions to completed/failed.
 */
async function runConfirm({ db, tenantId, dryRunId }) {
  const stateRef = db
    .collection("tenants").doc(tenantId)
    .collection("migrationState").doc(dryRunId);
  const logsRef = db
    .collection("tenants").doc(tenantId)
    .collection("migrationLogs").doc();

  const stateBefore = await acquireRunningLock(db, stateRef);
  const { fromUid, toUid } = stateBefore;
  const previousCheckpoint = stateBefore.checkpoint || {};
  const previousUpdated = stateBefore.updated || {};

  const updated = {};
  try {
    for (const { name, field } of COLLECTIONS) {
      const delta = await runCollectionUpdate({
        db,
        tenantId,
        collection: name,
        field,
        fromUid,
        toUid,
        stateRef,
        resumeFromDocId: previousCheckpoint[name] || null,
      });
      updated[name] = (previousUpdated[name] || 0) + delta;
    }
    // Write the audit log BEFORE flipping migrationState to completed so that
    // a process death between these two writes leaves the state as `running`
    // (recoverable via STALE_RUNNING_MS stale detection) rather than
    // `completed` with no audit record.
    await logsRef.set({
      dryRunId,
      status: "completed",
      fromUid,
      toUid,
      tenantId,
      recordingsUpdated: updated.recordings || 0,
      templatesUpdated: updated.templates || 0,
      whitelistUpdated: updated.whitelist || 0,
      startedAt: stateBefore.startedAt || FieldValue.serverTimestamp(),
      completedAt: FieldValue.serverTimestamp(),
    });
    await stateRef.update({
      status: "completed",
      completedAt: FieldValue.serverTimestamp(),
    });
    return { ok: true, updated };
  } catch (err) {
    const failurePayload = {
      code: err.code || "internal",
      message: err.message || String(err),
    };
    // Best-effort state transition; do not mask the original error even if
    // status write fails (orphaned running state is recoverable by re-run).
    try {
      await stateRef.update({
        status: "failed",
        lastFailure: failurePayload,
        failedAt: FieldValue.serverTimestamp(),
      });
    } catch (stateErr) {
      console.error("[transferOwnership] failed to persist failed status", {
        dryRunId,
        tenantId,
        stateErr: stateErr.message,
      });
    }
    try {
      await logsRef.set({
        dryRunId,
        status: "failed",
        fromUid,
        toUid,
        tenantId,
        error: failurePayload,
        startedAt: stateBefore.startedAt || FieldValue.serverTimestamp(),
        failedAt: FieldValue.serverTimestamp(),
      });
    } catch (logErr) {
      console.error("[transferOwnership] failed to persist failed log", {
        dryRunId,
        tenantId,
        logErr: logErr.message,
      });
    }
    if (err instanceof HttpsError) {
      throw err;
    }
    throw new HttpsError("internal", "transferOwnership failed", failurePayload);
  }
}

exports.transferOwnership = onCall(
  { region: REGION, timeoutSeconds: 540 },
  async (request) => {
    const { tenantId } = authorizeCaller(request);
    const args = validateArgs(request.data);
    const db = getFirestore();
    if (args.mode === "dryRun") {
      return runDryRun({ db, tenantId, fromUid: args.fromUid, toUid: args.toUid });
    }
    return runConfirm({ db, tenantId, dryRunId: args.dryRunId });
  }
);

// Exports for unit / integration tests.
exports._internals = Object.freeze({
  REGION,
  BATCH_SIZE,
  COLLECTIONS,
  validateArgs,
  authorizeCaller,
  runDryRun,
  runConfirm,
  runCollectionUpdate,
  acquireRunningLock,
});
