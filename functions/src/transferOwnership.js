"use strict";

const crypto = require("node:crypto");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");

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

/**
 * Verify that toUid exists in Firebase Auth and belongs to the target tenant
 * via custom claims. Since the Callable runs with admin SDK (bypassing rules),
 * Callable-level validation is the only guard against a typo rewriting
 * documents to an orphan / cross-tenant / non-existent uid.
 *
 * fromUid is intentionally NOT validated: it may be a deleted legacy account,
 * which is a primary use case (the old identity is gone and we are
 * transferring its orphaned documents to the new one).
 */
async function validateToUidBelongsToTenant(tenantId, toUid) {
  let user;
  try {
    user = await getAuth().getUser(toUid);
  } catch (err) {
    if (err.code === "auth/user-not-found") {
      throw new HttpsError(
        "invalid-argument",
        `toUid not found in Firebase Auth (likely typo)`
      );
    }
    throw new HttpsError("internal", `Failed to verify toUid: ${err.message}`);
  }
  const claimTenant = user.customClaims?.tenantId;
  if (claimTenant !== tenantId) {
    throw new HttpsError(
      "invalid-argument",
      `toUid belongs to tenant "${claimTenant || "<none>"}", expected "${tenantId}"`
    );
  }
}

/**
 * Reject new dryRun / confirm when another fresh (non-stale) migration for the
 * same fromUid is already active (prepared-within-TTL or running-within-TTL).
 * Prevents two different dryRunId's from racing writes against the same data.
 *
 * Called from both runDryRun (before creating state) and acquireRunningLock
 * (inside tx, before transitioning to running). Emulator tests cover both.
 */
async function assertNoConcurrentMigration(db, tenantId, fromUid, excludeDryRunId, now = Date.now()) {
  const snap = await db
    .collection("tenants").doc(tenantId)
    .collection("migrationState")
    .where("fromUid", "==", fromUid)
    .get();
  for (const doc of snap.docs) {
    if (doc.id === excludeDryRunId) continue;
    const d = doc.data();
    if (d.status === "completed" || d.status === "failed") continue;
    // prepared / running: check whether it is still fresh (within TTL).
    // runningAt drives running TTL; createdAt drives prepared TTL.
    const ra = d.runningAt?.toMillis?.() || 0;
    const ca = d.createdAt?.toMillis?.() || 0;
    const lastActivity = Math.max(ra, ca);
    if (lastActivity && now - lastActivity < STALE_RUNNING_MS) {
      throw new HttpsError(
        "already-exists",
        `Another active migration for fromUid "${fromUid}" (dryRunId=${doc.id}, status=${d.status})`
      );
    }
  }
}

/**
 * Build a structured error context that correlates Cloud Logging entries with
 * the HttpsError surfaced to the caller. `errorId` is a fresh UUID per call;
 * admins can grep Cloud Logging by `jsonPayload.errorId` once they receive the
 * id through the CLI stderr / migrationState.lastFailure / migrationLogs.error.
 * Safe against nullish, non-Error, and missing-code values so no catch branch
 * can silently swallow the id.
 */
