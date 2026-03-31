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
    firestore: { rules, host: "127.0.0.1", port: 8080 },
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

  it("member は自テナントの recordings を read/write できる", async () => {
    const db = testEnv.authenticatedContext(
      "member-a",
      memberAuth(TENANT_ID).token
    ).firestore();
    const ref = db
      .collection("tenants")
      .doc(TENANT_ID)
      .collection("recordings")
      .doc("r1");

    await assertSucceeds(ref.set({ scene: "visit", clientName: "山田太郎" }));
    await assertSucceeds(ref.get());
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
