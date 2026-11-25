import test from "node:test";
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import {
  encrypt,
  decrypt,
  validateSnapshot,
  type Snapshot,
} from "../Tools/snapshot.ts";
export const fixture: Snapshot = {
  schemaVersion: 2,
  capturedAt: "2026-09-22T12:00:00.000Z",
  asOf: "2026-09-22",
  cadPerUSD: "1.25",
  fxAsOf: "2026-09-21",
  accounts: [
    {
      id: "example",
      name: "Example",
      institution: "Example",
      category: "Cash",
      currency: "CAD",
      amountMinor: 12500,
      note: "Synthetic",
      asOf: "2026-09-22",
    },
  ],
  history: [
    {
      date: "2026-01-01",
      totalMinor: 10000,
      currency: "CAD",
      source: "Synthetic test",
    },
  ],
  notes: [],
};
test("encrypt/decrypt preserves integer money; ciphertext changes per encryption", () => {
  const key = randomBytes(32);
  const one = encrypt(fixture, key),
    two = encrypt(fixture, key);
  assert.deepEqual(decrypt(one.envelope, key), fixture);
  assert.notEqual(one.digest, two.digest);
  assert.throws(() => decrypt(one.envelope, randomBytes(32)));
  const e = JSON.parse(one.envelope);
  const b = Buffer.from(e.combined, "base64");
  b[15] ^= 1;
  e.combined = b.toString("base64");
  assert.throws(() => decrypt(JSON.stringify(e), key));
});
test("reject invalid currency, fractional money, duplicate dates, future source and noncanonical FX", () => {
  for (const modify of [
    (s: Snapshot) => {
      s.accounts[0].currency = "EUR";
    },
    (s: Snapshot) => {
      s.accounts[0].amountMinor = 1.25;
    },
    (s: Snapshot) => {
      s.history.push(s.history[0]);
    },
    (s: Snapshot) => {
      s.accounts[0].asOf = "2026-09-23";
    },
    (s: Snapshot) => {
      s.cadPerUSD = "1.2bad";
    },
    (s: Snapshot) => {
      s.asOf = "2026-02-30";
    },
  ]) {
    const s = structuredClone(fixture);
    modify(s);
    assert.throws(() => validateSnapshot(s));
  }
});

test("chunked history: unchanged months seal identically and reassemble exactly", async () => {
  const { encryptChunked, assembleChunked, decrypt } = await import("../Tools/snapshot.ts");
  const key = Buffer.alloc(32, 7);
  const base = JSON.parse(JSON.stringify(chunkFixture));
  const first = encryptChunked(base, key);
  assert.equal(first.chunks.length, 2);
  const head = decrypt(first.envelope, key);
  assert.deepEqual(head.history, []);
  assert.deepEqual(assembleChunked(head, first.chunks, key), base);
  // A new point in the latest month changes only that month's chunk.
  const next = JSON.parse(JSON.stringify(base));
  next.history.push({ date: "2026-09-21", totalMinor: 300, currency: "CAD", source: "synthetic" });
  const second = encryptChunked(next, key);
  assert.equal(second.chunks[0].digest, first.chunks[0].digest);
  assert.notEqual(second.chunks[1].digest, first.chunks[1].digest);
  assert.throws(() => assembleChunked(decrypt(second.envelope, key), first.chunks, key));
});
const chunkFixture = {
  schemaVersion: 2,
  capturedAt: "2026-09-22T12:00:00.000Z",
  asOf: "2026-09-22",
  cadPerUSD: "1.25",
  fxAsOf: "2026-09-21",
  accounts: [
    { id: "cash", name: "Example", institution: "Example", category: "Cash", currency: "CAD", amountMinor: 12500, note: "Synthetic", asOf: "2026-09-22" },
  ],
  history: [
    { date: "2026-08-01", totalMinor: 100, currency: "CAD", source: "synthetic" },
    { date: "2026-09-01", totalMinor: 200, currency: "CAD", source: "synthetic" },
  ],
  notes: [],
};
