const { beforeUserSignedIn } = require("firebase-functions/v2/identity");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

initializeApp();

exports.beforeSignIn = beforeUserSignedIn(
  { region: "asia-northeast1" },
  async (event) => {
    const email = (event.data.email || "").toLowerCase().trim();
    if (!email) {
      throw new Error("メールアドレスが取得できません。");
    }

    const db = getFirestore();
    const tenantsSnapshot = await db.collection("tenants").get();

    for (const tenantDoc of tenantsSnapshot.docs) {
      const tenantId = tenantDoc.id;

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

    // No match: reject sign-in
    throw new Error("このアカウントは許可されていません。管理者にお問い合わせください。");
  }
);
