const assert = require("assert");
const admin = require("firebase-admin");
const functionsTest = require("firebase-functions-test");

// Initialize firebase-functions-test in offline mode
const test = functionsTest();

// Mock Firestore
let mockFirestoreData = {};

// Helper: set up mock tenant data
function setupTenant(tenantId, { whitelist = [], allowedDomains = [] } = {}) {
  mockFirestoreData[`tenants/${tenantId}`] = { allowedDomains };
  whitelist.forEach((entry, i) => {
    mockFirestoreData[`tenants/${tenantId}/whitelist/${i}`] = entry;
  });
}

function resetMockData() {
  mockFirestoreData = {};
}

// Mock admin.firestore
const originalGetFirestore = admin.firestore;
let firestoreMock;

before(() => {
  // Create Firestore mock that returns data from mockFirestoreData
  firestoreMock = () => ({
    collection: (path) => createCollectionRef(path),
  });

  function createCollectionRef(path) {
    return {
      get: async () => {
        // Return all docs matching this collection path
        const docs = Object.entries(mockFirestoreData)
          .filter(([key]) => {
            const parts = key.split("/");
            const collParts = path.split("/");
            // For top-level: "tenants" matches "tenants/xxx"
            if (collParts.length === 1) {
              return parts.length === 2 && parts[0] === collParts[0];
            }
            return false;
          })
          .map(([key, data]) => ({
            id: key.split("/").pop(),
            data: () => data,
          }));
        return { docs };
      },
      doc: (id) => createDocRef(`${path}/${id}`),
      where: (field, op, value) => ({
        limit: () => ({
          get: async () => {
            const docs = Object.entries(mockFirestoreData)
              .filter(([key, data]) => {
                return key.startsWith(path + "/") && data[field] === value;
              })
              .slice(0, 1)
              .map(([key, data]) => ({
                id: key.split("/").pop(),
                data: () => data,
              }));
            return { empty: docs.length === 0, docs };
          },
        }),
      }),
    };
  }

  function createDocRef(path) {
    return {
      get: async () => ({
        exists: path in mockFirestoreData,
        data: () => mockFirestoreData[path] || {},
      }),
      collection: (subPath) => createCollectionRef(`${path}/${subPath}`),
    };
  }

  // Monkey-patch getFirestore
  const adminFirestore = require("firebase-admin/firestore");
  adminFirestore.getFirestore = firestoreMock;
});

afterEach(() => {
  resetMockData();
});

after(() => {
  test.cleanup();
});

// Import the function under test AFTER mocking
// We need to re-require to pick up the mock
let beforeSignIn;
before(() => {
  // Clear require cache to pick up mocked getFirestore
  delete require.cache[require.resolve("../index")];
  const functions = require("../index");
  beforeSignIn = test.wrap(functions.beforeSignIn);
});

describe("Auth Blocking Function", () => {
  // ABF-2: 未登録ユーザー拒否
  describe("未登録ユーザー", () => {
    it("whitelist/allowedDomains どちらにもマッチしないユーザーを拒否する", async () => {
      setupTenant("279", {
        whitelist: [{ email: "allowed@example.com", role: "member" }],
        allowedDomains: ["example.com"],
      });

      try {
        await beforeSignIn({ data: { email: "unknown@other.com" } });
        assert.fail("Should have thrown");
      } catch (e) {
        assert.ok(e.message.includes("許可されていません"));
      }
    });

    it("テナントが存在しない場合も拒否する", async () => {
      // No tenants set up
      try {
        await beforeSignIn({ data: { email: "anyone@example.com" } });
        assert.fail("Should have thrown");
      } catch (e) {
        assert.ok(e.message.includes("許可されていません"));
      }
    });
  });

  // ABF-3: allowedDomains 経由サインイン
  describe("allowedDomains", () => {
    it("ドメインマッチで member role の claims を返す", async () => {
      setupTenant("279", {
        whitelist: [],
        allowedDomains: ["279279.net"],
      });

      const result = await beforeSignIn({
        data: { email: "newuser@279279.net" },
      });
      assert.deepStrictEqual(result, {
        customClaims: { tenantId: "279", role: "member" },
      });
    });
  });

  // ABF-3: whitelist 経由サインイン
  describe("whitelist", () => {
    it("ホワイトリスト登録ユーザーは指定された role で claims を返す", async () => {
      setupTenant("279", {
        whitelist: [{ email: "admin@279279.net", role: "admin" }],
        allowedDomains: [],
      });

      const result = await beforeSignIn({
        data: { email: "admin@279279.net" },
      });
      assert.deepStrictEqual(result, {
        customClaims: { tenantId: "279", role: "admin" },
      });
    });

    it("whitelist は allowedDomains より優先される", async () => {
      setupTenant("279", {
        whitelist: [{ email: "special@279279.net", role: "admin" }],
        allowedDomains: ["279279.net"],
      });

      const result = await beforeSignIn({
        data: { email: "special@279279.net" },
      });
      assert.deepStrictEqual(result, {
        customClaims: { tenantId: "279", role: "admin" },
      });
    });
  });

  // ABF-5: 大文字小文字正規化
  describe("大文字小文字正規化", () => {
    it("大文字メールが正規化されてマッチする", async () => {
      setupTenant("279", {
        whitelist: [{ email: "user@example.com", role: "member" }],
        allowedDomains: [],
      });

      const result = await beforeSignIn({
        data: { email: "User@Example.COM" },
      });
      assert.deepStrictEqual(result, {
        customClaims: { tenantId: "279", role: "member" },
      });
    });

    it("allowedDomains も大文字小文字を無視する", async () => {
      setupTenant("279", {
        whitelist: [],
        allowedDomains: ["Example.COM"],
      });

      const result = await beforeSignIn({
        data: { email: "user@example.com" },
      });
      assert.deepStrictEqual(result, {
        customClaims: { tenantId: "279", role: "member" },
      });
    });
  });

  // ABF-6: email 空/undefined
  describe("email 空・undefined", () => {
    it("email が空文字の場合はエラー", async () => {
      try {
        await beforeSignIn({ data: { email: "" } });
        assert.fail("Should have thrown");
      } catch (e) {
        assert.ok(e.message.includes("メールアドレスが取得できません"));
      }
    });

    it("email が undefined の場合はエラー", async () => {
      try {
        await beforeSignIn({ data: {} });
        assert.fail("Should have thrown");
      } catch (e) {
        assert.ok(e.message.includes("メールアドレスが取得できません"));
      }
    });
  });

  // ABF-8: role 未設定フォールバック
  describe("role フォールバック", () => {
    it("whitelist entry に role がない場合 member にフォールバック", async () => {
      setupTenant("279", {
        whitelist: [{ email: "norole@example.com" }],
        allowedDomains: [],
      });

      const result = await beforeSignIn({
        data: { email: "norole@example.com" },
      });
      assert.deepStrictEqual(result, {
        customClaims: { tenantId: "279", role: "member" },
      });
    });
  });
});
