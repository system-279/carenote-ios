const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
const { readFileSync } = require("fs");
const { resolve } = require("path");

const PROJECT_ID = "carenote-test";
const TENANT_ID = "tenant-a";
const TENANT_ID_B = "tenant-b";

// CI と local で `firebase emulators:exec` が FIRESTORE_EMULATOR_HOST を注入するため、
// ハードコード値よりも env を優先する（ローカルでポート変更した場合の可搬性も確保）。
const EMULATOR_HOST_RAW = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
const [EMULATOR_HOST, EMULATOR_PORT] = EMULATOR_HOST_RAW.split(":");

function memberAuth(tenantId, role = "member") {
  return {
    uid: `${role}-${tenantId}`,
    token: { tenantId, role },
  };
}

function adminAuth(tenantId) {
  return memberAuth(tenantId, "admin");
}

let testEnv;

before(async () => {
  const rules = readFileSync(
    resolve(__dirname, "../../firestore.rules"),
    "utf8"
  );
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules, host: EMULATOR_HOST, port: Number(EMULATOR_PORT) },
  });
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

after(async () => {
  await testEnv.cleanup();
});

// ===== SEC-2: 未認証拒否テスト =====

describe("未認証ユーザー", () => {
  it("tenants を read できない", async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(db.collection("tenants").doc(TENANT_ID).get());
  });

  it("whitelist を read できない", async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      db
        .collection("tenants")
        .doc(TENANT_ID)
        .collection("whitelist")
        .doc("entry1")
        .get()
    );
  });

  it("templates を read できない", async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      db
        .collection("tenants")
        .doc(TENANT_ID)
        .collection("templates")
        .doc("t1")
        .get()
    );
  });

  it("clients を read できない", async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      db
        .collection("tenants")
        .doc(TENANT_ID)
        .collection("clients")
        .doc("c1")
        .get()
    );
  });

  it("recordings を read できない", async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      db
        .collection("tenants")
        .doc(TENANT_ID)
        .collection("recordings")
        .doc("r1")
        .get()
    );
  });

  it("recordings を write できない", async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      db
        .collection("tenants")
        .doc(TENANT_ID)
        .collection("recordings")
        .doc("r1")
        .set({ scene: "visit" })
    );
  });
});

// ===== SEC-3: テナント隔離テスト =====

describe("テナント隔離", () => {
  it("tenantA メンバーは tenantB の tenants ドキュメントを read できない", async () => {
    const db = testEnv.authenticatedContext(
      "member-a",
      memberAuth(TENANT_ID).token
    ).firestore();
    await assertFails(db.collection("tenants").doc(TENANT_ID_B).get());
  });

  it("tenantA メンバーは tenantB の clients を read できない", async () => {
    const db = testEnv.authenticatedContext(
      "member-a",
      memberAuth(TENANT_ID).token
    ).firestore();
    await assertFails(
      db
        .collection("tenants")
        .doc(TENANT_ID_B)
        .collection("clients")
        .doc("c1")
        .get()
    );
  });

  it("tenantA メンバーは tenantB の recordings を read できない", async () => {
    const db = testEnv.authenticatedContext(
      "member-a",
      memberAuth(TENANT_ID).token
    ).firestore();
    await assertFails(
      db
        .collection("tenants")
        .doc(TENANT_ID_B)
        .collection("recordings")
        .doc("r1")
        .get()
    );
  });

  it("tenantA メンバーは tenantB の recordings に write できない", async () => {
    const db = testEnv.authenticatedContext(
      "member-a",
      memberAuth(TENANT_ID).token
    ).firestore();
    await assertFails(
      db
        .collection("tenants")
        .doc(TENANT_ID_B)
        .collection("recordings")
        .doc("r1")
        .set({ scene: "visit" })
    );
  });

  it("tenantA メンバーは tenantB の templates を read できない", async () => {
    const db = testEnv.authenticatedContext(
      "member-a",
      memberAuth(TENANT_ID).token
    ).firestore();
    await assertFails(
      db
        .collection("tenants")
        .doc(TENANT_ID_B)
        .collection("templates")
        .doc("t1")
        .get()
    );
  });

  it("tenantA admin は tenantB の whitelist を read できない", async () => {
    const db = testEnv.authenticatedContext(
      "admin-a",
      adminAuth(TENANT_ID).token
    ).firestore();
    await assertFails(
      db
        .collection("tenants")
        .doc(TENANT_ID_B)
        .collection("whitelist")
        .doc("e1")
        .get()
    );
  });
});

