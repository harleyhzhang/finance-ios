import test from "node:test";
import assert from "node:assert/strict";
import { equalHash, nextRevision, validateEnvelope } from "../convex/policy.ts";
const envelope = JSON.stringify({
  version: 1,
  algorithm: "AES-256-GCM",
  combined: Buffer.alloc(80, 1).toString("base64"),
});
const digest = "a".repeat(64),
  time = "2026-01-01T12:00:00.000Z";
test("only exact configured token hash is authorized", () => {
  assert.equal(equalHash(digest, digest), true);
  assert.equal(equalHash(digest, "b".repeat(64)), false);
  assert.equal(equalHash("", ""), false);
});
test("reject plaintext, malformed, oversized snapshot envelopes", () => {
  validateEnvelope(envelope, digest, time);
  assert.throws(() => validateEnvelope('{"balance":100}', digest, time));
  assert.throws(() => validateEnvelope("a".repeat(750001), digest, time));
  assert.throws(() => validateEnvelope(envelope, "bad", time));
  assert.throws(() => validateEnvelope(envelope, digest, "yesterday"));
});
test("optimistic concurrency and stale capture guard", () => {
  assert.equal(nextRevision(null, 0, time), 1);
  assert.equal(nextRevision({ revision: 1, capturedAt: time }, 1, time), 2);
  assert.throws(() => nextRevision({ revision: 2, capturedAt: time }, 1, time));
  assert.throws(() =>
    nextRevision(
      { revision: 1, capturedAt: time },
      1,
      "2025-01-01T00:00:00.000Z",
    ),
  );
});
