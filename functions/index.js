const { beforeUserSignedIn } = require("firebase-functions/v2/identity");
const { HttpsError } = require("firebase-functions/v2/identity");
const { onCall, HttpsError: CallableHttpsError } = require("firebase-functions/v2/https");
const { onDocumentDeleted } = require("firebase-functions/v2/firestore");
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
//
// Auth deletion runs even if Firestore/Storage cleanup partially fails, so the
// identity is always removed (preferred for App Store compliance). Orphan blobs
// can be reaped by Storage lifecycle rules.
//
// NOTE: doc.ref.delete() の発行で `onRecordingDeleted` trigger が発火し、同じ
// audioStoragePath に対して二重削除が走るが、Storage delete は `ignoreNotFound: true`
// なので冪等。Issue #192。
exports.deleteAccount = onCall(
  { region: REGION, timeoutSeconds: 540 },
  async (request) => {
    const uid = request.auth?.uid;
    const tenantId = request.auth?.token?.tenantId;
    if (!uid) {
      throw new CallableHttpsError("unauthenticated", "ログインが必要です。");
    }
    if (!tenantId) {
      console.error("[deleteAccount] missing tenantId claim", { uid });
      throw new CallableHttpsError(
        "failed-precondition",
        "セッション情報が不完全です。一度ログアウトしてから再度お試しください。"
      );
    }

    const db = getFirestore();
    let recordingsSnap;
    try {
      recordingsSnap = await db
        .collection("tenants")
        .doc(tenantId)
        .collection("recordings")
        .where("createdBy", "==", uid)
        .get();
    } catch (err) {
      // Query failure (permissions, transient, missing index) must not block
      // Auth user deletion. App Store 5.1.1(v) requires identity removal even
      // when data cleanup fails; orphan recordings can be reaped by support
      // tooling. Proceed with empty snapshot.
      console.error("[deleteAccount] recordings query failed, proceeding to auth-delete", {
        uid, tenantId, code: err.code, message: err.message,
      });
      recordingsSnap = { docs: [] };
    }

    const cleanupPromises = [];
    for (const doc of recordingsSnap.docs) {
      const data = doc.data() || {};
      const gs = parseGsUri(data.audioStoragePath);
      if (gs) {
        cleanupPromises.push(
          getStorage().bucket(gs.bucket).file(gs.object).delete({ ignoreNotFound: true })
        );
      } else if (data.audioStoragePath) {
        // Issue #193 review: writer-side のバグ / data corruption の可能性があるため
        // error level (warn は「気にする必要のない」シグナル、これは actionable)。
        console.error("[deleteAccount] unparseable audioStoragePath", {
          uid, docId: doc.id, audioStoragePath: data.audioStoragePath,
        });
      }
      cleanupPromises.push(doc.ref.delete());
    }
    const results = await Promise.allSettled(cleanupPromises);
    const failures = results.filter((r) => r.status === "rejected");
    if (failures.length > 0) {
      console.error("[deleteAccount] partial cleanup failures", {
        uid, tenantId,
        failureCount: failures.length,
        totalCount: results.length,
        reasons: failures.map((f) => ({
          code: f.reason?.code,
          message: f.reason?.message,
        })),
      });
      // Continue: identity removal takes precedence over orphan cleanup.
    }

    try {
      await getAuth().deleteUser(uid);
    } catch (err) {
      console.error("[deleteAccount] auth.deleteUser failed", {
        uid, code: err.code, message: err.message,
      });
      if (err.code === "auth/user-not-found") {
        return { success: true, alreadyDeleted: true };
      }
      if (err.code === "auth/requires-recent-login") {
        throw new CallableHttpsError(
          "failed-precondition",
          "セキュリティのため再ログインが必要です。一度ログアウトしてから再度お試しください。",
          { requiresReauth: true }
        );
      }
      throw new CallableHttpsError(
        "internal",
        "アカウント削除に失敗しました。時間をおいて再度お試しください。",
        { phase: "auth-delete" }
      );
    }
    return { success: true };
  }
);

// Phase 1 transferOwnership (Issue #110): admin が旧 uid → 新 uid にテナント内
// recordings / templates / whitelist を書換える Callable Function。
// 詳細は functions/src/transferOwnership.js および ADR-008 参照。
exports.transferOwnership = require("./src/transferOwnership").transferOwnership;

// Issue #192: 録音 doc が削除されたら関連の Cloud Storage audio object も削除する
// Firestore trigger。iOS swipe delete (PR #191 / Issue #182) では Firestore doc のみ
// 消えるため、この trigger がないと Storage が orphan blob で圧迫されていく。
//
// 既存の `deleteAccount` Callable も同じ Storage delete を呼ぶが、`ignoreNotFound: true`
// で冪等。trigger 発火時に既に object が消えていても no-op で完走する。
//
// trigger 内では throw しない: trigger が throw すると Firebase は exponential backoff で
// retry し続け、永久ループ + log spam になる。Storage delete 失敗は orphan として記録し、
// `functions/scripts/delete-empty-createdby.mjs` 系の手動 cleanup スクリプトで回収する。
//
// handler を別関数で定義 + `_handleRecordingDeleted` として named export しているのは
// `firebase-functions-test` の `makeDocumentSnapshot` が他テストの `getFirestore` mock と
// 干渉するため、test では event 互換オブジェクトを直接渡して handler を call する設計のため。
async function handleRecordingDeleted(event) {
  const tenantId = event.params.tenantId;
  const recordingId = event.params.recordingId;
  const data = event.data?.data() || {};
  const audioStoragePath = data.audioStoragePath;

  if (!audioStoragePath) {
    console.info("[onRecordingDeleted] no audioStoragePath, skipping", {
      tenantId,
      recordingId,
    });
    return;
  }

  const gs = parseGsUri(audioStoragePath);
  if (!gs) {
    // writer-side のバグ / data corruption が原因。orphan を作る silent failure に
    // しないよう error level で記録 (warn は「気にする必要のない」シグナル)。
    console.error("[onRecordingDeleted] unparseable audioStoragePath, skipping", {
      tenantId,
      recordingId,
      audioStoragePath,
    });
    return;
  }

  try {
    await getStorage()
      .bucket(gs.bucket)
      .file(gs.object)
      .delete({ ignoreNotFound: true });
    console.info("[onRecordingDeleted] storage object deleted", {
      tenantId,
      recordingId,
      bucket: gs.bucket,
      object: gs.object,
    });
  } catch (err) {
    // throw すると trigger が retry backoff に入る。orphan は許容して log のみ残す。
    console.error("[onRecordingDeleted] storage delete failed (orphan possible)", {
      tenantId,
      recordingId,
      bucket: gs.bucket,
      object: gs.object,
      code: err.code,
      message: err.message,
    });
  }
}

exports.onRecordingDeleted = onDocumentDeleted(
  {
    region: REGION,
    document: "tenants/{tenantId}/recordings/{recordingId}",
  },
  handleRecordingDeleted
);

// Test 用: handler を直接呼べるよう named export する（v2 trigger は wrap 経由だと
// 他テストの admin SDK mock と干渉するため）。production は `exports.onRecordingDeleted`
// 経由で発火するので影響なし。
//
// Firebase は `onCall` / `onDocumentDeleted` などで wrap された `CloudFunction` オブジェクト
// のみを trigger / function として登録するため、plain な async function である
// `_handleRecordingDeleted` は `firebase deploy` の対象外（デプロイ後の Cloud Console にも
// 表示されない）。テスト目的の export であり攻撃面の追加にはならない。
exports._handleRecordingDeleted = handleRecordingDeleted;
