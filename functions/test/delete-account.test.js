const assert = require("assert");
const functionsTest = require("firebase-functions-test");

const test = functionsTest();

let mockFirestoreData = {};
let deletedDocs = [];
let deletedStorageFiles = [];
let deletedUids = [];

function resetState() {
  mockFirestoreData = {};
  deletedDocs = [];
  deletedStorageFiles = [];
  deletedUids = [];
}

before(() => {
  function createDocRef(path) {
    return {
      collection: (subPath) => createCollectionRef(`${path}/${subPath}`),
      delete: async () => {
        deletedDocs.push(path);
        delete mockFirestoreData[path];
      },
    };
  }

  function createCollectionRef(path) {
    return {
      doc: (id) => createDocRef(`${path}/${id}`),
      where: (field, _op, value) => ({
        get: async () => {
          const prefix = path + "/";
          const docs = Object.entries(mockFirestoreData)
            .filter(([key, data]) => {
              if (!key.startsWith(prefix)) return false;
              const rel = key.slice(prefix.length);
              // Only direct children: reject deeper subcollection paths
              // (e.g. "recordings/r1/comments/c1" must not match a query on
              // "tenants/279/recordings"). See Issue #104.
              if (rel.includes("/")) return false;
              return data[field] === value;
            })
            .map(([key, data]) => ({
              id: key.split("/").pop(),
              data: () => data,
              ref: createDocRef(key),
            }));
          return { docs };
        },
      }),
    };
  }

  const firestoreMock = () => ({
    collection: (path) => createCollectionRef(path),
  });

  const adminFirestore = require("firebase-admin/firestore");
  adminFirestore.getFirestore = firestoreMock;

  const adminStorage = require("firebase-admin/storage");
  adminStorage.getStorage = () => ({
    bucket: (name) => ({
      file: (path) => ({
        delete: async () => {
          deletedStorageFiles.push(`${name}/${path}`);
        },
      }),
    }),
  });

  const adminAuth = require("firebase-admin/auth");
  adminAuth.getAuth = () => ({
    deleteUser: async (uid) => {
      deletedUids.push(uid);
    },
  });
});

afterEach(() => {
  resetState();
});

after(() => {
  test.cleanup();
});

let deleteAccount;
before(() => {
  delete require.cache[require.resolve("../index")];
  const functions = require("../index");
  deleteAccount = test.wrap(functions.deleteAccount);
});

