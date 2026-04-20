#!/usr/bin/env node
// Usage:
//   node functions/scripts/delete-empty-createdby.mjs <PROJECT_ID>            # dry-run (default)
//   node functions/scripts/delete-empty-createdby.mjs <PROJECT_ID> --execute  # actually delete
//
// Prod deletion additionally requires the CONFIRM_PROD=yes environment variable.
//
// Rationale: Issue #99.
// Existing recordings were saved with createdBy="" (pre PR #101 bug).
// `deleteAccount` filters by `createdBy == uid`, so these orphans are never removed.
// Per ADR-008 / stakeholder decision, they are treated as development/test data
// and deleted (Firestore doc + Cloud Storage audio object).
//
// Safety:
// - Dry-run is the default. `--execute` must be passed explicitly, AND prod
//   additionally requires CONFIRM_PROD=yes (multi-layer guard against the
//   dev/prod mix-up risk called out in CLAUDE.md Dev/Prod 分離).
// - Targets ONLY recordings where createdBy is empty string, nullValue, or
//   missing field. Unknown REST value shapes are treated as populated so we
//   never delete a record we don't fully understand.
// - Storage is deleted BEFORE Firestore. On Storage error, the Firestore
//   delete is skipped to avoid orphaning the audio object (the same class of
//   bug we're here to clean up).
// - Before each delete, the document is re-fetched and re-checked (TOCTOU
//   guard) so a concurrent backfill can't be clobbered.
// - Firestore DELETE requires 200/204 (404 is treated as a URL/consistency
//   bug, not silent idempotency). Cloud Storage DELETE accepts 404 because
//   the GCS API documents that as idempotent.
// - gcloud user token is used (not a SA key) so the audit trail attributes
//   deletions to the operator; SA key distribution is also prohibited by
//   project CLAUDE.md.

import { execFileSync } from "node:child_process";

export function isEmptyCreatedBy(fields) {
  const f = fields?.createdBy;
  if (f === undefined) return true;
  if ("nullValue" in f) return true;
  if ("stringValue" in f) return f.stringValue === "";
  return false;
}

export function parseGsUri(uri) {
  if (typeof uri !== "string" || !uri.startsWith("gs://")) return null;
  const rest = uri.slice(5);
  const slash = rest.indexOf("/");
  if (slash <= 0) return null;
  const object = rest.slice(slash + 1);
  if (object === "") return null;
  return { bucket: rest.slice(0, slash), object };
}

const isDirectRun = import.meta.url === `file://${process.argv[1]}`;
if (isDirectRun) {
  runCli().catch((err) => {
    console.error(err?.stack || err?.message || err);
    process.exit(1);
  });
}

async function runCli() {
  const projectId = process.argv[2];
  const shouldExecute = process.argv.includes("--execute");

  if (!projectId) {
    console.error("Usage: node delete-empty-createdby.mjs <PROJECT_ID> [--execute]");
    console.error("  <PROJECT_ID>: carenote-dev-279 | carenote-prod-279");
    console.error("  Prod additionally requires CONFIRM_PROD=yes.");
    process.exit(1);
  }

  const isProd = projectId === "carenote-prod-279";
  if (isProd && shouldExecute && process.env.CONFIRM_PROD !== "yes") {
    console.error(`Refusing to --execute against ${projectId} without CONFIRM_PROD=yes.`);
    console.error(
      `Run: CONFIRM_PROD=yes node functions/scripts/delete-empty-createdby.mjs ${projectId} --execute`,
    );
    process.exit(1);
  }

  try {
    const activeProject = execFileSync("gcloud", ["config", "get-value", "project"])
      .toString()
      .trim();
    if (activeProject && activeProject !== projectId) {
      console.warn(
        `Warning: active gcloud project '${activeProject}' differs from target '${projectId}'.`,
      );
      console.warn(
        `  Recommended: CLOUDSDK_ACTIVE_CONFIG_NAME=<matching-config> node ...`,
      );
    }
  } catch {
    // best-effort; continue
  }

  const token = fetchAccessToken();
  const rest = makeRestClient(token);
  const firestoreBase = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;

  console.log(`\nMode     : ${shouldExecute ? "EXECUTE (will delete)" : "DRY-RUN (no changes)"}`);
  console.log(`Project  : ${projectId}\n`);

  const counters = {
    targetsFound: 0,
    storageOk: 0,
    storageSkip: 0,
    storageErr: 0,
    firestoreOk: 0,
    firestoreSkip: 0,
    firestoreErr: 0,
    toctouSkipped: 0,
  };

  try {
    const targets = await collectTargets(rest, firestoreBase);
    counters.targetsFound = targets.length;

    console.log(`Targets : ${targets.length}\n`);
    for (const t of targets) {
      console.log(
        `  [${t.tenantId}] ${t.id}  audio=${t.audioStoragePath || "(none)"}  recordedAt=${t.recordedAt || "(none)"}`,
      );
    }

    if (!shouldExecute) {
      console.log(`\nDRY-RUN finished. Re-run with --execute to actually delete.`);
      return;
    }
    if (targets.length === 0) {
      console.log("\nNothing to delete.");
      return;
    }

    console.log("\nExecuting deletion...\n");
    for (const t of targets) {
      const fresh = await rest.get(`https://firestore.googleapis.com/v1/${t.docName}`);
      if (!isEmptyCreatedBy(fresh.fields || {})) {
        console.warn(`  skip (TOCTOU): ${t.docName} no longer has empty createdBy`);
        counters.toctouSkipped++;
        continue;
      }

      const parsed = parseGsUri(t.audioStoragePath);
      if (parsed) {
        try {
          await rest.deleteStorageObject(parsed.bucket, parsed.object);
          console.log(`  storage   : gs://${parsed.bucket}/${parsed.object} -> ok`);
          counters.storageOk++;
        } catch (e) {
          console.error(`  storage ! : gs://${parsed.bucket}/${parsed.object}: ${e.message}`);
          console.error(`  firestore!: SKIPPED (storage failed; avoiding orphan)`);
          counters.storageErr++;
          counters.firestoreSkip++;
          continue;
        }
      } else {
        counters.storageSkip++;
      }

      try {
        await rest.deleteFirestoreDoc(t.docName);
        console.log(`  firestore : ${t.docName} -> ok`);
        counters.firestoreOk++;
      } catch (e) {
        console.error(`  firestore!: ${t.docName}: ${e.message}`);
        counters.firestoreErr++;
      }
    }
  } finally {
    console.log(`\n=== Result ===`);
    console.log(`Targets  : ${counters.targetsFound}`);
    console.log(`Storage  : ok=${counters.storageOk} skip=${counters.storageSkip} err=${counters.storageErr}`);
    console.log(
      `Firestore: ok=${counters.firestoreOk} skip=${counters.firestoreSkip} err=${counters.firestoreErr}`,
    );
    if (counters.toctouSkipped > 0) {
      console.log(`TOCTOU skipped: ${counters.toctouSkipped}`);
    }
  }

  if (counters.firestoreErr > 0 || counters.storageErr > 0) {
    process.exit(2);
  }
}