function buildErrorContext(err) {
  const errorId = crypto.randomUUID();
  const code = (err && typeof err.code === "string" && err.code) || "internal";
  let message;
  if (err && typeof err.message === "string" && err.message.length > 0) {
    message = err.message;
  } else if (err === null || err === undefined) {
    message = "<unknown error>";
  } else {
    // String(new Error("")) returns "Error" which is useless in logs. Collapse
    // that and any other empty stringification to the explicit sentinel so the
    // log line is never blank and never silently pretends to carry a message.
    const str = String(err);
    message = str && str !== "Error" ? str : "<unknown error>";
  }
  const stack = err && typeof err.stack === "string" ? err.stack : null;
  return { errorId, code, message, stack };
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
  // Defense in depth: verify toUid is a real user in this tenant before we
  // persist any state. fromUid is allowed to be missing (deleted account use
  // case). Cross-tenant write is already structurally impossible (tenantId
  // comes from caller claim), but a typo in toUid would silently orphan data
  // since admin SDK bypasses rules.
  await validateToUidBelongsToTenant(tenantId, toUid);

  // Block concurrent/overlapping migrations for the same fromUid. Two
  // different dryRunIds both transitioning to running would race on the same
  // `where(createdBy == fromUid)` result set and split ownership
  // non-deterministically.
  await assertNoConcurrentMigration(db, tenantId, fromUid, null);

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
async function acquireRunningLock(db, tenantId, stateRef) {
  return db.runTransaction(async (tx) => {
    // Capture the wall-clock time INSIDE the transaction callback so each
    // retry re-evaluates staleness against a fresh timestamp.
    const now = Date.now();
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
    // Must be done inside tx (before writes) to read consistent state.
    // Firestore transactions disallow post-write reads, so this query runs
    // before tx.update below.
    await assertNoConcurrentMigration(db, tenantId, data.fromUid, stateRef.id, now);
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
    const lastDocIdInBatch = snap.docs[snap.docs.length - 1].id;
    // Commit checkpoint together with the data writes in one atomic batch.
    // If we split (batch.commit → stateRef.update), a post-commit crash loses
    // the checkpoint and the `updated.{collection}` counter, under-counting
    // the audit log. BATCH_SIZE=400 + 1 state write is well within the 500
    // Firestore batch limit.
    batch.update(stateRef, {
      [`checkpoint.${collection}`]: lastDocIdInBatch,
      [`updated.${collection}`]: FieldValue.increment(snap.size),
    });
    await batch.commit();
    updated += snap.size;
    lastDocId = lastDocIdInBatch;
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

  const stateBefore = await acquireRunningLock(db, tenantId, stateRef);
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
    // Commit the audit log AND the completed state transition in one atomic
    // batch. Separate writes would leave a window where `migrationLogs` has a
    // completed record while `migrationState.status` is still `running`, or
    // (worse, on retry) where state is already `completed` but logs are
    // missing. Both are violations of AC-5.
    const completionBatch = db.batch();
    completionBatch.set(logsRef, {
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
    completionBatch.update(stateRef, {
      status: "completed",
      completedAt: FieldValue.serverTimestamp(),
    });
    await completionBatch.commit();
    return { ok: true, updated };
  } catch (err) {
    const errCtx = buildErrorContext(err);
    // Persist only the fields Firestore can serialize safely. `stack` goes to
    // Cloud Logging (via logger.error below); copying it into Firestore would
    // bloat the doc without aiding forensics, since the errorId correlates both.
    const failurePayload = {
      errorId: errCtx.errorId,
      code: errCtx.code,
      message: errCtx.message,
    };
    // Structured log so Cloud Logging can be queried by jsonPayload.errorId.
    // stack is attached here (and only here) so we keep one source of truth.
    logger.error("[transferOwnership] confirm failed", {
      errorId: errCtx.errorId,
      dryRunId,
      tenantId,
      code: errCtx.code,
      message: errCtx.message,
      stack: errCtx.stack,
    });
    // Best-effort state transition; do not mask the original error even if
    // status write fails (orphaned running state is recoverable by re-run).
    try {
      await stateRef.update({
        status: "failed",
        lastFailure: failurePayload,
        failedAt: FieldValue.serverTimestamp(),
      });
    } catch (stateErr) {
      logger.error("[transferOwnership] failed to persist failed status", {
        errorId: errCtx.errorId,
        dryRunId,
        tenantId,
        stateErrCode: stateErr?.code,
        stateErrMessage: stateErr?.message,
        stateErrStack: stateErr?.stack,
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
      logger.error("[transferOwnership] failed to persist failed log", {
        errorId: errCtx.errorId,
        dryRunId,
        tenantId,
        logErrCode: logErr?.code,
        logErrMessage: logErr?.message,
        logErrStack: logErr?.stack,
      });
    }
    // Enrich both outgoing error shapes with errorId so callers (CLI / client)
    // can quote it back when filing a ticket. Preserve the original HttpsError
    // code/message so failed-precondition vs internal semantics are not lost.
    if (err instanceof HttpsError) {
      // Only spread `err.details` when it is a plain object. Arrays would leak
      // their numeric keys alongside errorId; primitives / null would throw or
      // silently drop. Non-object details are replaced with the errorId wrapper.
      const detailsIsPlainObject =
        err.details != null &&
        typeof err.details === "object" &&
        !Array.isArray(err.details);
      const enrichedDetails = detailsIsPlainObject
        ? { ...err.details, errorId: errCtx.errorId }
        : { errorId: errCtx.errorId };
      throw new HttpsError(err.code, err.message, enrichedDetails);
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
  STALE_RUNNING_MS,
  COLLECTIONS,
  validateArgs,
  authorizeCaller,
  validateToUidBelongsToTenant,
  assertNoConcurrentMigration,
  runDryRun,
  runConfirm,
  runCollectionUpdate,
  acquireRunningLock,
  buildErrorContext,
});
