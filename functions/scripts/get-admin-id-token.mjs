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
  if (args.project.includes("prod") && process.env.CONFIRM_PROD !== "yes") {
    console.error(
      "Error: prod project targeted but CONFIRM_PROD=yes not set. Refusing."
    );
    process.exit(2);
  }
  args.role = args.role || "admin";
}

function resolveApiKey(args) {
  if (args.apiKey) return args.apiKey;
  // Auto-resolve from the appropriate GoogleService-Info.plist by project id.
  // Dev and prod plists live under CareNote/Firebase/{Dev,Prod}.
  const env = args.project.includes("prod") ? "Prod" : "Dev";
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
  if (!res.ok) {
    throw new Error(`signInWithCustomToken HTTP ${res.status}: ${text}`);
  }
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    throw new Error(`signInWithCustomToken returned non-JSON: ${text.slice(0, 200)}`);
  }
  if (!json.idToken) {
    throw new Error(`signInWithCustomToken response missing idToken: ${text.slice(0, 200)}`);
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
    console.error(`Error: ${err.message}`);
    if (err.stack && process.env.DEBUG) console.error(err.stack);
    process.exit(3);
  }
}

main();
