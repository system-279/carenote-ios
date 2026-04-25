const assert = require("assert");
const functionsTest = require("firebase-functions-test");

const test = functionsTest();

// ---- Mock state ----
let storageDeleteCalls = [];
let storageDeleteFailureMode = null; // null | { code, message }
let consoleWarnCalls = [];
let consoleErrorCalls = [];
let consoleInfoCalls = [];

const originalConsole = {
  warn: console.warn,
  error: console.error,
  info: console.info,
};

function resetState() {
  storageDeleteCalls = [];
  storageDeleteFailureMode = null;
  consoleWarnCalls = [];
  consoleErrorCalls = [];
  consoleInfoCalls = [];
}

function installConsoleSpies() {
  console.warn = (...args) => {
    consoleWarnCalls.push(args);
  };
  console.error = (...args) => {
    consoleErrorCalls.push(args);
  };
  console.info = (...args) => {
    consoleInfoCalls.push(args);
  };
}

function restoreConsole() {
  console.warn = originalConsole.warn;
  console.error = originalConsole.error;
  console.info = originalConsole.info;
}

// ---- Admin SDK mock ----
//
// `delete-account.test.js` と同じ思想: getStorage / getFirestore / getAuth を
// 一度だけ差し替え、テスト本体は state と handler のみを切替える。
function initializeAdminMocks() {
  const adminStorage = require("firebase-admin/storage");
  adminStorage.getStorage = () => ({
    bucket: (name) => ({
      file: (path) => ({
        delete: async (opts) => {
          storageDeleteCalls.push({
            bucket: name,
            object: path,
            ignoreNotFound: opts?.ignoreNotFound === true,
          });
          if (storageDeleteFailureMode) {
            const err = new Error(storageDeleteFailureMode.message);
            err.code = storageDeleteFailureMode.code;
            throw err;
          }
        },
      }),
    }),
  });
}

// `before` フックは定義順に実行される。**順序必須**:
// 1. `initializeAdminMocks` で `getStorage` 等の SDK を差し替える
// 2. その後で `require("../index")` を実行 → handler closure が差し替え後の SDK を参照
// 順序を入れ替えると handler が production の getStorage を bind してしまい test が壊れる。
let handleRecordingDeleted;

before(() => {
  initializeAdminMocks();
  installConsoleSpies();
});

before(() => {
  delete require.cache[require.resolve("../index")];
  const functions = require("../index");
  handleRecordingDeleted = functions._handleRecordingDeleted;
});

afterEach(() => {
  resetState();
});

after(() => {
  restoreConsole();
  test.cleanup();
});

// ---- Helpers ----

/**
 * v2 `onDocumentDeleted` の event 互換オブジェクトを手で作る。
 *
 * `firebase-functions-test` の `makeDocumentSnapshot` は内部で `getFirestore()` を
 * 呼ぶため、`delete-account.test.js` 等で SDK mock が installed されている状態だと
 * `firestoreService.snapshot_ is not a function` で fail する。handler 側は
 * `event.data?.data()` と `event.params` しか参照しないため、最小互換のみ用意する。
 */
async function invokeTrigger({ data, tenantId, recordingId }) {
  await handleRecordingDeleted({
    data: { data: () => data },
    params: { tenantId, recordingId },
  });
}

// ---- Tests ----

