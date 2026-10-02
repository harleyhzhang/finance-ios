import test from "node:test";
import assert from "node:assert/strict";
import {
  equityMinor,
  estimateRSUs,
  type EquityValuation,
} from "../Tools/equity.ts";
import { validateSnapshot, type Snapshot } from "../Tools/snapshot.ts";
const valuation: EquityValuation = {
  policy: "forge-service-vested-v1",
  provider: "Forge",
  priceUsdMinor: 12345,
  priceAsOf: "2026-09-21",
  priceSourceURL: "https://forgeglobal.com/example_stock/",
  awardedUnits: 400,
  serviceVestedUnits: 100,
  settledUnits: 20,
  unitsAsOf: "2026-09-22",
  unitsSourceURL: "https://app.carta.com/example",
  shareBasis: "issuer-reference-price-proxy",
};
test("count only service-vested unsettled RSUs, using exact cents", () => {
  assert.equal(equityMinor(valuation, "2026-09-22"), 987600);
  assert.equal(
    equityMinor({ ...valuation, serviceVestedUnits: 20 }, "2026-09-22"),
    0,
  );
});
test("reject alternate source, wrong dates, fractional units, oversettlement and overflow", () => {
  for (const change of [
    { provider: "Hiive" },
    { priceSourceURL: "https://forgeglobal.com.evil.test/example_stock/" },
    { priceAsOf: "2026-09-23" },
    { unitsAsOf: "2026-02-30" },
    { serviceVestedUnits: 100.5 },
    { settledUnits: 101 },
    { priceUsdMinor: Number.MAX_SAFE_INTEGER },
  ])
    assert.throws(() =>
      equityMinor({ ...valuation, ...change } as EquityValuation, "2026-09-22"),
    );
});
test("snapshot requires auditable valuation and rejects hand-entered mismatches", () => {
  const account = estimateRSUs({
    id: "rsus-example",
    name: "Example RSUs",
    institution: "Example",
    asOf: "2026-09-22",
    valuation,
  });
  const s: Snapshot = {
    schemaVersion: 2,
    capturedAt: "2026-09-22T12:00:00.000Z",
    asOf: "2026-09-22",
    cadPerUSD: "1.25",
    fxAsOf: "2026-09-21",
    accounts: [account],
    history: [],
    notes: [],
  };
  validateSnapshot(s);
  s.accounts[0].amountMinor++;
  assert.throws(() => validateSnapshot(s));
  s.accounts[0].amountMinor--;
  delete s.accounts[0].valuation;
  assert.throws(() => validateSnapshot(s));
});