async function collectTargets(rest, firestoreBase) {
  const tenants = await listAllDocs(rest, firestoreBase, "tenants");
  const targets = [];
  for (const tenantDoc of tenants) {
    const tenantId = tenantDoc.name.split("/").pop();
    const recordings = await listAllDocs(rest, firestoreBase, `tenants/${tenantId}/recordings`);
    for (const rec of recordings) {
      if (isEmptyCreatedBy(rec.fields || {})) {
        targets.push({
          tenantId,
          id: rec.name.split("/").pop(),
          docName: rec.name,
          audioStoragePath: rec.fields?.audioStoragePath?.stringValue,
          recordedAt: rec.fields?.recordedAt?.timestampValue,
        });
      }
    }
  }
  return targets;
}

async function listAllDocs(rest, firestoreBase, path, pageSize = 300) {
  const docs = [];
  let pageToken = null;
  while (true) {
    const url = new URL(`${firestoreBase}/${path}`);
    url.searchParams.set("pageSize", String(pageSize));
    if (pageToken) url.searchParams.set("pageToken", pageToken);
    const data = await rest.get(url.toString());
    if (data.documents) docs.push(...data.documents);
    if (!data.nextPageToken) break;
    pageToken = data.nextPageToken;
  }
  return docs;
}

function fetchAccessToken() {
  try {
    return execFileSync("gcloud", ["auth", "print-access-token"]).toString().trim();
  } catch (e) {
    console.error("Failed to obtain gcloud access token.");
    console.error("Ensure gcloud is installed and you are logged in:");
    console.error("  gcloud auth login");
    throw e;
  }
}

function makeRestClient(token) {
  const authHeader = { Authorization: `Bearer ${token}` };

  async function get(url) {
    const res = await fetch(url, { headers: authHeader });
    if (!res.ok) throw new Error(`GET ${url} -> ${res.status}: ${await res.text()}`);
    return res.json();
  }

  async function deleteFirestoreDoc(docName) {
    const url = `https://firestore.googleapis.com/v1/${docName}`;
    const res = await fetch(url, { method: "DELETE", headers: authHeader });
    if (res.status !== 200 && res.status !== 204) {
      throw new Error(`DELETE ${docName} -> ${res.status}: ${await res.text()}`);
    }
  }

  async function deleteStorageObject(bucket, object) {
    const url = `https://storage.googleapis.com/storage/v1/b/${bucket}/o/${encodeURIComponent(object)}`;
    const res = await fetch(url, { method: "DELETE", headers: authHeader });
    if (res.status !== 200 && res.status !== 204 && res.status !== 404) {
      throw new Error(`DELETE ${bucket}/${object} -> ${res.status}: ${await res.text()}`);
    }
  }

  return { get, deleteFirestoreDoc, deleteStorageObject };
}
