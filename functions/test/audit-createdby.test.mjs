import { strict as assert } from "node:assert";
import { auditCreatedBy } from "../scripts/audit-createdby.mjs";

// Firestore REST API returns documents as `{ name, fields }`. Tests forge just
// enough structure for auditCreatedBy to walk — tenant docs only need `name`.

function tenantDoc(tenantId) {
  return { name: `projects/test/databases/(default)/documents/tenants/${tenantId}` };
}

function recordingDoc(fields) {
  return {
    name: `projects/test/databases/(default)/documents/recordings/rec-${Math.random()}`,
    fields,
  };
}

function silent() {
  /* noop logger */
}

describe("audit-createdby: auditCreatedBy", () => {
  it("aggregates per-tenant summaries across all tenants on success", async () => {
    const store = {
      tenants: [tenantDoc("t1"), tenantDoc("t2")],
      "tenants/t1/recordings": [
        recordingDoc({ createdBy: { stringValue: "uid-a" } }),
        recordingDoc({ createdBy: { stringValue: "" } }),
      ],
      "tenants/t2/recordings": [recordingDoc({ createdBy: { stringValue: "uid-b" } })],
    };
    const listDocuments = async (path) => store[path] || [];

    const result = await auditCreatedBy({ listDocuments, log: silent, warn: silent });

    assert.equal(result.failedTenants.length, 0);
    assert.equal(result.perTenant.length, 2);
    const t1 = result.perTenant.find((p) => p.tenantId === "t1");
    assert.equal(t1.empty, 1);
    assert.equal(t1.nonEmpty, 1);
    assert.equal(t1.total, 2);
    assert.equal(result.overall.total, 3);
    assert.equal(result.needsBackfill, 1);
  });

  it("records a failed tenant but preserves successful tenants' data", async () => {
    const store = {
      tenants: [tenantDoc("t1"), tenantDoc("t-fail"), tenantDoc("t3")],
      "tenants/t1/recordings": [recordingDoc({ createdBy: { stringValue: "u1" } })],
      "tenants/t3/recordings": [recordingDoc({ createdBy: { stringValue: "u3" } })],
    };
    const listDocuments = async (path) => {
      if (path === "tenants/t-fail/recordings") {
        throw new Error("HTTP 500 simulated");
      }
      return store[path] || [];
    };

    const result = await auditCreatedBy({ listDocuments, log: silent, warn: silent });

    assert.equal(result.failedTenants.length, 1);
    assert.equal(result.failedTenants[0].tenantId, "t-fail");
    assert.match(result.failedTenants[0].error, /HTTP 500/);
    assert.equal(result.perTenant.length, 3);

    const failEntry = result.perTenant.find((p) => p.tenantId === "t-fail");
    assert.ok(failEntry.error, "failed tenant entry must carry an `error` field");
    // Partial results from successful tenants must survive the failure.
    assert.equal(result.perTenant.find((p) => p.tenantId === "t1").nonEmpty, 1);
    assert.equal(result.perTenant.find((p) => p.tenantId === "t3").nonEmpty, 1);
    assert.equal(result.overall.nonEmpty, 2);
  });

  it("continues through multiple tenant failures and reports each in failedTenants", async () => {
    const listDocuments = async (path) => {
      if (path === "tenants") return [tenantDoc("t1"), tenantDoc("t2"), tenantDoc("t3")];
      if (path === "tenants/t1/recordings") throw new Error("HTTP 403 simulated");
      if (path === "tenants/t2/recordings") return [recordingDoc({ createdBy: { stringValue: "u2" } })];
      if (path === "tenants/t3/recordings") throw new Error("HTTP 500 simulated");
      return [];
    };

    const result = await auditCreatedBy({ listDocuments, log: silent, warn: silent });

    assert.equal(result.failedTenants.length, 2);
    assert.deepEqual(
      result.failedTenants.map((f) => f.tenantId).sort(),
      ["t1", "t3"]
    );
    assert.equal(result.overall.nonEmpty, 1);
  });

  it("counts missing createdBy fields toward needsBackfill", async () => {
    const store = {
      tenants: [tenantDoc("t1")],
      "tenants/t1/recordings": [recordingDoc({})],
    };
    const result = await auditCreatedBy({
      listDocuments: async (path) => store[path] || [],
      log: silent,
      warn: silent,
    });

    assert.equal(result.perTenant[0].missing, 1);
    assert.equal(result.needsBackfill, 1);
    assert.equal(result.failedTenants.length, 0);
  });

  it("returns a clean result when every recording has a non-empty createdBy", async () => {
    const store = {
      tenants: [tenantDoc("t1")],
      "tenants/t1/recordings": [recordingDoc({ createdBy: { stringValue: "u1" } })],
    };
    const result = await auditCreatedBy({
      listDocuments: async (path) => store[path] || [],
      log: silent,
      warn: silent,
    });

    assert.equal(result.needsBackfill, 0);
    assert.equal(result.failedTenants.length, 0);
    assert.equal(result.overall.nonEmpty, 1);
  });

  it("propagates an error from the initial tenants listing (pre-loop failure)", async () => {
    const listDocuments = async (path) => {
      if (path === "tenants") throw new Error("HTTP 403 no datastore.viewer");
      return [];
    };
    await assert.rejects(
      () => auditCreatedBy({ listDocuments, log: silent, warn: silent }),
      /HTTP 403/
    );
  });

  it("requires a listDocuments function", async () => {
    await assert.rejects(
      () => auditCreatedBy({ log: silent, warn: silent }),
      /listDocuments/
    );
  });
});
