#!/usr/bin/env node
// Admin operator CLI for invoking the `transferOwnership` Callable Function.
//
// Usage (dev):
//   node functions/scripts/call-transfer-ownership.mjs \
//     --project carenote-dev-279 \
//     --from-uid <old uid> \
//     --to-uid <new uid> \
//     --dry-run
//   # → prints dryRunId and per-collection counts
//
//   node functions/scripts/call-transfer-ownership.mjs \
//     --project carenote-dev-279 \
//     --dry-run-id <uuid> \
//     --confirm
//   # → executes the migration
//
// Usage (prod): additionally set CONFIRM_PROD=yes environment variable.
//
// The caller must be an admin of the target tenant. The tenantId is taken from
// the caller's custom claim; we do NOT pass tenantId as an argument (mirroring
// the Callable signature to keep cross-tenant writes structurally impossible).
//
// Authentication: an OAuth2 access token is obtained via
// `gcloud auth print-identity-token --impersonate-service-account=...`
// and used as the Callable's Authorization header. The impersonated service
// account must have the caller's admin custom claims minted by a preceding
// `auth().setCustomUserClaims` operation, OR the caller's real uid token must
// be supplied via --id-token.
//
// Simplest mode: supply an admin user id token explicitly.
//   --id-token $(firebase auth:export ...) — see RUNBOOK in ADR-008 Phase 1.
//
// NOTE (2026-04-21): This CLI requires --id-token until the admin-id-token
// issuing RUNBOOK is finalized. For initial dev smoke tests, invoke the
// Callable from `firebase functions:shell` or the Firestore emulator shell
// which bypasses Authorization header verification. Prod runs MUST use a
// real Firebase Auth admin id token.

import { execFileSync } from "node:child_process";
import process from "node:process";

// Explicit allowlist, mirroring get-admin-id-token.mjs, to prevent
// `includes("prod")` from misclassifying new prod/sandbox names.
const PROD_PROJECTS = new Set(["carenote-prod-279"]);
const DEV_PROJECTS = new Set(["carenote-dev-279"]);

function isProdProject(project) {
  return PROD_PROJECTS.has(project);
}

function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    switch (a) {
      case "--project":
        args.project = argv[++i];
        break;
      case "--from-uid":
        args.fromUid = argv[++i];
        break;
      case "--to-uid":
        args.toUid = argv[++i];
        break;
      case "--dry-run":
        args.dryRun = true;
        break;
      case "--dry-run-id":
        args.dryRunId = argv[++i];
        break;
      case "--confirm":
        args.confirm = true;
        break;
      case "--id-token":
        args.idToken = argv[++i];
        break;
      case "--region":
        args.region = argv[++i];
        break;
      case "--help":
      case "-h":
        args.help = true;
        break;
      default:
        throw new Error(`Unknown argument: ${a}`);
    }
  }
  return args;
}

function usageAndExit(code) {
  console.log(
    "Usage: node call-transfer-ownership.mjs --project <id> [--region <region>] \\\n" +
      "         [--dry-run --from-uid <uid> --to-uid <uid>] \\\n" +
      "         [--confirm --dry-run-id <uuid>] \\\n" +
      "         [--id-token <jwt>]"
  );
  process.exit(code);
}

function validate(args) {
  if (args.help) usageAndExit(0);
  if (!args.project) {
    console.error("Error: --project is required");
    usageAndExit(1);
  }
  if (isProdProject(args.project)) {
    // Require the project id (not `yes`) so a persistent `export CONFIRM_PROD=...`
    // in one shell cannot silently auth every subsequent prod-targeted call.
    if (process.env.CONFIRM_PROD !== args.project) {
      console.error(
        `Error: prod project ${args.project} targeted. Set CONFIRM_PROD=${args.project} ` +
          `for the invocation (not via persistent \`export\`).`
      );
      process.exit(2);
    }
  } else if (!DEV_PROJECTS.has(args.project)) {
    console.error(
      `Error: project "${args.project}" is neither dev nor prod allowlisted. ` +
        `If this is a new project, update PROD_PROJECTS / DEV_PROJECTS in this script.`
    );
    process.exit(1);
  }
  const isDryRun = args.dryRun === true;
  const isConfirm = args.confirm === true;
  if (isDryRun === isConfirm) {
    console.error("Error: specify exactly one of --dry-run or --confirm");
    usageAndExit(1);
  }
  if (isDryRun && (!args.fromUid || !args.toUid)) {
    console.error("Error: --dry-run requires --from-uid and --to-uid");
    usageAndExit(1);
  }
  if (isConfirm && !args.dryRunId) {
    console.error("Error: --confirm requires --dry-run-id");
    usageAndExit(1);
  }
}

function fetchIdToken(args) {
  if (args.idToken) return args.idToken;
  // Fallback: gcloud print-identity-token. Note: this yields an OAuth2 ID token,
  // NOT a Firebase Auth user token. Callable functions expect the latter; the
  // operator is responsible for supplying --id-token when the caller is a real
  // Firebase Auth admin user. We emit a clear error if no id-token is given.
  throw new Error(
    "--id-token is required. Obtain a Firebase ID token for an admin user of " +
      "the target tenant and pass it via --id-token. Example via admin SDK: " +
      "`admin.auth().createCustomToken(adminUid, {tenantId, role: 'admin'})` " +
      "then exchange for an ID token on the client."
  );
}

function resolveFunctionUrl(project, region = "asia-northeast1") {
  return `https://${region}-${project}.cloudfunctions.net/transferOwnership`;
}

async function call(args) {
  const idToken = fetchIdToken(args);
  const url = resolveFunctionUrl(args.project, args.region);
  const body = args.dryRun
    ? { data: { dryRun: true, fromUid: args.fromUid, toUid: args.toUid } }
    : { data: { dryRunId: args.dryRunId } };
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${idToken}`,
    },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok) {
    console.error(`HTTP ${res.status}: ${text}`);
    process.exit(3);
  }
  const json = JSON.parse(text);
  // Callable response envelope: { result: ... } or { error: ... }
  if (json.error) {
    console.error("Callable error:", JSON.stringify(json.error, null, 2));
    process.exit(4);
  }
  console.log(JSON.stringify(json.result, null, 2));
}

async function main() {
  const args = parseArgs(process.argv);
  validate(args);
  try {
    await call(args);
  } catch (err) {
    console.error(`Error: ${err.message}`);
    process.exit(5);
  }
}

main();
