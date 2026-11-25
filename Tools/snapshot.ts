import { equityMinor, type EquityValuation } from "./equity.ts";
import {
  createCipheriv,
  createDecipheriv,
  createHash,
  createHmac,
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
export type HistoryChunkRef = { month: string; digest: string };
export type Snapshot = {
  schemaVersion: 2;
  /** Present on chunked heads: history lives in sealed monthly chunks. */
  historyChunks?: HistoryChunkRef[];
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
  if (
    s.historyChunks !== undefined &&
    (!Array.isArray(s.historyChunks) ||
      s.history.length !== 0 ||
      s.historyChunks.some(
        (c, i, all) =>
          !/^\d{4}-\d{2}$/.test(c.month) ||
          !/^[a-f0-9]{64}$/.test(c.digest) ||
          (i > 0 && all[i - 1].month >= c.month),
      ))
  )
    throw Error("invalid_history_chunks");
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

/** Sealed month of history. The nonce is derived from the key and plaintext,
 * so an unchanged month always seals to the same bytes and digest: a publish
 * uploads only months that changed, never the whole growing history again. */
export type SealedChunk = { month: string; digest: string; envelope: string };
export function sealChunk(
  month: string,
  points: History[],
  key: Buffer,
): SealedChunk {
  if (key.length !== 32) throw Error("invalid_key");
  if (!/^\d{4}-\d{2}$/.test(month) || points.some((p) => !p.date.startsWith(month + "-")))
    throw Error("invalid_chunk_month");
  const clear = JSON.stringify({ month, history: points });
  const nonce = createHmac("sha256", key)
    .update("finance-history-chunk-v1\0" + clear)
    .digest()
    .subarray(0, 12);
  const cipher = createCipheriv("aes-256-gcm", key, nonce);
  const combined = Buffer.concat([
    nonce,
    cipher.update(clear, "utf8"),
    cipher.final(),
    cipher.getAuthTag(),
  ]);
  return {
    month,
    digest: createHash("sha256").update(combined).digest("hex"),
    envelope: JSON.stringify({
      version: 1,
      algorithm: "AES-256-GCM",
      combined: combined.toString("base64"),
    }),
  };
}
export function openChunk(chunk: SealedChunk, key: Buffer): History[] {
  const e = JSON.parse(chunk.envelope);
  const b = Buffer.from(e.combined, "base64");
  if (createHash("sha256").update(b).digest("hex") !== chunk.digest)
    throw Error("chunk_digest_mismatch");
  const decipher = createDecipheriv("aes-256-gcm", key, b.subarray(0, 12));
  decipher.setAuthTag(b.subarray(-16));
  const clear = JSON.parse(
    Buffer.concat([decipher.update(b.subarray(12, -16)), decipher.final()]).toString("utf8"),
  );
  if (clear.month !== chunk.month) throw Error("chunk_month_mismatch");
  return clear.history as History[];
}
/** Head (accounts, rates, chunk references) plus one sealed chunk per month. */
export function encryptChunked(snapshot: Snapshot, key: Buffer) {
  validateSnapshot(snapshot);
  const months = new Map<string, History[]>();
  for (const point of snapshot.history) {
    const month = point.date.slice(0, 7);
    months.set(month, [...(months.get(month) ?? []), point]);
  }
  const chunks = [...months].map(([month, points]) => sealChunk(month, points, key));
  const head: Snapshot = {
    ...snapshot,
    history: [],
    historyChunks: chunks.map(({ month, digest }) => ({ month, digest })),
  };
  return { ...encrypt(head, key), chunks };
}
export function assembleChunked(head: Snapshot, chunks: SealedChunk[], key: Buffer): Snapshot {
  const byDigest = new Map(chunks.map((c) => [c.digest, c]));
  const history = (head.historyChunks ?? []).flatMap((ref) => {
    const chunk = byDigest.get(ref.digest);
    if (!chunk || chunk.month !== ref.month) throw Error("missing_history_chunk");
    return openChunk(chunk, key);
  });
  const { historyChunks: _, ...rest } = head;
  const full = { ...rest, history };
  validateSnapshot(full);
  return full;
}
