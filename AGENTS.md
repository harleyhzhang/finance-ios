# Finance

Single-user, read-only net-worth viewer. Read README.md and docs/ first.

- **Privacy:** real balances, profiles, keys, screenshots of real data and `Config/Local.xcconfig` never go in Git. Use synthetic fixtures. Private output paths must sit outside the repo.
- **Scope:** no bank clients, scraping, background refresh, polling or analytics. The phone only reads. Publishing is a deliberate CLI step.
- **Data:** money crosses boundaries as integer minor units, and FX uses the snapshot's dated rate. Never invent history points. Validate before saving, and keep the last good cache on error.
- **UI:** one dark page with no tabs. Use `Theme` for every font, color and spacing value: SF Rounded, greys plus green for gains and red for losses, and system controls. Keep views small and pass models down rather than many props. Chart morph and scrub behavior live in `ChartMotion.swift` and `NetWorthChart.swift`. Keep scrubbing cheap.
- **Build:** `project.yml` is the source of truth; run `xcodegen generate` after edits. Run `npm run verify` before you finish. CI is manual-dispatch only.
