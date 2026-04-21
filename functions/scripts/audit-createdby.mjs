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
//
// Exit codes:
//   0 — all recordings have non-empty createdBy (clean)
//   1 — unrecoverable error OR at least one tenant failed to audit (audit is incomplete)
//   2 — audit succeeded for every tenant but backfill is needed (≥1 empty or missing createdBy)
// Shell callers should treat exit 2 as "work to do", not as failure.
// Exit 1 from a partial-tenant failure is preferred over exit 2 so callers cannot
// mistake an incomplete audit for a clean or actionable result.

import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

// gcloud access tokens live ~60 min. Refresh at 55 min to leave headroom.
const TOKEN_TTL_MS = 55 * 60 * 1000;
// Hard cap to break out of a Firestore pageToken loop that fails to progress.
// 1000 pages × 300 pageSize = 300k docs upper bound — well above any realistic tenant.
const MAX_PAGES = 1000;
// Exponential backoff for 429 / 5xx; max 3 attempts total (initial + 2 retries).
const MAX_RETRIES = 2;
const BACKOFF_BASE_MS = 1000;

let cachedToken = null;
let cachedAt = 0;

function invalidateToken() {
  cachedToken = null;
  cachedAt = 0;
}

function token() {
  const now = Date.now();
  if (cachedToken && now - cachedAt < TOKEN_TTL_MS) return cachedToken;
  const fresh = execFileSync("gcloud", ["auth", "print-access-token"]).toString().trim();
  if (!fresh) {
    throw new Error(
      "gcloud auth print-access-token returned empty; run `gcloud auth login` and retry."
    );
  }
  cachedToken = fresh;
  cachedAt = now;
  return cachedToken;
}

function httpError(status, url, body, projectId) {
  if (status === 401) {
    return new Error(
      `HTTP 401 for ${url}: gcloud セッションが期限切れです。\n` +
        `  → \`gcloud auth login\` を実行してから再試行してください。\n` +
        `  response: ${body}`
    );
  }
  if (status === 403) {
    return new Error(
      `HTTP 403 for ${url}: Firestore 読取権限がありません。\n` +
        `  → 現在のアカウントに roles/datastore.viewer (または上位) を付与してください。\n` +
        `    確認: gcloud projects get-iam-policy ${projectId} --flatten="bindings[].members"\n` +
        `  response: ${body}`
    );
  }
  if (status === 429) {
    return new Error(
      `HTTP 429 for ${url}: Firestore API のレート制限を超過しました (計 ${MAX_RETRIES + 1} 回試行後)。\n` +
        `  → 時間をおいて再試行、または pageSize を下げてください。\n` +
        `  response: ${body}`
    );
  }
  return new Error(`HTTP ${status} for ${url}: ${body}`);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Factory: binds the network helpers to a projectId so auditCreatedBy stays
// pure and test-injectable. Tests do NOT go through this factory; they pass
// their own `listDocuments` implementation.
function createDefaultListDocuments(projectId) {
  const base = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;

  async function getJson(url) {
    let lastStatus = 0;
    let lastBody = "";
    for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
      let res;
      try {
        res = await fetch(url, {
          headers: { Authorization: `Bearer ${token()}` },
        });
      } catch (err) {
        // fetch throws on network-level failures (DNS, ECONNRESET, AbortError).
        // Treat them as transient and retry in the same backoff envelope as 5xx.
        lastStatus = -1;
        lastBody = `network error: ${err.message}`;
        if (attempt === MAX_RETRIES) break;
        const backoff = BACKOFF_BASE_MS * Math.pow(2, attempt);
        console.warn(`  retry ${attempt + 1}/${MAX_RETRIES} after ${backoff}ms (${lastBody})`);
        await sleep(backoff);
        continue;
      }
      if (res.ok) return res.json();

      lastStatus = res.status;
      lastBody = await res.text();

      // 401 typically means token expired; invalidate the cache and retry once
      // so long-running audits survive the 55min TTL boundary.
      if (res.status === 401) {
        invalidateToken();
        if (attempt === MAX_RETRIES) break;
        console.warn(`  retry ${attempt + 1}/${MAX_RETRIES} after token refresh (HTTP 401)`);
        continue;
      }

      const retryable = res.status === 429 || (res.status >= 500 && res.status < 600);
      if (!retryable || attempt === MAX_RETRIES) break;

      const backoff = BACKOFF_BASE_MS * Math.pow(2, attempt);
      console.warn(
        `  retry ${attempt + 1}/${MAX_RETRIES} after ${backoff}ms (HTTP ${res.status})`
      );
      await sleep(backoff);
    }
    throw httpError(lastStatus, url, lastBody, projectId);
  }

  return async function listAllDocuments(path, pageSize = 300) {
    const docs = [];
    let pageToken = null;
    for (let page = 0; page < MAX_PAGES; page++) {
      const url = new URL(`${base}/${path}`);
      url.searchParams.set("pageSize", String(pageSize));
      if (pageToken) url.searchParams.set("pageToken", pageToken);
      const data = await getJson(url.toString());
      if (data.documents) docs.push(...data.documents);
      if (!data.nextPageToken) return docs;
      // Guard against a stuck pageToken: if the server returns the same token
      // we just sent, pagination is not advancing — bail rather than loop.
      if (data.nextPageToken === pageToken) {
        throw new Error(
          `Firestore pageToken did not advance at page ${page} for ${path}; aborting to avoid infinite loop.`
        );
      }
      pageToken = data.nextPageToken;
    }
    throw new Error(
      `Exceeded MAX_PAGES=${MAX_PAGES} for ${path}; if this is legitimate, increase MAX_PAGES after reviewing.`
    );
  };
}

