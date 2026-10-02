import { validateSnapshot, type Snapshot } from "./snapshot.ts";

/** Parses one CSV line, allowing double-quoted fields with commas and "" escapes. */
function cells(line: string): string[] {
  const out: string[] = [];
  let cur = "",
    quoted = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (quoted && c === '"' && line[i + 1] === '"') (cur += '"'), i++;
    else if (c === '"') quoted = !quoted;
    else if (c === "," && !quoted) out.push(cur), (cur = "");
    else cur += c;
  }
  return [...out, cur].map((c) => c.trim());
}

function rows(text: string): Record<string, string>[] {
  const lines = text.split(/\r?\n/).filter((l) => l.trim());
  if (!lines.length) return [];
  const header = cells(lines[0]);
  return lines.slice(1).map((l) => {
    const values = cells(l);
    return Object.fromEntries(header.map((h, i) => [h, values[i] ?? ""]));
  });
}

/** "1,234.56" or "-12.5" to integer cents without floating-point rounding. */
export function toMinor(amount: string): number {
  const clean = amount.replace(/[$,\s]/g, "");
  const match = clean.match(/^(-?)(\d+)(?:\.(\d{1,2}))?$/);
  if (!match) throw Error(`invalid_amount: ${amount}`);
  const cents = Number(match[2]) * 100 + Number((match[3] ?? "").padEnd(2, "0"));
  return match[1] ? -cents : cents;
}

/**
 * Builds a validated snapshot from two simple CSVs.
 * accounts: id,name,institution,category,currency,amount,asOf[,note]
 * history:  date,total,currency[,source]
 */
export function snapshotFromCSV(
  accountsCSV: string,
  historyCSV: string,
  cadPerUSD: string,
  now = new Date(),
): Snapshot {
  const accounts = rows(accountsCSV).map((r) => ({
    id: r.id,
    name: r.name,
    institution: r.institution ?? "",
    category: r.category,
    currency: r.currency.toUpperCase(),
    amountMinor: toMinor(r.amount),
    asOf: r.asOf,
    note: r.note ?? "",
  }));
  const asOf = accounts.map((a) => a.asOf).sort().at(-1) ?? "";
  const history = rows(historyCSV)
    .map((r) => ({
      date: r.date,
      totalMinor: toMinor(r.total),
      currency: r.currency.toUpperCase(),
      source: r.source || "CSV import",
    }))
    .sort((a, b) => a.date.localeCompare(b.date));
  const snapshot: Snapshot = {
    schemaVersion: 2,
    capturedAt: now.toISOString(),
    asOf,
    cadPerUSD,
    fxAsOf: asOf,
    accounts,
    history,
    notes: [],
  };
  validateSnapshot(snapshot);
  return snapshot;
}