// ===== SEC-4: admin権限境界テスト =====

describe("member権限の制限", () => {
  it("member は whitelist に create できない", async () => {
    const db = testEnv.authenticatedContext(
      "member-a",
      memberAuth(TENANT_ID).token
    ).firestore();
    await assertFails(
      db
        .collection("tenants")
        .doc(TENANT_ID)
        .collection("whitelist")
        .doc("new-entry")
        .set({ email: "new@example.com", role: "member" })
    );
  });

  it("member は whitelist を delete できない", async () => {
    // Setup: admin creates a whitelist entry
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .collection("tenants")
        .doc(TENANT_ID)
        .collection("whitelist")
        .doc("entry1")
        .set({ email: "user@example.com", role: "member" });
    });

    const db = testEnv.authenticatedContext(
      "member-a",
      memberAuth(TENANT_ID).token
    ).firestore();
    await assertFails(
      db
        .collection("tenants")
        .doc(TENANT_ID)
        .collection("whitelist")
        .doc("entry1")
        .delete()
    );
  });

  it("member は templates に create できない", async () => {
    const db = testEnv.authenticatedContext(
      "member-a",
      memberAuth(TENANT_ID).token
    ).firestore();
    await assertFails(
      db
        .collection("tenants")
        .doc(TENANT_ID)
        .collection("templates")
        .doc("new-t")
        .set({ name: "テスト", outputType: "transcription" })
    );
  });

  it("member は templates を delete できない", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .collection("tenants")
        .doc(TENANT_ID)
        .collection("templates")
        .doc("t1")
        .set({ name: "テスト", outputType: "transcription" });
    });

    const db = testEnv.authenticatedContext(
      "member-a",
      memberAuth(TENANT_ID).token
    ).firestore();
    await assertFails(
      db
        .collection("tenants")
        .doc(TENANT_ID)
        .collection("templates")
        .doc("t1")
        .delete()
    );
  });

  it("member は tenants ドキュメントに write できない", async () => {
    const db = testEnv.authenticatedContext(
      "member-a",
      memberAuth(TENANT_ID).token
    ).firestore();
    await assertFails(
      db
        .collection("tenants")
        .doc(TENANT_ID)
        .set({ allowedDomains: ["evil.com"] })
    );
  });
});

// ===== SEC-5: admin正常系 + whitelist update制限 =====

describe("admin権限の正常系", () => {
  it("admin は whitelist に create できる", async () => {
    const db = testEnv.authenticatedContext(
      "admin-a",
      adminAuth(TENANT_ID).token
    ).firestore();
    await assertSucceeds(
      db
        .collection("tenants")
        .doc(TENANT_ID)
        .collection("whitelist")
        .doc("new-entry")
        .set({ email: "new@example.com", role: "member" })
    );
  });

  it("admin は whitelist を delete できる", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .collection("tenants")
        .doc(TENANT_ID)
        .collection("whitelist")
        .doc("entry1")
        .set({ email: "user@example.com", role: "member" });
    });

    const db = testEnv.authenticatedContext(
      "admin-a",
      adminAuth(TENANT_ID).token
    ).firestore();
    await assertSucceeds(
      db
        .collection("tenants")
        .doc(TENANT_ID)
        .collection("whitelist")
        .doc("entry1")
        .delete()
    );
  });

  it("admin は whitelist の role のみ update できる", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .collection("tenants")
        .doc(TENANT_ID)
        .collection("whitelist")
        .doc("entry1")
        .set({ email: "user@example.com", role: "member" });
    });

    const db = testEnv.authenticatedContext(
      "admin-a",
      adminAuth(TENANT_ID).token
    ).firestore();
    await assertSucceeds(
      db
        .collection("tenants")
        .doc(TENANT_ID)
        .collection("whitelist")
        .doc("entry1")
        .update({ role: "admin" })
    );
  });

  it("admin は whitelist の email を update できない", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .collection("tenants")
        .doc(TENANT_ID)
        .collection("whitelist")
        .doc("entry1")
        .set({ email: "user@example.com", role: "member" });
    });

    const db = testEnv.authenticatedContext(
      "admin-a",
      adminAuth(TENANT_ID).token
    ).firestore();
    await assertFails(
      db
        .collection("tenants")
        .doc(TENANT_ID)
        .collection("whitelist")
        .doc("entry1")
        .update({ email: "hacked@example.com" })
    );
  });

  it("admin は templates を CRUD できる", async () => {
    const db = testEnv.authenticatedContext(
      "admin-a",
      adminAuth(TENANT_ID).token
    ).firestore();
    const ref = db
      .collection("tenants")
      .doc(TENANT_ID)
      .collection("templates")
      .doc("t1");

    await assertSucceeds(
      ref.set({ name: "テスト", outputType: "transcription" })
    );
    await assertSucceeds(ref.get());
    await assertSucceeds(ref.update({ name: "更新" }));
    await assertSucceeds(ref.delete());
  });
});

