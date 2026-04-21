"use strict";

const assert = require("assert");
const { _internals } = require("../src/transferOwnership");

const { buildErrorContext } = _internals;

// UUIDv4 shape used by crypto.randomUUID().
const UUID_V4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

describe("transferOwnership: buildErrorContext", () => {
  it("generates a fresh errorId per call", () => {
    const a = buildErrorContext(new Error("x"));
    const b = buildErrorContext(new Error("x"));
    assert.notStrictEqual(a.errorId, b.errorId, "errorId must be unique per invocation");
    assert.match(a.errorId, UUID_V4);
    assert.match(b.errorId, UUID_V4);
  });

  it("preserves Error message, code, and stack", () => {
    const err = Object.assign(new Error("boom"), { code: "failed-precondition" });
    const ctx = buildErrorContext(err);
    assert.equal(ctx.code, "failed-precondition");
    assert.equal(ctx.message, "boom");
    assert.ok(ctx.stack, "stack must be retained for Cloud Logging forensics");
    assert.ok(ctx.stack.includes("boom"), "stack should include the original message");
  });

  it("defaults code to 'internal' when err has no code", () => {
    const ctx = buildErrorContext(new Error("no code"));
    assert.equal(ctx.code, "internal");
  });

  it("ignores a non-string code (defensive against unknown error shapes)", () => {
    const ctx = buildErrorContext(Object.assign(new Error("x"), { code: 500 }));
    assert.equal(ctx.code, "internal");
  });

  it("stringifies non-Error throw values safely", () => {
    const ctx = buildErrorContext("raw string err");
    assert.equal(ctx.message, "raw string err");
    assert.equal(ctx.stack, null);
    assert.equal(ctx.code, "internal");
    assert.match(ctx.errorId, UUID_V4);
  });

  it("handles null / undefined without throwing", () => {
    for (const value of [null, undefined]) {
      const ctx = buildErrorContext(value);
      assert.equal(ctx.message, "<unknown error>");
      assert.equal(ctx.stack, null);
      assert.equal(ctx.code, "internal");
      assert.match(ctx.errorId, UUID_V4);
    }
  });

  it("treats empty-string message as unknown (avoids silent empty logs)", () => {
    const err = new Error("");
    const ctx = buildErrorContext(err);
    // Empty Error.message falls back to String(err) which is "Error".
    // What we guard against is a completely blank message making the log
    // entry useless — "Error" is at least parseable.
    assert.ok(ctx.message.length > 0, "message must never be empty");
  });
});
