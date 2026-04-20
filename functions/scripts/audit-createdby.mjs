#!/usr/bin/env node
// Usage: node functions/scripts/audit-createdby.mjs [PROJECT_ID]
//   PROJECT_ID defaults to carenote-dev-279.
//   Use carenote-prod-279 only after explicit approval (see CLAUDE.md Dev/Prod 分離).
//
// Audits the distribution of `createdBy` in every tenant's recordings
// collection. Motivated by issue #99: existing data was saved with an
// empty string, breaking deleteAccount and future ownership transfer.
//
// Uses Firestore REST API with gcloud user access token (IAM roles/datastore.viewer
// or higher required). Does not go through Admin SDK to avoid service account key handling.
// Access token is obtained via execFileSync (no shell) with hardcoded argv.

import { execFileSync } from "node:child_process";

const projectId = process.argv[2] || "carenote-dev-279";
const base = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;

function token() {
  return execFileSync("gcloud", ["auth", "print-access-token"]).toString().trim();
}

async function getJson(url) {
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${token()}` },
  });
  if (!res.ok) {
    throw new Error(`HTTP ${res.status} for ${url}: ${await res.text()}`);
  }
  return res.json();
}

async function listAllDocuments(path, pageSize = 300) {
  const docs = [];
  let pageToken = null;
  while (true) {
    const url = new URL(`${base}/${path}`);
    url.searchParams.set("pageSize", String(pageSize));
    if (pageToken) url.searchParams.set("pageToken", pageToken);
    const data = await getJson(url.toString());
    if (data.documents) docs.push(...data.documents);
    if (!data.nextPageToken) break;
    pageToken = data.nextPageToken;
  }
  return docs;
}

function emptyBucket() {
  return { empty: 0, missing: 0, nonEmpty: 0, uniqueUids: new Set() };
}

function summarize(bucket) {
  const total = bucket.empty + bucket.missing + bucket.nonEmpty;
  return { total, ...bucket, uniqueUidCount: bucket.uniqueUids.size };
}

async function audit() {
  console.log(`\nAuditing createdBy distribution in project: ${projectId}\n`);

  const tenants = await listAllDocuments("tenants");
  const overall = emptyBucket();
  const perTenant = [];

  for (const tenantDoc of tenants) {
    const tenantId = tenantDoc.name.split("/").pop();
    const recordings = await listAllDocuments(`tenants/${tenantId}/recordings`);

    const bucket = emptyBucket();
    for (const doc of recordings) {
      const fields = doc.fields || {};
      if (!("createdBy" in fields)) {
        bucket.missing++;
        overall.missing++;
      } else {
        const value = fields.createdBy.stringValue;
        if (value === undefined || value === null || value === "") {
          bucket.empty++;
          overall.empty++;
        } else {
          bucket.nonEmpty++;
          overall.nonEmpty++;
          bucket.uniqueUids.add(value);
          overall.uniqueUids.add(value);
        }
      }
    }
    perTenant.push({ tenantId, ...summarize(bucket) });
  }

  for (const t of perTenant) {
    console.log(`Tenant: ${t.tenantId}`);
    console.log(`  Total recordings : ${t.total}`);
    console.log(`  Empty string     : ${t.empty}`);
    console.log(`  Missing field    : ${t.missing}`);
    console.log(`  Non-empty        : ${t.nonEmpty} (${t.uniqueUidCount} unique uids)`);
    console.log();
  }

  const o = summarize(overall);
  console.log("=== OVERALL ===");
  console.log(`Total recordings : ${o.total}`);
  console.log(`Empty string     : ${o.empty}`);
  console.log(`Missing field    : ${o.missing}`);
  console.log(`Non-empty        : ${o.nonEmpty} (${o.uniqueUidCount} unique uids)`);
  console.log();

  const needsBackfill = o.empty + o.missing;
  if (needsBackfill > 0) {
    console.log(`⚠️  ${needsBackfill} recordings need backfill (empty or missing createdBy)`);
    process.exit(2);
  }
  console.log("✅ All recordings have non-empty createdBy.");
}

audit().catch((err) => {
  console.error(err);
  process.exit(1);
});