// ===== メンバー正常系 =====

describe("メンバー正常系", () => {
  it("member は自テナントの clients を read/write できる", async () => {
    const db = testEnv.authenticatedContext(
      "member-a",
      memberAuth(TENANT_ID).token
    ).firestore();
    const ref = db
      .collection("tenants")
      .doc(TENANT_ID)
      .collection("clients")
      .doc("c1");

    await assertSucceeds(ref.set({ name: "山田太郎", furigana: "やまだたろう" }));
    await assertSucceeds(ref.get());
  });

  it("member は自テナントの recordings を read できる (createdBy 問わず)", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .collection("tenants")
        .doc(TENANT_ID)
        .collection("recordings")
        .doc("r1")
        .set({ scene: "visit", clientName: "山田太郎", createdBy: "other-uid" });
    });

    const db = testEnv.authenticatedContext(
      "member-a",
      memberAuth(TENANT_ID).token
    ).firestore();
    await assertSucceeds(
      db.collection("tenants").doc(TENANT_ID).collection("recordings").doc("r1").get()
    );
  });

  it("member は自テナントの templates を read できる", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .collection("tenants")
        .doc(TENANT_ID)
        .collection("templates")
        .doc("t1")
        .set({ name: "テスト", outputType: "transcription" });
    });

    const db = testEnv.authenticatedContext(
      "member-a",
      memberAuth(TENANT_ID).token
    ).firestore();
    await assertSucceeds(
      db
        .collection("tenants")
        .doc(TENANT_ID)
        .collection("templates")
        .doc("t1")
        .get()
    );
  });

  it("member は自テナントの tenants ドキュメントを read できる", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .collection("tenants")
        .doc(TENANT_ID)
        .set({ allowedDomains: ["example.com"] });
    });

    const db = testEnv.authenticatedContext(
      "member-a",
      memberAuth(TENANT_ID).token
    ).firestore();
    await assertSucceeds(db.collection("tenants").doc(TENANT_ID).get());
  });
});

// ===== recordings 権限境界（Phase 0.5: Issue #100 対応） =====

