# Snapshot data

A snapshot is a complete replacement, not a patch. Money is stored as signed integer minor units (cents), and debt is negative.

```json
{
  "schemaVersion": 2,
  "capturedAt": "2026-09-30T12:00:00.000Z",
  "asOf": "2026-09-30",
  "cadPerUSD": "1.36",
  "fxAsOf": "2026-09-30",
  "accounts": [
    {"id":"chequing","name":"Chequing","institution":"Example Bank","category":"Cash","currency":"CAD","amountMinor":1284500,"asOf":"2026-09-30","note":""}
  ],
  "history": [
    {"date":"2026-08-31","totalMinor":8057000,"currency":"CAD","source":"Monthly statement"}
  ],
  "notes": []
}
```

- **Categories:** `Cash`, `Business funds`, `Investments`, `Family investments`, `Credit cards`, `RSUs`. The breakdown merges Business funds into Cash and Family investments into Investments.
- **Currencies:** each account keeps its native USD or CAD amount. Conversion uses the snapshot's explicit `cadPerUSD` rate, never a live rate.
- **Dates:** account dates and history dates cannot be after `asOf`. History is strictly ascending, with one point per date.
- **Limits:** 100 accounts, 10,000 history points, 500 KB.

## CSV import

`from-csv` reads two files. Amounts are decimal strings, such as `-1842.00`.

- `accounts.csv`: `id,name,institution,category,currency,amount,asOf,note`
- `history.csv`: `date,total,currency,source`

See [`examples/`](../examples). History is optional; pass `-` to skip it.

## Chart

The chart draws straight lines between recorded points and never interpolates new observations. The final point is today's account total. The change shown is net-worth change, so it includes deposits and debt, not investment return.

## RSUs

An `RSUs` account needs a `valuation` object containing the unit price, its source and date, and the vested and settled unit counts. The amount must equal the vested unsettled units times the price. `node Tools/finance.ts estimate-rsus input.json out.json` builds and checks that object; see `Tools/equity.ts` for the fields.
