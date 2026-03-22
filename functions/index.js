const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore } = require("firebase-admin/firestore");
const { beforeUserCreated } = require("firebase-functions/v2/identity");
const { logger } = require("firebase-functions");

initializeApp();

/**
 * Auth blocking function: 新規ユーザー作成前にホワイトリストを照合し、
 * tenantId と role を custom claims に自動設定する。
 *
 * ホワイトリスト未登録のメールはサインインを拒否する。
 */
exports.beforeCreate = beforeUserCreated(
  { region: "asia-northeast1" },
  async (event) => {
    const email = (event.data.email || "").toLowerCase().trim();

    if (!email) {
      throw new Error("メールアドレスが取得できません。");
    }

    logger.info(`beforeCreate: checking whitelist for ${email}`);

    const db = getFirestore();

    // 全テナントの whitelist からメールを検索
    const tenantsSnapshot = await db.collection("tenants").get();

    for (const tenantDoc of tenantsSnapshot.docs) {
      const tenantId = tenantDoc.id;
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
          `beforeCreate: ${email} found in tenant ${tenantId} with role ${role}`
        );

        // custom claims を設定
        return {
          customClaims: {
            tenantId: tenantId,
            role: role,
          },
        };
      }
    }

    // ホワイトリスト未登録 → サインイン拒否
    logger.warn(`beforeCreate: ${email} not found in any whitelist`);
    throw new Error(
      "このアカウントは許可されていません。管理者にお問い合わせください。"
    );
  }
);