describe("recordings 権限境界", () => {
  async function seedRecording(tenantId, recordingId, createdBy, extra = {}) {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .collection("tenants")
        .doc(tenantId)
        .collection("recordings")
        .doc(recordingId)
        .set({ scene: "visit", clientName: "山田太郎", createdBy, ...extra });
    });
  }

  describe("create", () => {
    it("member は createdBy に自分の uid をセットすれば create できる", async () => {
      const db = testEnv.authenticatedContext(
        "member-a",
        memberAuth(TENANT_ID).token
      ).firestore();
      await assertSucceeds(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-new")
          .set({ scene: "visit", clientName: "山田太郎", createdBy: "member-a" })
      );
    });

    it("member は createdBy に他人の uid を入れた create を拒否される (なりすまし防止)", async () => {
      const db = testEnv.authenticatedContext(
        "member-a",
        memberAuth(TENANT_ID).token
      ).firestore();
      await assertFails(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-impersonate")
          .set({ scene: "visit", clientName: "山田太郎", createdBy: "member-b" })
      );
    });

    // ADR-010: Build 35 互換性のため、createdBy 欠落 / 空文字も create を許容する。
    //          なりすまし防止は "他人の uid は deny" の条件で担保。
    it("member は createdBy 欠落の create を許可される (防御的、Build 35 互換)", async () => {
      const db = testEnv.authenticatedContext(
        "member-a",
        memberAuth(TENANT_ID).token
      ).firestore();
      await assertSucceeds(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-missing")
          .set({ scene: "visit", clientName: "山田太郎" })
      );
    });

    // Build 35 (iOS Unlisted 公開中) は FirestoreRecording.createdBy に空文字を
    // 保存する (#99/#101 参照)。Rules は空文字を許容して Build 35 互換性を担保。
    it("member は createdBy='' (空文字) の create を許可される (Build 35 互換)", async () => {
      const db = testEnv.authenticatedContext(
        "member-a",
        memberAuth(TENANT_ID).token
      ).firestore();
      await assertSucceeds(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-build35")
          .set({ scene: "visit", clientName: "山田太郎", createdBy: "" })
      );
    });
  });

  describe("update", () => {
    it("member は自分の録音を update できる (transcription 編集想定)", async () => {
      await seedRecording(TENANT_ID, "r-own", "member-a");
      const db = testEnv.authenticatedContext(
        "member-a",
        memberAuth(TENANT_ID).token
      ).firestore();
      await assertSucceeds(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-own")
          .update({ transcription: "編集済みテキスト" })
      );
    });

    it("member は他人の録音を update できない", async () => {
      await seedRecording(TENANT_ID, "r-other", "member-b");
      const db = testEnv.authenticatedContext(
        "member-a",
        memberAuth(TENANT_ID).token
      ).firestore();
      await assertFails(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-other")
          .update({ transcription: "改ざん" })
      );
    });

    it("admin は他人の録音を update できる", async () => {
      await seedRecording(TENANT_ID, "r-admin-fix", "member-a");
      const db = testEnv.authenticatedContext(
        "admin-a",
        adminAuth(TENANT_ID).token
      ).firestore();
      await assertSucceeds(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-admin-fix")
          .update({ transcription: "admin による補正" })
      );
    });

    it("member は自分の録音の createdBy を他人に書き換える update を拒否される", async () => {
      await seedRecording(TENANT_ID, "r-rewrite", "member-a");
      const db = testEnv.authenticatedContext(
        "member-a",
        memberAuth(TENANT_ID).token
      ).firestore();
      await assertFails(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-rewrite")
          .update({ createdBy: "member-b" })
      );
    });

    it("admin も client 経由の createdBy 変更 update は拒否される (admin SDK で bypass する設計)", async () => {
      await seedRecording(TENANT_ID, "r-admin-rewrite", "member-a");
      const db = testEnv.authenticatedContext(
        "admin-a",
        adminAuth(TENANT_ID).token
      ).firestore();
      await assertFails(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-admin-rewrite")
          .update({ createdBy: "member-b" })
      );
    });
  });

  describe("delete", () => {
    it("member は自分の録音を delete できる", async () => {
      await seedRecording(TENANT_ID, "r-own-del", "member-a");
      const db = testEnv.authenticatedContext(
        "member-a",
        memberAuth(TENANT_ID).token
      ).firestore();
      await assertSucceeds(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-own-del")
          .delete()
      );
    });

    it("member は他人の録音を delete できない", async () => {
      await seedRecording(TENANT_ID, "r-other-del", "member-b");
      const db = testEnv.authenticatedContext(
        "member-a",
        memberAuth(TENANT_ID).token
      ).firestore();
      await assertFails(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-other-del")
          .delete()
      );
    });

    it("admin は他人の録音を delete できる", async () => {
      await seedRecording(TENANT_ID, "r-admin-del", "member-a");
      const db = testEnv.authenticatedContext(
        "admin-a",
        adminAuth(TENANT_ID).token
      ).firestore();
      await assertSucceeds(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-admin-del")
          .delete()
      );
    });
  });

  // ADR-010: 既存 createdBy="" recording (Build 35 で作成された稼働中データ) の権限境界
  //   - member: author 判定 "" != uid で不成立 → admin のみ操作可 (設計意図)
  //   - admin: immutable 制約を守れば update / delete 可
  //   - createdBy を別値に書き換える update は admin 経路でも immutable 制約で deny
  //     (所有権書換は Admin SDK 経由の Callable でのみ実施 — #119 transferOwnership)
  describe('createdBy="" 既存レコード (Build 35 互換)', () => {
    it("member は createdBy='' の recording を update できない", async () => {
      await seedRecording(TENANT_ID, "r-legacy-upd-deny", "");
      const db = testEnv.authenticatedContext(
        "member-a",
        memberAuth(TENANT_ID).token
      ).firestore();
      await assertFails(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-legacy-upd-deny")
          .update({ transcription: "編集" })
      );
    });

    it("member は createdBy='' の recording を delete できない", async () => {
      await seedRecording(TENANT_ID, "r-legacy-del-deny", "");
      const db = testEnv.authenticatedContext(
        "member-a",
        memberAuth(TENANT_ID).token
      ).firestore();
      await assertFails(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-legacy-del-deny")
          .delete()
      );
    });

    it("admin は createdBy='' の recording を update できる (immutable 満たす transcription 更新)", async () => {
      await seedRecording(TENANT_ID, "r-legacy-upd-admin", "");
      const db = testEnv.authenticatedContext(
        "admin-a",
        adminAuth(TENANT_ID).token
      ).firestore();
      await assertSucceeds(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-legacy-upd-admin")
          .update({ transcription: "admin による補正" })
      );
    });

    it("admin も createdBy='' を別値に書き換える update は immutable 違反で拒否される", async () => {
      await seedRecording(TENANT_ID, "r-legacy-rewrite-admin", "");
      const db = testEnv.authenticatedContext(
        "admin-a",
        adminAuth(TENANT_ID).token
      ).firestore();
      await assertFails(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-legacy-rewrite-admin")
          .update({ createdBy: "admin-a" })
      );
    });

    it("admin は createdBy='' の recording を delete できる", async () => {
      await seedRecording(TENANT_ID, "r-legacy-del-admin", "");
      const db = testEnv.authenticatedContext(
        "admin-a",
        adminAuth(TENANT_ID).token
      ).firestore();
      await assertSucceeds(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-legacy-del-admin")
          .delete()
      );
    });
  });

  // ADR-010 AC14 強化 (Evaluator HIGH 指摘対応):
  // createdBy フィールドが欠落した recording (AC2 防御経路で write された理論上のデータ) に対する
  // 追加/削除 update を client 全経路で deny する。pre/post 双方で 'createdBy' の存在を等しく
  // 要求することで "片側のみ存在" パターン (client からの追加 / FieldValue.delete による削除) を
  // 遮断。実装: firestore.rules update ブロックの immutable 制約を双方向 in-check に強化。
  describe("createdBy 不在 recording (AC2 防御経路の保護)", () => {
    async function seedRecordingWithoutCreatedBy(tenantId, recordingId) {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context
          .firestore()
          .collection("tenants")
          .doc(tenantId)
          .collection("recordings")
          .doc(recordingId)
          .set({ scene: "visit", clientName: "山田太郎" });
      });
    }

    it("admin も createdBy 不在 recording に createdBy を追加する update は拒否される", async () => {
      await seedRecordingWithoutCreatedBy(TENANT_ID, "r-no-cb-add");
      const db = testEnv.authenticatedContext(
        "admin-a",
        adminAuth(TENANT_ID).token
      ).firestore();
      await assertFails(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-no-cb-add")
          .update({ createdBy: "admin-a" })
      );
    });

    it("admin は createdBy 不在 recording の他フィールド update は許可される (後方互換)", async () => {
      await seedRecordingWithoutCreatedBy(TENANT_ID, "r-no-cb-safe");
      const db = testEnv.authenticatedContext(
        "admin-a",
        adminAuth(TENANT_ID).token
      ).firestore();
      await assertSucceeds(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-no-cb-safe")
          .update({ transcription: "補正" })
      );
    });
  });
});

