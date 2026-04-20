import { strict as assert } from "node:assert";
import { isEmptyCreatedBy, parseGsUri } from "../scripts/delete-empty-createdby.mjs";

describe("delete-empty-createdby: isEmptyCreatedBy", () => {
  it("treats missing createdBy field as empty (legacy data)", () => {
    assert.equal(isEmptyCreatedBy({}), true);
  });

  it("treats explicit empty stringValue as empty", () => {
    assert.equal(isEmptyCreatedBy({ createdBy: { stringValue: "" } }), true);
  });

  it("treats nullValue as empty", () => {
    assert.equal(isEmptyCreatedBy({ createdBy: { nullValue: null } }), true);
  });

  it("treats value object without stringValue/nullValue as populated (safe default)", () => {
    assert.equal(isEmptyCreatedBy({ createdBy: {} }), false);
  });

  it("CRITICAL: treats any non-empty stringValue as populated (never delete real uid)", () => {
    assert.equal(isEmptyCreatedBy({ createdBy: { stringValue: "uid-abc" } }), false);
    assert.equal(isEmptyCreatedBy({ createdBy: { stringValue: "0" } }), false);
    assert.equal(isEmptyCreatedBy({ createdBy: { stringValue: "   " } }), false);
  });

  it("treats unknown value types as populated (refuse to delete)", () => {
    assert.equal(isEmptyCreatedBy({ createdBy: { integerValue: "42" } }), false);
    assert.equal(isEmptyCreatedBy({ createdBy: { mapValue: { fields: {} } } }), false);
    assert.equal(isEmptyCreatedBy({ createdBy: { booleanValue: false } }), false);
  });

  it("tolerates nullish fields argument", () => {
    assert.equal(isEmptyCreatedBy(null), true);
    assert.equal(isEmptyCreatedBy(undefined), true);
  });
});

describe("delete-empty-createdby: parseGsUri", () => {
  it("returns null for non-string inputs", () => {
    assert.equal(parseGsUri(undefined), null);
    assert.equal(parseGsUri(null), null);
    assert.equal(parseGsUri(123), null);
    assert.equal(parseGsUri({}), null);
  });

  it("returns null for empty string and non-gs schemes", () => {
    assert.equal(parseGsUri(""), null);
    assert.equal(parseGsUri("http://example.com/x.m4a"), null);
    assert.equal(parseGsUri("https://example.com/x.m4a"), null);
    assert.equal(parseGsUri("file:///tmp/x.m4a"), null);
  });

  it("returns null for bucket-only or empty object paths", () => {
    assert.equal(parseGsUri("gs://"), null);
    assert.equal(parseGsUri("gs://bucket"), null);
    assert.equal(parseGsUri("gs://bucket/"), null);
    assert.equal(parseGsUri("gs:///object"), null);
  });

  it("parses a standard gs URI", () => {
    assert.deepEqual(parseGsUri("gs://my-bucket/path/to/file.m4a"), {
      bucket: "my-bucket",
      object: "path/to/file.m4a",
    });
  });

  it("preserves multi-segment object paths", () => {
    assert.deepEqual(parseGsUri("gs://carenote-dev-279-audio/279/UUID.m4a"), {
      bucket: "carenote-dev-279-audio",
      object: "279/UUID.m4a",
    });
  });

  it("preserves non-ASCII object paths", () => {
    assert.deepEqual(parseGsUri("gs://bucket/テスト/音声.m4a"), {
      bucket: "bucket",
      object: "テスト/音声.m4a",
    });
  });
});
