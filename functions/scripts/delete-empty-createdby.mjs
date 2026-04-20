#!/usr/bin/env node
// Usage:
//   node functions/scripts/delete-empty-createdby.mjs <PROJECT_ID>            # dry-run (default)
//   node functions/scripts/delete-empty-createdby.mjs <PROJECT_ID> --execute  # actually delete
//
// Rationale: Issue #99 / Phase -1 A3.
// Existing recordings were saved with createdBy="" (pre PR #101 bug).
// `deleteAccount` filters by `createdBy == uid`, so these orphans are never removed.
// Per ADR-008 / stakeholder decision, they are treated as development/test data and deleted
// (Firestore doc + Cloud Storage audio object).
//
// Safety:
// - Targets ONLY recordings where `createdBy` is empty string / null / undefined / missing field.
// - Recordings with non-empty `createdBy` are never touched.
// - Dry-run is the default; `--execute` must be passed explicitly.
// - Uses Firestore / Cloud Storage REST with `gcloud auth print-access-token` (no SA key).

import { execFileSync } from "node:child_process";

const projectId = process.argv[2];
const shouldExecute = process.argv.includes("--execute");

if (!projectId) {
  console.error("Usage: node delete-empty-createdby.mjs <PROJECT_ID> [--execute]");
  process.exit(1);
}

const firestoreBase = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;

function token() {
  return execFileSync("gcloud", ["auth", "print-access-token"]).toString().trim();
}

async function restGet(url) {
  const res = await fetch(url, { headers: { Authorization: `Bearer ${token()}` } });
  if (!res.ok) throw new Error(`GET ${url} -> ${res.status}: ${await res.text()}`);
  return res.json();
}

async function restDelete(url) {
  const res = await fetch(url, {
    method: "DELETE",
    headers: { Authorization: `Bearer ${token()}` },
  });
  // 404 is acceptable (already deleted); others are errors.
  if (res.status !== 200 && res.status !== 204 && res.status !== 404) {
    throw new Error(`DELETE ${url} -> ${res.status}: ${await res.text()}`);
  }
  return res.status;
}

async function listAllDocs(path, pageSize = 300) {
  const docs = [];
  let pageToken = null;
  while (true) {
    const url = new URL(`${firestoreBase}/${path}`);
    url.searchParams.set("pageSize", String(pageSize));
    if (pageToken) url.searchParams.set("pageToken", pageToken);
    const data = await restGet(url.toString());
    if (data.documents) docs.push(...data.documents);
    if (!data.nextPageToken) break;
    pageToken = data.nextPageToken;
  }
  return docs;
}

function parseGsUri(uri) {
  if (!uri || typeof uri !== "string" || !uri.startsWith("gs://")) return null;
  const withoutScheme = uri.slice(5);
  const slash = withoutScheme.indexOf("/");
  if (slash === -1) return null;
  return {
    bucket: withoutScheme.slice(0, slash),
    object: withoutScheme.slice(slash + 1),
  };
}

async function deleteStorageObject(bucket, object) {
  const encoded = encodeURIComponent(object);
  const url = `https://storage.googleapis.com/storage/v1/b/${bucket}/o/${encoded}`;
  return restDelete(url);
}

async function deleteFirestoreDoc(docName) {
  return restDelete(`https://firestore.googleapis.com/v1/${docName}`);
}

function isEmptyCreatedBy(fields) {
  if (!("createdBy" in fields)) return true;
  const v = fields.createdBy.stringValue;
  return v === undefined || v === null || v === "";
}

async function main() {
  console.log(`\nMode     : ${shouldExecute ? "EXECUTE (will delete)" : "DRY-RUN (no changes)"}`);
  console.log(`Project  : ${projectId}\n`);

  const tenants = await listAllDocs("tenants");
  const targets = [];

  for (const tenantDoc of tenants) {
    const tenantId = tenantDoc.name.split("/").pop();
    const recordings = await listAllDocs(`tenants/${tenantId}/recordings`);
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
  const counters = {
    storageOk: 0,
    storageSkip: 0,
    storageErr: 0,
    firestoreOk: 0,
    firestoreErr: 0,
  };

  for (const t of targets) {
    const parsed = parseGsUri(t.audioStoragePath);
    if (parsed) {
      try {
        const s = await deleteStorageObject(parsed.bucket, parsed.object);
        console.log(`  storage   : gs://${parsed.bucket}/${parsed.object} -> ${s}`);
        counters.storageOk++;
      } catch (e) {
        console.error(`  storage ! : gs://${parsed.bucket}/${parsed.object}: ${e.message}`);
        counters.storageErr++;
      }
    } else {
      console.log(`  storage   : skipped (no parseable gs:// URI)`);
      counters.storageSkip++;
    }

    try {
      const s = await deleteFirestoreDoc(t.docName);
      console.log(`  firestore : ${t.docName} -> ${s}`);
      counters.firestoreOk++;
    } catch (e) {
      console.error(`  firestore!: ${t.docName}: ${e.message}`);
      counters.firestoreErr++;
    }
  }

  console.log(`\n=== Result ===`);
  console.log(`Storage  : ok=${counters.storageOk} skip=${counters.storageSkip} err=${counters.storageErr}`);
  console.log(`Firestore: ok=${counters.firestoreOk} err=${counters.firestoreErr}`);

  if (counters.firestoreErr > 0 || counters.storageErr > 0) {
    process.exit(2);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