// ===== migrationLogs: Phase 1 transferOwnership の監査ログ =====

describe("migrationLogs 権限境界", () => {
  async function seedMigrationLog(tenantId, logId) {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .collection("tenants")
        .doc(tenantId)
        .collection("migrationLogs")
        .doc(logId)
        .set({
          executedAt: new Date(),
          actor: "admin-sdk",
          oldEmail: "old@279279.net",
          newEmail: "new@279279.net",
          affectedDocs: 42,
        });
    });
  }

  it("admin は migrationLogs を read できる", async () => {
    await seedMigrationLog(TENANT_ID, "log-1");
    const db = testEnv.authenticatedContext(
      "admin-a",
      adminAuth(TENANT_ID).token
    ).firestore();
    await assertSucceeds(
      db
        .collection("tenants")
        .doc(TENANT_ID)
        .collection("migrationLogs")
        .doc("log-1")
        .get()
    );
  });

  it("member は migrationLogs を read できない (旧メール等機微情報)", async () => {
    await seedMigrationLog(TENANT_ID, "log-2");
    const db = testEnv.authenticatedContext(
      "member-a",
      memberAuth(TENANT_ID).token
    ).firestore();
    await assertFails(
      db
        .collection("tenants")
        .doc(TENANT_ID)
        .collection("migrationLogs")
        .doc("log-2")
        .get()
    );
  });

  it("admin でもクライアントからは write できない (admin SDK 専用)", async () => {
    const db = testEnv.authenticatedContext(
      "admin-a",
      adminAuth(TENANT_ID).token
    ).firestore();
    await assertFails(
      db
        .collection("tenants")
        .doc(TENANT_ID)
        .collection("migrationLogs")
        .doc("log-new")
        .set({ actor: "admin-a" })
    );
  });

  it("member も当然 write できない", async () => {
    const db = testEnv.authenticatedContext(
      "member-a",
      memberAuth(TENANT_ID).token
    ).firestore();
    await assertFails(
      db
        .collection("tenants")
        .doc(TENANT_ID)
        .collection("migrationLogs")
        .doc("log-new")
        .set({ actor: "member-a" })
    );
  });

  it("他テナント admin は自テナント外の migrationLogs を read できない", async () => {
    await seedMigrationLog(TENANT_ID, "log-cross");
    const db = testEnv.authenticatedContext(
      "admin-b",
      adminAuth(TENANT_ID_B).token
    ).firestore();
    await assertFails(
      db
        .collection("tenants")
        .doc(TENANT_ID)
        .collection("migrationLogs")
        .doc("log-cross")
        .get()
    );
  });

  // AC-10 網羅: write: false が create 以外にも効いていることを保証
  // (将来 rules を allow create/update/delete に分解した場合の回帰検知)

  it("admin でも migrationLogs を update できない", async () => {
    await seedMigrationLog(TENANT_ID, "log-update");
    const db = testEnv.authenticatedContext(
      "admin-a",
      adminAuth(TENANT_ID).token
    ).firestore();
    await assertFails(
      db
        .collection("tenants")
        .doc(TENANT_ID)
        .collection("migrationLogs")
        .doc("log-update")
        .update({ affectedDocs: 999 })
    );
  });

  it("admin でも migrationLogs を delete できない", async () => {
    await seedMigrationLog(TENANT_ID, "log-delete");
    const db = testEnv.authenticatedContext(
      "admin-a",
      adminAuth(TENANT_ID).token
    ).firestore();
    await assertFails(
      db
        .collection("tenants")
        .doc(TENANT_ID)
        .collection("migrationLogs")
        .doc("log-delete")
        .delete()
    );
  });
});

