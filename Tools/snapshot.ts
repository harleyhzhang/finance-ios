import { equityMinor, type EquityValuation } from "./equity.ts";
import {
  createCipheriv,
  createDecipheriv,
  createHash,
  randomBytes,
} from "node:crypto";
export type Account = {
  valuation?: EquityValuation;
  id: string;
  name: string;
  institution: string;
  category: string;
  currency: string;
  amountMinor: number;
  note: string;
  asOf: string;
};
export type History = {
  date: string;
  totalMinor: number;
  currency: string;
  source: string;
};
export type Snapshot = {
  schemaVersion: 2;
  capturedAt: string;
  asOf: string;
  cadPerUSD: string;
  fxAsOf: string;
  accounts: Account[];
  history: History[];
  notes: string[];
};
const day = (s: unknown): s is string =>
  typeof s === "string" &&
  /^\d{4}-\d{2}-\d{2}$/.test(s) &&
  Number.isFinite(Date.parse(s)) &&
  new Date(s).toISOString().slice(0, 10) === s;
const money = (n: unknown): n is number =>
  Number.isSafeInteger(n) && Math.abs(n as number) < 1e12;
const currencies = ["USD", "CAD"];
const categories = [
  "Cash",
  "Family investments",
  "Investments",
  "Business funds",
  "Credit cards",
  "RSUs",
];
export function validateSnapshot(value: unknown): asserts value is Snapshot {
  const s = value as Snapshot;
  if (
    !s ||
    s.schemaVersion !== 2 ||
    !day(s.asOf) ||
    !day(s.fxAsOf) ||
    s.fxAsOf > s.asOf ||
    typeof s.capturedAt !== "string" ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(s.capturedAt) ||
    !Number.isFinite(Date.parse(s.capturedAt)) ||
    new Date(s.capturedAt).toISOString() !== s.capturedAt ||
    s.asOf > s.capturedAt.slice(0, 10) ||
    !/^\d+(\.\d+)?$/.test(s.cadPerUSD) ||
    !(Number(s.cadPerUSD) > 0 && Number(s.cadPerUSD) < 100)
  )
    throw Error("invalid_snapshot_header");
  if (
    !Array.isArray(s.accounts) ||
    s.accounts.length < 1 ||
    s.accounts.length > 100 ||
    new Set(s.accounts.map((a) => a.id)).size !== s.accounts.length
  )
    throw Error("invalid_accounts");
  for (const a of s.accounts)
    if (
      !a.id ||
      !a.name ||
      typeof a.institution !== "string" ||
      typeof a.note !== "string" ||
      !categories.includes(a.category) ||
      !currencies.includes(a.currency) ||
      !money(a.amountMinor) ||
      !day(a.asOf) ||
      a.asOf > s.asOf ||
      (a.category === "Credit cards" && a.amountMinor > 0)
    )
      throw Error("invalid_account");
  for (const a of s.accounts) {
    if (a.category === "RSUs") {
      if (
        !a.valuation ||
        a.currency !== "USD" ||
        a.amountMinor !== equityMinor(a.valuation, a.asOf)
      )
        throw Error("equity_value_mismatch");
    } else if (a.valuation) throw Error("equity_metadata_on_other_category");
  }
  if (!Array.isArray(s.history) || s.history.length > 10000)
    throw Error("invalid_history");
  let last = "";
  for (const h of s.history) {
    if (
      !day(h.date) ||
      h.date <= last ||
      h.date > s.asOf ||
      !money(h.totalMinor) ||
      !currencies.includes(h.currency) ||
      !h.source
    )
      throw Error("invalid_history_point");
    last = h.date;
  }
  if (
    !Array.isArray(s.notes) ||
    s.notes.some((n) => typeof n !== "string") ||
    Buffer.byteLength(JSON.stringify(s)) > 500000
  )
    throw Error("invalid_snapshot_size_or_notes");
}
export function encrypt(snapshot: Snapshot, key: Buffer) {
  validateSnapshot(snapshot);
  if (key.length !== 32) throw Error("invalid_key");
  const nonce = randomBytes(12),
    cipher = createCipheriv("aes-256-gcm", key, nonce);
  const combined = Buffer.concat([
    nonce,
    cipher.update(JSON.stringify(snapshot), "utf8"),
    cipher.final(),
    cipher.getAuthTag(),
  ]);
  return {
    envelope: JSON.stringify({
      version: 1,
      algorithm: "AES-256-GCM",
      combined: combined.toString("base64"),
    }),
    digest: createHash("sha256").update(combined).digest("hex"),
    capturedAt: snapshot.capturedAt,
  };
}
export function decrypt(envelope: string, key: Buffer): Snapshot {
  const e = JSON.parse(envelope);
  if (e.version !== 1 || e.algorithm !== "AES-256-GCM")
    throw Error("invalid_envelope");
  const b = Buffer.from(e.combined, "base64"),
    decipher = createDecipheriv("aes-256-gcm", key, b.subarray(0, 12));
  decipher.setAuthTag(b.subarray(-16));
  const s = JSON.parse(
    Buffer.concat([
      decipher.update(b.subarray(12, -16)),
      decipher.final(),
    ]).toString("utf8"),
  );
  validateSnapshot(s);
  return s;
}