function emptyBucket() {
  return { empty: 0, missing: 0, nonEmpty: 0, uniqueUids: new Set() };
}

function summarize(bucket) {
  const total = bucket.empty + bucket.missing + bucket.nonEmpty;
  return { total, ...bucket, uniqueUidCount: bucket.uniqueUids.size };
}

/**
 * Walk every tenant's recordings and aggregate createdBy statistics.
 *
 * Failures while listing an individual tenant's recordings are isolated:
 * they do not abort the audit. The failing tenant is recorded in
 * `failedTenants` and surfaced in `perTenant` with an `error` field, so the
 * already-aggregated stats from earlier tenants are never discarded.
 *
 * Callers decide process exit codes from the returned shape:
 *   - `failedTenants.length > 0` → the audit is incomplete; treat as failure
 *     (prefer over `needsBackfill` to avoid claiming a partial audit is clean).
 *   - `needsBackfill > 0` → audit complete but backfill required.
 *   - otherwise clean.
 *
 * @param {object} options
 * @param {(path: string) => Promise<Array<{ name: string, fields?: object }>>} options.listDocuments
 *   Required. Returns Firestore REST documents at `path`. Tests inject a stub.
 * @param {(message?: any, ...rest: any[]) => void} [options.log]  Defaults to `console.log`.
 * @param {(message?: any, ...rest: any[]) => void} [options.warn] Defaults to `console.warn`.
 */
export async function auditCreatedBy({
  listDocuments,
  log = console.log,
  warn = console.warn,
} = {}) {
  if (typeof listDocuments !== "function") {
    throw new TypeError("auditCreatedBy: `listDocuments` option is required.");
  }

  const tenants = await listDocuments("tenants");
  const overall = emptyBucket();
  const perTenant = [];
  const failedTenants = [];

  for (const tenantDoc of tenants) {
    const tenantId = tenantDoc.name.split("/").pop();
    try {
      const recordings = await listDocuments(`tenants/${tenantId}/recordings`);
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
    } catch (err) {
      const message = err && err.message ? err.message : String(err);
      failedTenants.push({ tenantId, error: message });
      perTenant.push({ tenantId, error: message });
      warn(`⚠️  tenant ${tenantId} audit failed: ${message}`);
    }
  }

  for (const t of perTenant) {
    log(`Tenant: ${t.tenantId}`);
    if (t.error) {
      log(`  (audit failed: ${t.error})`);
      log();
      continue;
    }
    log(`  Total recordings : ${t.total}`);
    log(`  Empty string     : ${t.empty}`);
    log(`  Missing field    : ${t.missing}`);
    log(`  Non-empty        : ${t.nonEmpty} (${t.uniqueUidCount} unique uids)`);
    log();
  }

  const o = summarize(overall);
  log("=== OVERALL ===");
  log(`Total recordings : ${o.total}`);
  log(`Empty string     : ${o.empty}`);
  log(`Missing field    : ${o.missing}`);
  log(`Non-empty        : ${o.nonEmpty} (${o.uniqueUidCount} unique uids)`);
  log();

  const needsBackfill = o.empty + o.missing;

  if (failedTenants.length > 0) {
    warn(
      `⚠️  ${failedTenants.length} tenant(s) failed to audit; overall counts above are INCOMPLETE. ` +
        `Re-run after resolving the underlying error before acting on these numbers.`
    );
  }
  if (needsBackfill > 0) {
    log(`⚠️  ${needsBackfill} recordings need backfill (empty or missing createdBy)`);
  } else if (failedTenants.length === 0) {
    log("✅ All recordings have non-empty createdBy.");
  }

  return {
    perTenant,
    overall: o,
    failedTenants,
    needsBackfill,
  };
}

// CLI entry point — runs only when invoked as a script, not when imported for tests.
function isCliEntry() {
  if (!process.argv[1]) return false;
  try {
    return fileURLToPath(import.meta.url) === process.argv[1];
  } catch {
    return false;
  }
}

if (isCliEntry()) {
  const projectId = process.argv[2] || "carenote-dev-279";
  console.log(`\nAuditing createdBy distribution in project: ${projectId}\n`);

  const listDocuments = createDefaultListDocuments(projectId);
  auditCreatedBy({ listDocuments })
    .then(({ failedTenants, needsBackfill }) => {
      // Exit-code priority is deliberate: an incomplete audit (exit 1) must not
      // be downgraded to "backfill needed" (exit 2) or "clean" (exit 0).
      if (failedTenants.length > 0) process.exit(1);
      if (needsBackfill > 0) process.exit(2);
      process.exit(0);
    })
    .catch((err) => {
      console.error(err);
      process.exit(1);
    });
}
