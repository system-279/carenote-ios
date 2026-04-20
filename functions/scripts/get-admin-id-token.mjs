#!/usr/bin/env node
// Usage: node functions/scripts/get-admin-id-token.mjs \
//          --project <id> --uid <admin-uid> --tenant-id <tenantId> [--role admin] [--api-key <key>]
//
// Emits a Firebase Auth ID token carrying the admin claims required by the
// `transferOwnership` Callable Function. Intended for dev/prod RUNBOOK use
// (方式B smoke test / one-off prod ops). Not for application use.
//
// Pipeline:
//   1. Use Firebase Admin SDK (ADC) to upsert the target user and set
//      custom claims { tenantId, role }.
//   2. Mint a Firebase custom token for that uid.
//   3. Exchange the custom token at Identity Toolkit
//      `accounts:signInWithCustomToken` using the project's public Web API
//      Key. The returned `idToken` is valid for ~1 hour.
//
// Authentication:
//   - Admin SDK credentials: `gcloud auth application-default login` (ADC).
//     No service account key file is mounted.
//   - API Key: the Firebase Web API Key is public (embedded in mobile app
//     binaries). It can be supplied via --api-key or auto-resolved from
//     CareNote/Firebase/<env>/GoogleService-Info.plist.
//
// Safety:
//   - On prod projects, CONFIRM_PROD=yes is required (guardrail against
//     accidental prod-targeted token issuance).
//   - Ephemeral admin uid pattern is encouraged: pass a uid like
//     "transferOp-<initials>-<YYYYMMDD>" and delete it after the op.
//
// Exit codes:
//   0 — idToken printed on stdout
//   1 — argument / config error
//   2 — prod target without CONFIRM_PROD=yes
//   3 — Admin SDK or Identity Toolkit call failed

import { initializeApp, applicationDefault } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { readFileSync } from "node:fs";
import path from "node:path";
import process from "node:process";

// Explicit allowlist beats substring matching for the prod guard.
// A substring check like `includes("prod")` would miss future prod names
// that don't contain "prod" (e.g. "carenote-live-279") and falsely flag
// pre-prod sandboxes (e.g. "carenote-preprod-test").
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
      case "--project": args.project = argv[++i]; break;
      case "--uid": args.uid = argv[++i]; break;
      case "--tenant-id": args.tenantId = argv[++i]; break;
      case "--role": args.role = argv[++i]; break;
      case "--api-key": args.apiKey = argv[++i]; break;
      case "--help":
      case "-h": args.help = true; break;
      default: throw new Error(`Unknown argument: ${a}`);
    }
  }
  return args;
}

function usageAndExit(code) {
  console.error(
    "Usage: node get-admin-id-token.mjs \\\n" +
      "         --project <id> --uid <admin-uid> --tenant-id <tenantId> \\\n" +
      "         [--role admin] [--api-key <public-api-key>]\n\n" +
      "Env:\n" +
      "  CONFIRM_PROD=yes  required when --project matches 'prod'\n" +
      "  GOOGLE_APPLICATION_CREDENTIALS  optional; ADC preferred"
  );
  process.exit(code);
}

function validate(args) {
  if (args.help) usageAndExit(0);
  if (!args.project || !args.uid || !args.tenantId) {
    console.error("Error: --project, --uid, --tenant-id are required");
    usageAndExit(1);
  }
  if (isProdProject(args.project)) {
    // Require the project id as the confirmation value to prevent
    // accidental `export CONFIRM_PROD=yes` in a long-lived shell from
    // bypassing every subsequent prod-targeted invocation.
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
  args.role = args.role || "admin";
}

function resolveApiKey(args) {
  if (args.apiKey) return args.apiKey;
  // Auto-resolve from the appropriate GoogleService-Info.plist by project id.
  // Dev and prod plists live under CareNote/Firebase/{Dev,Prod}.
  const env = isProdProject(args.project) ? "Prod" : "Dev";
  const plistPath = path.resolve(
    process.cwd(),
    `CareNote/Firebase/${env}/GoogleService-Info.plist`
  );
  let plist;
  try {
    plist = readFileSync(plistPath, "utf8");
  } catch (err) {
    throw new Error(
      `--api-key omitted and ${plistPath} is not readable (${err.message}). ` +
        `Pass --api-key explicitly or run from repo root.`
    );
  }
  const match = plist.match(/<key>API_KEY<\/key>\s*<string>([^<]+)<\/string>/);
  if (!match) {
    throw new Error(
      `Could not find API_KEY in ${plistPath}. Pass --api-key explicitly.`
    );
  }
  return match[1];
}

async function mintIdToken(args) {
  initializeApp({ credential: applicationDefault(), projectId: args.project });
  const auth = getAuth();

  try {
    await auth.getUser(args.uid);
  } catch (err) {
    if (err.code === "auth/user-not-found") {
      console.error(`  creating Auth user: ${args.uid}`);
      await auth.createUser({ uid: args.uid });
    } else {
      throw err;
    }
  }

  await auth.setCustomUserClaims(args.uid, {
    tenantId: args.tenantId,
    role: args.role,
  });
  console.error(
    `  set claims { tenantId: "${args.tenantId}", role: "${args.role}" } on ${args.uid}`
  );

  const customToken = await auth.createCustomToken(args.uid, {
    tenantId: args.tenantId,
    role: args.role,
  });

  const apiKey = resolveApiKey(args);
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${apiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ token: customToken, returnSecureToken: true }),
    }
  );
  const text = await res.text();
  // Never echo raw response bodies into error messages — on 200 the body
  // carries the live idToken, and even partial/truncated bodies may contain
  // JWT fragments. Only surface structured error codes/messages.
  if (!res.ok) {
    let code = "";
    let message = "";
    try {
      const parsed = JSON.parse(text);
      code = parsed?.error?.status || parsed?.error?.code || "";
      message = parsed?.error?.message || "";
    } catch {
      // body was not JSON; do not echo it (could still contain secrets)
    }
    const safeSuffix = code || message
      ? `${code}${code && message ? ": " : ""}${message}`
      : "(response body withheld)";
    throw new Error(`signInWithCustomToken HTTP ${res.status}: ${safeSuffix}`);
  }
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    // Do not include any portion of the body; on 200 it contains the idToken.
    throw new Error("signInWithCustomToken returned non-JSON on 200 status");
  }
  if (!json.idToken) {
    // Only surface structure, never raw payload.
    const keys = Object.keys(json || {}).join(",");
    throw new Error(`signInWithCustomToken response missing idToken (keys: ${keys})`);
  }
  return json.idToken;
}

async function main() {
  const args = parseArgs(process.argv);
  validate(args);
  try {
    const idToken = await mintIdToken(args);
    // Write a trailing newline so `$(...)` substitution in shells works
    // without producing warnings.
    process.stdout.write(idToken + "\n");
  } catch (err) {
    // Deliberately do NOT print err.stack — firebase-admin error messages
    // and stack traces have historically surfaced custom tokens, and this
    // script is the one place that generates credentials. Users needing
    // deeper traces should modify the script locally rather than enable a
    // DEBUG env flag that could leak secrets into terminals/CI logs.
    console.error(`Error: ${err.message}`);
    process.exit(3);
  }
}

main();
