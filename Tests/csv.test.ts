import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { snapshotFromCSV, toMinor } from "../Tools/csv.ts";

test("amounts become exact integer cents", () => {
  assert.equal(toMinor("1,234.56"), 123456);
  assert.equal(toMinor("-12.5"), -1250);
  assert.equal(toMinor("$7"), 700);
  assert.throws(() => toMinor("1.234"));
});

test("example CSVs build a valid snapshot", () => {
  const s = snapshotFromCSV(
    readFileSync("examples/accounts.csv", "utf8"),
    readFileSync("examples/history.csv", "utf8"),
    "1.36",
    new Date("2026-09-30T12:00:00.000Z"),
  );
  assert.equal(s.asOf, "2026-09-30");
  assert.equal(s.accounts.length, 4);
  assert.ok(s.history.length > 0);
  assert.equal(s.accounts.find((a) => a.id === "card")?.amountMinor, -184200);
});

test("quoted fields keep their commas", () => {
  const s = snapshotFromCSV(
    'id,name,institution,category,currency,amount,asOf\ncash,"Savings, joint",Bank,Cash,CAD,"1,000.00",2026-01-01\n',
    "",
    "1.25",
    new Date("2026-01-02T00:00:00.000Z"),
  );
  assert.equal(s.accounts[0].name, "Savings, joint");
  assert.equal(s.accounts[0].amountMinor, 100000);
});
