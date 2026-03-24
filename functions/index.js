const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { beforeUserSignedIn } = require("firebase-functions/v2/identity");
const { logger } = require("firebase-functions");

initializeApp();

/**
 * Auth blocking function: 毎回サインイン時にホワイトリストを照合し、
 * tenantId と role を custom claims に設定する。
 *
 * - ホワイトリスト登録済み → tenantId + role を claims に設定
 * - ホワイトリスト未登録 → サインインを拒否
 * - ロール変更も次回サインインで自動反映
 */
exports.beforeSignIn = beforeUserSignedIn(
  { region: "asia-northeast1" },
  async (event) => {
    const email = (event.data.email || "").toLowerCase().trim();

    if (!email) {
      throw new Error("メールアドレスが取得できません。");
    }

    logger.info(`beforeSignIn: checking whitelist for ${email}`);

    const db = getFirestore();

    const emailDomain = email.split("@")[1] || "";

    // 全テナントの whitelist + allowedDomains からメールを検索
    const tenantsSnapshot = await db.collection("tenants").get();

    for (const tenantDoc of tenantsSnapshot.docs) {
      const tenantId = tenantDoc.id;

      // 1. whitelist でメール完全一致を検索
      const whitelistSnapshot = await db
        .collection("tenants")
        .doc(tenantId)
        .collection("whitelist")
        .where("email", "==", email)
        .limit(1)
        .get();

      if (!whitelistSnapshot.empty) {
        const entry = whitelistSnapshot.docs[0].data();
        const role = entry.role || "user";

        logger.info(
          `beforeSignIn: ${email} found in tenant ${tenantId} whitelist with role ${role}`
        );

        return {
          customClaims: {
            tenantId: tenantId,
            role: role,
          },
        };
      }

      // 2. allowedDomains でドメイン一致を検索
      const tenantData = tenantDoc.data() || {};
      const allowedDomains = tenantData.allowedDomains || [];

      if (
        emailDomain &&
        allowedDomains.some(
          (d) => d.toLowerCase().trim() === emailDomain
        )
      ) {
        logger.info(
          `beforeSignIn: ${email} matched domain ${emailDomain} in tenant ${tenantId}`
        );

        return {
          customClaims: {
            tenantId: tenantId,
            role: "user",
          },
        };
      }
    }

    // ホワイトリスト・ドメインいずれも不一致 → サインイン拒否
    logger.warn(`beforeSignIn: ${email} not found in any whitelist or allowed domain`);
    throw new Error(
      "このアカウントは許可されていません。管理者にお問い合わせください。"
    );
  }
);