// ===== Issue #116 follow-up: エッジケーステスト =====

describe("エッジケース (Issue #116 follow-up)", () => {
  async function seedRecording(tenantId, recordingId, createdBy) {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .collection("tenants")
        .doc(tenantId)
        .collection("recordings")
        .doc(recordingId)
        .set({ scene: "visit", clientName: "山田太郎", createdBy });
    });
  }

  // #116-1: Firebase SDK 経由で role が混入しない token に対する regression gate
  describe("role claim 欠落 token", () => {
    function noRoleToken(tenantId) {
      return { tenantId };
    }

    it("role 欠落 member は他人の録音を update できない (isAdmin 成立せず)", async () => {
      await seedRecording(TENANT_ID, "r-norole-upd", "member-b");
      const db = testEnv.authenticatedContext(
        "no-role-a",
        noRoleToken(TENANT_ID)
      ).firestore();
      await assertFails(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-norole-upd")
          .update({ transcription: "改ざん試行" })
      );
    });

    it("role 欠落 token で migrationLogs を read できない", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context
          .firestore()
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("migrationLogs")
          .doc("log-norole")
          .set({ actor: "admin-sdk" });
      });
      const db = testEnv.authenticatedContext(
        "no-role-a",
        noRoleToken(TENANT_ID)
      ).firestore();
      await assertFails(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("migrationLogs")
          .doc("log-norole")
          .get()
      );
    });
  });

  // #116-2: クライアントバグで null / 空文字が混入した際の二重防御
  describe("createdBy 不正値 create", () => {
    it("createdBy=null の create は拒否される", async () => {
      const db = testEnv.authenticatedContext(
        "member-a",
        memberAuth(TENANT_ID).token
      ).firestore();
      await assertFails(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-null")
          .set({ scene: "visit", clientName: "山田太郎", createdBy: null })
      );
    });

    // ADR-010: 空文字 createdBy は Build 35 の実 payload。以前は deny 前提だったが、
    //          稼働バイナリ (Build 35, App Store Unlisted 公開中) と互換を取るため許容。
    //          既存テストは #116 follow-up 時点 (Phase 0.5 前提) で記述されたが、
    //          Build 35 ロールバック後の恒久設計 (#100) では空文字は許容側に反転する。
    it("createdBy='' の create は許可される (Build 35 の実 payload、ADR-010)", async () => {
      const db = testEnv.authenticatedContext(
        "member-a",
        memberAuth(TENANT_ID).token
      ).firestore();
      await assertSucceeds(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-empty")
          .set({ scene: "visit", clientName: "山田太郎", createdBy: "" })
      );
    });
  });

  // #116-3: isAdmin が同一テナント内限定で機能することの明示
  describe("admin cross-tenant の recordings", () => {
    it("tenant-b admin は tenant-a の録音を update できない", async () => {
      await seedRecording(TENANT_ID, "r-cross-upd", "member-a");
      const db = testEnv.authenticatedContext(
        "admin-b",
        adminAuth(TENANT_ID_B).token
      ).firestore();
      await assertFails(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-cross-upd")
          .update({ transcription: "クロステナント改ざん" })
      );
    });

    it("tenant-b admin は tenant-a の録音を delete できない", async () => {
      await seedRecording(TENANT_ID, "r-cross-del", "member-a");
      const db = testEnv.authenticatedContext(
        "admin-b",
        adminAuth(TENANT_ID_B).token
      ).firestore();
      await assertFails(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-cross-del")
          .delete()
      );
    });
  });

  // #116-4: collection list クエリの権限（将来 allow get / allow list 分解時の regression gate）
  describe("recordings list クエリ", () => {
    async function seedTwoRecordings() {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const col = context
          .firestore()
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings");
        await col.doc("r-list-1").set({
          scene: "visit",
          clientName: "山田",
          createdBy: "member-a",
        });
        await col.doc("r-list-2").set({
          scene: "visit",
          clientName: "佐藤",
          createdBy: "member-b",
        });
      });
    }

    it("member は自テナントの recordings を list できる", async () => {
      await seedTwoRecordings();
      const db = testEnv.authenticatedContext(
        "member-a",
        memberAuth(TENANT_ID).token
      ).firestore();
      await assertSucceeds(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .get()
      );
    });

    it("他テナント member は recordings を list できない", async () => {
      await seedTwoRecordings();
      const db = testEnv.authenticatedContext(
        "member-b",
        memberAuth(TENANT_ID_B).token
      ).firestore();
      await assertFails(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .get()
      );
    });

    it("未認証は recordings を list できない", async () => {
      await seedTwoRecordings();
      const db = testEnv.unauthenticatedContext().firestore();
      await assertFails(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .get()
      );
    });
  });

  // #135-1: role 値バリエーション (rating 7)
  // 現状 rules は `role == 'admin'` 厳密一致で isAdmin を判定するが、
  // 将来 `role in ['admin']` や `role != 'member'` 等への書換 regression を予防する。
  describe("role 値バリエーション (issue #135-1)", () => {
    function roleToken(tenantId, role) {
      return { tenantId, role };
    }

    it("role='' では isAdmin 不成立（migrationLogs read 拒否）", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context
          .firestore()
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("migrationLogs")
          .doc("log-empty-role")
          .set({ actor: "admin-sdk" });
      });
      const db = testEnv.authenticatedContext(
        "empty-role-a",
        roleToken(TENANT_ID, "")
      ).firestore();
      await assertFails(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("migrationLogs")
          .doc("log-empty-role")
          .get()
      );
    });

    it("role='Admin' (大文字始まり) では isAdmin 不成立（他人の録音 update 拒否）", async () => {
      await seedRecording(TENANT_ID, "r-titlecase-role", "member-b");
      const db = testEnv.authenticatedContext(
        "titlecase-role-a",
        roleToken(TENANT_ID, "Admin")
      ).firestore();
      await assertFails(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-titlecase-role")
          .update({ transcription: "大文字ロール試行" })
      );
    });

    it("role=0 (数値) では isAdmin 不成立（他人の録音 delete 拒否）", async () => {
      await seedRecording(TENANT_ID, "r-numeric-role", "member-b");
      const db = testEnv.authenticatedContext(
        "numeric-role-a",
        roleToken(TENANT_ID, 0)
      ).firestore();
      await assertFails(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-numeric-role")
          .delete()
      );
    });

    it("role=null では isAdmin 不成立（whitelist create 拒否）", async () => {
      const db = testEnv.authenticatedContext(
        "null-role-a",
        roleToken(TENANT_ID, null)
      ).firestore();
      await assertFails(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("whitelist")
          .doc("w-nullrole")
          .set({ email: "x@example.com", role: "member" })
      );
    });
  });

  // #135-2: createdBy 書換防止の明示 (rating 7)
  // update の不変制約 `request.resource.data.createdBy == resource.data.createdBy` が
  // 所有権移管シナリオの各境界で機能することを明示する。
  describe("createdBy 書換防止の境界 (issue #135-2)", () => {
    it("admin が自分の uid に createdBy を書き換える update は拒否される", async () => {
      await seedRecording(TENANT_ID, "r-admin-self-rewrite", "member-a");
      const db = testEnv.authenticatedContext(
        "admin-a",
        adminAuth(TENANT_ID).token
      ).firestore();
      await assertFails(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-admin-self-rewrite")
          .update({ createdBy: "admin-a" })
      );
    });

    it("member が他人の uid から別の他人の uid へ createdBy を書き換える update は拒否される", async () => {
      await seedRecording(TENANT_ID, "r-third-party-rewrite", "member-b");
      const db = testEnv.authenticatedContext(
        "member-a",
        memberAuth(TENANT_ID).token
      ).firestore();
      await assertFails(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-third-party-rewrite")
          .update({ createdBy: "member-c" })
      );
    });
  });

  // #135-3: createdBy 非 string 型 (rating 6)
  // クライアント SDK の型崩れ regression を拾う。現状 rules は
  // `request.resource.data.createdBy == request.auth.uid` (string) との比較で拒否する。
  describe("createdBy 非 string 型 create (issue #135-3)", () => {
    it("createdBy={} の create は拒否される", async () => {
      const db = testEnv.authenticatedContext(
        "member-a",
        memberAuth(TENANT_ID).token
      ).firestore();
      await assertFails(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-obj-createdby")
          .set({ scene: "visit", clientName: "山田太郎", createdBy: {} })
      );
    });

    it("createdBy=123 (数値) の create は拒否される", async () => {
      const db = testEnv.authenticatedContext(
        "member-a",
        memberAuth(TENANT_ID).token
      ).firestore();
      await assertFails(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-num-createdby")
          .set({ scene: "visit", clientName: "山田太郎", createdBy: 123 })
      );
    });

    it("createdBy=[] (配列) の create は拒否される", async () => {
      const db = testEnv.authenticatedContext(
        "member-a",
        memberAuth(TENANT_ID).token
      ).firestore();
      await assertFails(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-arr-createdby")
          .set({ scene: "visit", clientName: "山田太郎", createdBy: [] })
      );
    });
  });

  // #116-5: admin 間の相互干渉シナリオの明示
  describe("admin 間の recordings 操作", () => {
    it("admin-1 は admin-2 の録音を update できる", async () => {
      await seedRecording(TENANT_ID, "r-a1a2-upd", "admin-creator");
      const db = testEnv.authenticatedContext(
        "admin-writer",
        adminAuth(TENANT_ID).token
      ).firestore();
      await assertSucceeds(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-a1a2-upd")
          .update({ transcription: "admin 間補正" })
      );
    });

    it("admin-1 は admin-2 の録音を delete できる", async () => {
      await seedRecording(TENANT_ID, "r-a1a2-del", "admin-creator");
      const db = testEnv.authenticatedContext(
        "admin-writer",
        adminAuth(TENANT_ID).token
      ).firestore();
      await assertSucceeds(
        db
          .collection("tenants")
          .doc(TENANT_ID)
          .collection("recordings")
          .doc("r-a1a2-del")
          .delete()
      );
    });
  });
});
