const { beforeUserSignedIn } = require("firebase-functions/v2/identity");
const { HttpsError } = require("firebase-functions/v2/identity");
const { onCall, HttpsError: CallableHttpsError } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const { getStorage } = require("firebase-admin/storage");

initializeApp();

const REGION = "asia-northeast1";

// Guest tenant used for users who sign in with providers that do not match
// any whitelist / allowedDomains (currently: Apple Sign-In only).
// Enables anyone to explore the app with isolated data.
const GUEST_TENANT_ID = "demo-guest";

function isAppleProvider(event) {
  if (event.credential?.providerId === "apple.com") return true;
  const providerData = event.data?.providerData || [];
  return providerData.some((p) => p?.providerId === "apple.com");
}

exports.beforeSignIn = beforeUserSignedIn(
  { region: REGION },
  async (event) => {
    const email = (event.data.email || "").toLowerCase().trim();
    if (!email) {
      throw new HttpsError("invalid-argument", "メールアドレスが取得できません。");
    }

    const db = getFirestore();
    const tenantsSnapshot = await db.collection("tenants").get();

    for (const tenantDoc of tenantsSnapshot.docs) {
      const tenantId = tenantDoc.id;
      if (tenantId === GUEST_TENANT_ID) continue;

      // 1. Whitelist: email exact match
      const whitelistSnapshot = await db
        .collection("tenants")
        .doc(tenantId)
        .collection("whitelist")
        .where("email", "==", email)
        .limit(1)
        .get();

      if (!whitelistSnapshot.empty) {
        const entry = whitelistSnapshot.docs[0].data();
        const role = entry.role || "member";
        return {
          customClaims: {
            tenantId: tenantId,
            role: role,
          },
        };
      }

      // 2. Allowed domains: domain match
      const tenantData = tenantDoc.data() || {};
      const allowedDomains = tenantData.allowedDomains || [];
      const emailDomain = email.split("@")[1] || "";

      if (
        allowedDomains.some(
          (d) => d.toLowerCase().trim() === emailDomain
        )
      ) {
        return {
          customClaims: {
            tenantId: tenantId,
            role: "member",
          },
        };
      }
    }

    // No match: Apple Sign-In users fall into the guest tenant so they can
    // evaluate the app. Other providers remain invitation-only.
    if (isAppleProvider(event)) {
      return {
        customClaims: {
          tenantId: GUEST_TENANT_ID,
          role: "member",
        },
      };
    }

    throw new HttpsError("permission-denied", "このアカウントは許可されていません。管理者にお問い合わせください。");
  }
);

// Parses a gs:// URI into (bucket, object) pair. Returns null if malformed.
function parseGsUri(uri) {
  if (typeof uri !== "string") return null;
  const match = uri.match(/^gs:\/\/([^/]+)\/(.+)$/);
  if (!match) return null;
  return { bucket: match[1], object: match[2] };
}

// Allows a signed-in user to delete their own account (App Store Guideline 5.1.1(v)).
// Deletes:
//   1. Recordings in the caller's tenant where createdBy == uid
//   2. Associated audio files in Cloud Storage
//   3. The Firebase Auth user record
// Tenant-shared data (clients, tenant-wide templates) is NOT deleted because
// it is not considered personal data for this user.
exports.deleteAccount = onCall(
  { region: REGION },
  async (request) => {
    const uid = request.auth?.uid;
    const tenantId = request.auth?.token?.tenantId;
    if (!uid) {
      throw new CallableHttpsError("unauthenticated", "ログインが必要です。");
    }

    if (tenantId) {
      const db = getFirestore();
      const recordingsSnap = await db
        .collection("tenants")
        .doc(tenantId)
        .collection("recordings")
        .where("createdBy", "==", uid)
        .get();

      const cleanupPromises = [];
      for (const doc of recordingsSnap.docs) {
        const data = doc.data() || {};
        const gs = parseGsUri(data.audioStoragePath);
        if (gs) {
          cleanupPromises.push(
            getStorage().bucket(gs.bucket).file(gs.object).delete({ ignoreNotFound: true })
          );
        }
        cleanupPromises.push(doc.ref.delete());
      }
      await Promise.all(cleanupPromises);
    }

    try {
      await getAuth().deleteUser(uid);
    } catch (err) {
      // Treat already-deleted user as success to keep the operation idempotent.
      if (err.code === "auth/user-not-found") {
        return { success: true };
      }
      throw new CallableHttpsError("internal", "アカウント削除に失敗しました。", err.message);
    }
    return { success: true };
  }
);
