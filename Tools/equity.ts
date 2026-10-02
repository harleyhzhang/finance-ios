import type { Account } from "./snapshot.ts";

/** Pinned personal valuation policy. Never silently switch the mark to Hiive/409A. */
export type EquityValuation = {
  policy: "forge-service-vested-v1";
  provider: "Forge";
  priceUsdMinor: number;
  priceAsOf: string;
  priceSourceURL: string;
  awardedUnits: number;
  serviceVestedUnits: number;
  settledUnits: number;
  unitsAsOf: string;
  unitsSourceURL: string;
  shareBasis: "issuer-reference-price-proxy";
};
const day = (s: string) =>
  /^\d{4}-\d{2}-\d{2}$/.test(s) &&
  Number.isFinite(Date.parse(s)) &&
  new Date(s).toISOString().slice(0, 10) === s;
export function equityMinor(v: EquityValuation, asOf: string): number {
  if (
    !v ||
    !day(asOf) ||
    v.policy !== "forge-service-vested-v1" ||
    v.provider !== "Forge" ||
    v.shareBasis !== "issuer-reference-price-proxy" ||
    !Number.isSafeInteger(v.priceUsdMinor) ||
    v.priceUsdMinor <= 0 ||
    !day(v.priceAsOf) ||
    !day(v.unitsAsOf) ||
    v.priceAsOf > asOf ||
    v.unitsAsOf > asOf ||
    !/^https:\/\/forgeglobal\.com\/[a-z0-9-]+_stock\/$/.test(
      v.priceSourceURL,
    ) ||
    !/^https:\/\/app\.carta\.com\//.test(v.unitsSourceURL)
  )
    throw Error("invalid_equity_provenance");
  for (const n of [v.awardedUnits, v.serviceVestedUnits, v.settledUnits])
    if (!Number.isSafeInteger(n) || n < 0) throw Error("invalid_equity_units");
  if (
    v.settledUnits > v.serviceVestedUnits ||
    v.serviceVestedUnits > v.awardedUnits
  )
    throw Error("invalid_equity_units");
  const amount = (v.serviceVestedUnits - v.settledUnits) * v.priceUsdMinor;
  if (!Number.isSafeInteger(amount) || amount >= 1e12)
    throw Error("invalid_equity_value");
  return amount;
}
export function estimateRSUs(input: {
  id: string;
  name: string;
  institution: string;
  asOf: string;
  valuation: EquityValuation;
}): Account {
  return {
    ...input,
    category: "RSUs",
    currency: "USD",
    amountMinor: equityMinor(input.valuation, input.asOf),
    note: "Gross illiquid estimate: service-vested, unsettled units × dated Forge Price. Unvested units excluded. Issuer reference-price proxy, not tax/409A FMV or an executable common-share bid. Liquidity trigger remains required; taxes/fees are not deducted. See valuation metadata and docs/equity-valuation.md.",
  };
}