describe("onRecordingDeleted Firestore trigger", () => {
  it("audioStoragePath が valid な gs:// URI の場合、bucket.file().delete() を ignoreNotFound:true で呼ぶ", async () => {
    await invokeTrigger({
      data: {
        createdBy: "alice",
        audioStoragePath: "gs://carenote-dev-279-audio/279/r1.m4a",
      },
      tenantId: "279",
      recordingId: "r1",
    });

    assert.deepStrictEqual(storageDeleteCalls, [
      {
        bucket: "carenote-dev-279-audio",
        object: "279/r1.m4a",
        ignoreNotFound: true,
      },
    ]);
  });

  it("audioStoragePath が undefined の場合は Storage を呼ばず no-op で完走する", async () => {
    await invokeTrigger({
      data: { createdBy: "alice" },
      tenantId: "279",
      recordingId: "r1",
    });

    assert.deepStrictEqual(storageDeleteCalls, []);
  });

  it("audioStoragePath が null の場合は Storage を呼ばず no-op で完走する", async () => {
    await invokeTrigger({
      data: { createdBy: "alice", audioStoragePath: null },
      tenantId: "279",
      recordingId: "r1",
    });

    assert.deepStrictEqual(storageDeleteCalls, []);
  });

  it("audioStoragePath が gs:// 形式でない場合は Storage を呼ばず error log で完走する", async () => {
    await invokeTrigger({
      data: {
        createdBy: "alice",
        audioStoragePath: "https://invalid-url/file.m4a",
      },
      tenantId: "279",
      recordingId: "r1",
    });

    assert.deepStrictEqual(storageDeleteCalls, []);
    // 不正 URI は data corruption / writer-side bug の signal なので error level
    const matched = consoleErrorCalls.find((args) =>
      typeof args[0] === "string" &&
      args[0].includes("[onRecordingDeleted] unparseable audioStoragePath")
    );
    assert.ok(matched, "error log が emit されるはず");
  });

  it("audioStoragePath が非 string (number / object) の場合は parseGsUri が null を返し error log で skip", async () => {
    await invokeTrigger({
      data: { createdBy: "alice", audioStoragePath: 42 },
      tenantId: "279",
      recordingId: "r1",
    });
    assert.deepStrictEqual(storageDeleteCalls, []);

    await invokeTrigger({
      data: { createdBy: "alice", audioStoragePath: { foo: "bar" } },
      tenantId: "279",
      recordingId: "r2",
    });
    assert.deepStrictEqual(storageDeleteCalls, []);

    // 両方とも error log で記録される
    const errorLogs = consoleErrorCalls.filter((args) =>
      typeof args[0] === "string" &&
      args[0].includes("[onRecordingDeleted] unparseable audioStoragePath")
    );
    assert.strictEqual(errorLogs.length, 2);
  });

  it("audioStoragePath が空文字列の場合は Storage を呼ばず no-op", async () => {
    await invokeTrigger({
      data: { createdBy: "alice", audioStoragePath: "" },
      tenantId: "279",
      recordingId: "r1",
    });

    assert.deepStrictEqual(storageDeleteCalls, []);
  });

  it("Storage delete が permission エラーで失敗しても trigger は throw しない (retry backoff 防止)", async () => {
    storageDeleteFailureMode = {
      code: "storage/unauthorized",
      message: "Permission denied",
    };

    // throw されないことを assert: rejects で false 検知
    await assert.doesNotReject(async () => {
      await invokeTrigger({
        data: {
          createdBy: "alice",
          audioStoragePath: "gs://carenote-dev-279-audio/279/r1.m4a",
        },
        tenantId: "279",
        recordingId: "r1",
      });
    });

    // Storage は1回呼ばれた上で error をのみ込んだ
    assert.strictEqual(storageDeleteCalls.length, 1);
    // failure は error log で観測可能でなければならない (silent failure 禁止)
    const matched = consoleErrorCalls.find((args) =>
      typeof args[0] === "string" &&
      args[0].includes("[onRecordingDeleted] storage delete failed (orphan possible)")
    );
    assert.ok(matched, "error log が emit されるはず");
  });

  it("Storage delete が generic エラーで失敗しても trigger は throw しない", async () => {
    storageDeleteFailureMode = {
      code: undefined,
      message: "network unreachable",
    };

    await assert.doesNotReject(async () => {
      await invokeTrigger({
        data: {
          createdBy: "alice",
          audioStoragePath: "gs://carenote-dev-279-audio/279/r1.m4a",
        },
        tenantId: "279",
        recordingId: "r1",
      });
    });

    assert.strictEqual(storageDeleteCalls.length, 1);
  });

  it("複数回連続で trigger 発火しても各々独立に処理される (冪等性確認)", async () => {
    await invokeTrigger({
      data: {
        createdBy: "alice",
        audioStoragePath: "gs://carenote-dev-279-audio/279/r1.m4a",
      },
      tenantId: "279",
      recordingId: "r1",
    });
    await invokeTrigger({
      data: {
        createdBy: "bob",
        audioStoragePath: "gs://carenote-dev-279-audio/279/r2.m4a",
      },
      tenantId: "279",
      recordingId: "r2",
    });

    assert.strictEqual(storageDeleteCalls.length, 2);
    assert.strictEqual(storageDeleteCalls[0].object, "279/r1.m4a");
    assert.strictEqual(storageDeleteCalls[1].object, "279/r2.m4a");
  });
});