describe("deleteAccount Callable Function", () => {
  it("caller の createdBy と一致する recording を削除し、Storage audio と Auth user を削除する", async () => {
    mockFirestoreData["tenants/279/recordings/r1"] = {
      createdBy: "alice",
      audioStoragePath: "gs://audio-bucket/279/r1.m4a",
    };
    mockFirestoreData["tenants/279/recordings/r2"] = {
      createdBy: "alice",
      audioStoragePath: "gs://audio-bucket/279/r2.m4a",
    };
    mockFirestoreData["tenants/279/recordings/r3"] = {
      createdBy: "bob",
      audioStoragePath: "gs://audio-bucket/279/r3.m4a",
    };

    const result = await deleteAccount({
      auth: { uid: "alice", token: { tenantId: "279" } },
      data: {},
    });

    assert.deepStrictEqual(result, { success: true });
    assert.deepStrictEqual(deletedDocs.sort(), [
      "tenants/279/recordings/r1",
      "tenants/279/recordings/r2",
    ]);
    assert.deepStrictEqual(deletedStorageFiles.sort(), [
      "audio-bucket/279/r1.m4a",
      "audio-bucket/279/r2.m4a",
    ]);
    assert.deepStrictEqual(deletedUids, ["alice"]);
    assert.ok("tenants/279/recordings/r3" in mockFirestoreData, "bob の録音は残る");
  });

  it("createdBy が空文字の既存データは削除されない（issue #99 regression）", async () => {
    mockFirestoreData["tenants/279/recordings/r1"] = {
      createdBy: "",
      audioStoragePath: "gs://audio-bucket/279/r1.m4a",
    };
    mockFirestoreData["tenants/279/recordings/r2"] = {
      createdBy: "",
      audioStoragePath: "gs://audio-bucket/279/r2.m4a",
    };

    const result = await deleteAccount({
      auth: { uid: "alice", token: { tenantId: "279" } },
      data: {},
    });

    assert.deepStrictEqual(result, { success: true });
    assert.deepStrictEqual(deletedDocs, [], "createdBy が空文字の録音は uid='alice' クエリにヒットしない");
    assert.deepStrictEqual(deletedStorageFiles, []);
    assert.deepStrictEqual(deletedUids, ["alice"], "Auth user は常に削除される");
  });

  it("recording 0件でも Auth user 削除は走る", async () => {
    const result = await deleteAccount({
      auth: { uid: "carol", token: { tenantId: "279" } },
      data: {},
    });

    assert.deepStrictEqual(result, { success: true });
    assert.deepStrictEqual(deletedDocs, []);
    assert.deepStrictEqual(deletedStorageFiles, []);
    assert.deepStrictEqual(deletedUids, ["carol"]);
  });

  it("audioStoragePath が gs:// でない場合は Storage 削除をスキップして継続", async () => {
    mockFirestoreData["tenants/279/recordings/r1"] = {
      createdBy: "alice",
      audioStoragePath: "https://invalid-url/file.m4a",
    };

    const result = await deleteAccount({
      auth: { uid: "alice", token: { tenantId: "279" } },
      data: {},
    });

    assert.deepStrictEqual(result, { success: true });
    assert.deepStrictEqual(deletedDocs, ["tenants/279/recordings/r1"], "Firestore 削除は実行される");
    assert.deepStrictEqual(deletedStorageFiles, [], "parseできない gs URI は Storage 削除されない");
    assert.deepStrictEqual(deletedUids, ["alice"]);
  });

  it("サブコレクション配下のドキュメントは recordings クエリで拾われない (Issue #104 regression)", async () => {
    mockFirestoreData["tenants/279/recordings/r1"] = {
      createdBy: "alice",
      audioStoragePath: "gs://audio-bucket/279/r1.m4a",
    };
    // 深いサブコレクションに alice の createdBy を持つ別ドキュメント。
    // 直下 recordings のクエリで拾ってはならない。
    mockFirestoreData["tenants/279/recordings/r1/comments/c1"] = {
      createdBy: "alice",
      audioStoragePath: "gs://audio-bucket/279/r1-c1.m4a",
    };

    const result = await deleteAccount({
      auth: { uid: "alice", token: { tenantId: "279" } },
      data: {},
    });

    assert.deepStrictEqual(result, { success: true });
    assert.deepStrictEqual(
      deletedDocs,
      ["tenants/279/recordings/r1"],
      "直下の r1 のみ削除。サブコレクション配下の c1 は対象外"
    );
    assert.deepStrictEqual(
      deletedStorageFiles,
      ["audio-bucket/279/r1.m4a"],
      "Storage も直下 r1 の audio のみ削除"
    );
    assert.ok(
      "tenants/279/recordings/r1/comments/c1" in mockFirestoreData,
      "サブコレクション配下のドキュメントは残存"
    );
    assert.deepStrictEqual(deletedUids, ["alice"]);
  });

  it("未認証で呼び出されると unauthenticated エラー", async () => {
    try {
      await deleteAccount({ auth: null, data: {} });
      assert.fail("Should have thrown");
    } catch (e) {
      assert.ok(e.message.includes("ログイン"), `unexpected: ${e.message}`);
    }
  });

  it("tenantId claim がない場合は failed-precondition エラー", async () => {
    try {
      await deleteAccount({
        auth: { uid: "alice", token: {} },
        data: {},
      });
      assert.fail("Should have thrown");
    } catch (e) {
      assert.ok(e.message.includes("セッション情報が不完全"), `unexpected: ${e.message}`);
    }
  });

  it("recordings query が失敗しても Auth user 削除は走る (C-Cdx-3)", async () => {
    // Monkey-patch: where().get() を reject させる
    const adminFirestore = require("firebase-admin/firestore");
    const originalGetFirestore = adminFirestore.getFirestore;
    adminFirestore.getFirestore = () => ({
      collection: () => ({
        doc: () => ({
          collection: () => ({
            where: () => ({
              get: async () => {
                const err = new Error("PERMISSION_DENIED");
                err.code = 7;
                throw err;
              },
            }),
          }),
        }),
      }),
    });

    try {
      const result = await deleteAccount({
        auth: { uid: "alice", token: { tenantId: "279" } },
        data: {},
      });
      assert.deepStrictEqual(result, { success: true });
      assert.deepStrictEqual(deletedDocs, [], "query 失敗時は削除対象ゼロ扱い");
      assert.deepStrictEqual(deletedStorageFiles, []);
      assert.deepStrictEqual(deletedUids, ["alice"], "Auth user は削除される (App Store 5.1.1(v))");
    } finally {
      adminFirestore.getFirestore = originalGetFirestore;
    }
  });
});
