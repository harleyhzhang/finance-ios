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
