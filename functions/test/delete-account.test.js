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

// ---- Mock handler injection ----
//
// index.js は `const { getAuth } = require("firebase-admin/auth")` のように
// destructure してロード時に関数参照を固定する。mock 関数自体を差し替えても
// 再ロードしない限り反映されないため、**mock 関数は固定のまま handler を
// 動的に差し替えられる** 構造にする。`installMocks({ ... })` は handler だけ
// 更新し、mock 関数本体は `initializeAdminMocks()` が最初の before() で1度だけ設置する。

let _handlers = {};

/**
 * Mock ハンドラを差し替える（mock 関数本体は固定）。
 *
 * @param {object} [opts]
 * @param {(path:string)=>Promise<void>|void} [opts.onDocDelete]   — doc.ref.delete() の挙動を差し替え
 * @param {(bucket:string, path:string)=>Promise<void>|void} [opts.onFileDelete]
 *                                                                — storage.bucket().file().delete() の挙動を差し替え
 * @param {(uid:string)=>Promise<void>|void} [opts.onDeleteUser]   — auth.deleteUser() の挙動を差し替え
 * @param {(collectionPath:string)=>Promise<{docs:Array}>} [opts.onRecordingsQuery]
 *                                                                — where().get() の挙動を差し替え（collection フルパス受領）
 */
function installMocks(opts = {}) {
  _handlers = opts;
}

function initializeAdminMocks() {
  function createDocRef(path) {
    return {
      collection: (subPath) => createCollectionRef(`${path}/${subPath}`),
      delete: async () => {
        if (_handlers.onDocDelete) {
          await _handlers.onDocDelete(path);
        }
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
          if (_handlers.onRecordingsQuery) {
            return _handlers.onRecordingsQuery(path);
          }
          const docs = Object.entries(mockFirestoreData)
            .filter(([key, data]) => {
              if (!key.startsWith(path + "/")) return false;
              const rel = key.slice(path.length + 1);
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
          if (_handlers.onFileDelete) {
            await _handlers.onFileDelete(name, path);
          }
          deletedStorageFiles.push(`${name}/${path}`);
        },
      }),
    }),
  });

  const adminAuth = require("firebase-admin/auth");
  adminAuth.getAuth = () => ({
    deleteUser: async (uid) => {
      if (_handlers.onDeleteUser) {
        await _handlers.onDeleteUser(uid);
      }
      deletedUids.push(uid);
    },
  });
}

before(() => {
  initializeAdminMocks();
});

afterEach(() => {
  resetState();
  // mock handlers を default (no-op) に戻し、テスト間で差し込みが引き継がないよう保証。
  installMocks({});
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

  it("深いサブコレクションを where でヒットさせない（issue #104 regression）", async () => {
    mockFirestoreData["tenants/279/recordings/r1"] = {
      createdBy: "alice",
      audioStoragePath: "gs://audio-bucket/279/r1.m4a",
    };
    mockFirestoreData["tenants/279/recordings/r1/comments/c1"] = {
      createdBy: "alice",
      text: "nested doc — must NOT be returned by where()",
    };
    mockFirestoreData["tenants/279/recordings/r1/attachments/a1"] = {
      createdBy: "alice",
      url: "gs://audio-bucket/279/r1/a1.txt",
    };

    const result = await deleteAccount({
      auth: { uid: "alice", token: { tenantId: "279" } },
      data: {},
    });

    assert.deepStrictEqual(result, { success: true });
    assert.deepStrictEqual(
      deletedDocs,
      ["tenants/279/recordings/r1"],
      "直下 recording のみ削除対象（サブコレクションは where 結果に含めない）"
    );
    assert.ok(
      "tenants/279/recordings/r1/comments/c1" in mockFirestoreData,
      "サブコレクション docs は削除対象に含まれない"
    );
    assert.ok(
      "tenants/279/recordings/r1/attachments/a1" in mockFirestoreData,
      "サブコレクション docs は削除対象に含まれない"
    );
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

  // ---- #102: branch coverage for partial-failure paths and auth error codes ----

  it("Firestore doc.delete が reject しても Auth user 削除は走る (Promise.allSettled 固定)", async () => {
    mockFirestoreData["tenants/279/recordings/r1"] = {
      createdBy: "alice",
      audioStoragePath: "gs://audio-bucket/279/r1.m4a",
    };

    installMocks({
      onDocDelete: async (path) => {
        const err = new Error("firestore delete failed");
        err.code = 13; // INTERNAL
        throw err;
      },
    });

    const result = await deleteAccount({
      auth: { uid: "alice", token: { tenantId: "279" } },
      data: {},
    });

    assert.deepStrictEqual(result, { success: true });
    assert.deepStrictEqual(deletedUids, ["alice"], "doc.delete 失敗時も Auth user は削除される");
  });

  it("Storage file.delete が reject しても Auth user 削除は走る", async () => {
    mockFirestoreData["tenants/279/recordings/r1"] = {
      createdBy: "alice",
      audioStoragePath: "gs://audio-bucket/279/r1.m4a",
    };

    installMocks({
      onFileDelete: async () => {
        const err = new Error("storage delete failed");
        err.code = 500;
        throw err;
      },
    });

    const result = await deleteAccount({
      auth: { uid: "alice", token: { tenantId: "279" } },
      data: {},
    });

    assert.deepStrictEqual(result, { success: true });
    assert.deepStrictEqual(deletedUids, ["alice"], "file.delete 失敗時も Auth user は削除される");
  });

  it("auth/user-not-found の場合は alreadyDeleted=true で success を返す", async () => {
    installMocks({
      onDeleteUser: async () => {
        const err = new Error("auth user not found");
        err.code = "auth/user-not-found";
        throw err;
      },
    });

    const result = await deleteAccount({
      auth: { uid: "ghost", token: { tenantId: "279" } },
      data: {},
    });

    assert.deepStrictEqual(result, { success: true, alreadyDeleted: true });
    assert.deepStrictEqual(deletedUids, [], "deleteUser は throw したので記録されない");
  });

  it("auth/requires-recent-login は failed-precondition + requiresReauth:true を返す", async () => {
    installMocks({
      onDeleteUser: async () => {
        const err = new Error("recent login required");
        err.code = "auth/requires-recent-login";
        throw err;
      },
    });

    try {
      await deleteAccount({
        auth: { uid: "alice", token: { tenantId: "279" } },
        data: {},
      });
      assert.fail("Should have thrown");
    } catch (e) {
      assert.strictEqual(e.code, "failed-precondition");
      assert.deepStrictEqual(e.details, { requiresReauth: true });
    }
  });

  it("その他の auth エラー (auth/internal-error 等) は internal + phase:'auth-delete' を返す", async () => {
    installMocks({
      onDeleteUser: async () => {
        const err = new Error("auth internal error");
        err.code = "auth/internal-error";
        throw err;
      },
    });

    try {
      await deleteAccount({
        auth: { uid: "alice", token: { tenantId: "279" } },
        data: {},
      });
      assert.fail("Should have thrown");
    } catch (e) {
      assert.strictEqual(e.code, "internal");
      assert.deepStrictEqual(e.details, { phase: "auth-delete" });
    }
  });

  // ---- end #102 ----

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
