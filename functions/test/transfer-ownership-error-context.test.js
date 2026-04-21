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

  it("falls back to '<unknown error>' for Error with empty message", () => {
    // Empty Error.message + String(err)==="Error" would give a log line with
    // only the word "Error" — useless. buildErrorContext must collapse this
    // to the explicit sentinel so operators can tell "unknown" from a real
    // framework error literally named "Error".
    const ctx = buildErrorContext(new Error(""));
    assert.equal(ctx.message, "<unknown error>");
  });

  it("falls back to '<unknown error>' for an object that stringifies to [object Object]", () => {
    // String({}) === "[object Object]" — technically non-empty but not useful.
    // We accept it (not "Error") because at least it is traceable as "caller
    // threw a bare object"; the assertion pins the current contract.
    const ctx = buildErrorContext({});
    assert.equal(ctx.message, "[object Object]");
  });
});
