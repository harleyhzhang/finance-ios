#if DEBUG
import Foundation

/// Synthetic data for screenshots and development. Launch with `FINANCE_DEMO_DATA=1`.
enum DemoSnapshot {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["FINANCE_DEMO_DATA"] == "1" }

    static func make() -> Snapshot {
        let asOf = "2026-09-30"
        let end = Snapshot.date(asOf)!
        let accounts = [
            account("chequing", "Chequing", "Cash", "CAD", 1_284_500),
            account("savings", "High-interest savings", "Cash", "CAD", 2_150_000),
            account("tfsa", "TFSA", "Investments", "CAD", 4_812_300),
            account("brokerage", "Brokerage", "Investments", "USD", 3_067_900),
            account("card", "Credit card", "Credit cards", "CAD", -184_200),
        ]
        let history = (1...104).reversed().map { week -> HistoryValue in
            let date = end.addingTimeInterval(-Double(week) * 7 * 86_400)
            let t = Double(104 - week)
            let value = 6_350_000 + t * 56_000 + sin(t / 5) * 180_000 + sin(t / 1.7) * 60_000
            return HistoryValue(date: Format.isoDay(date), totalMinor: Int64(value), currency: "CAD", source: "Demo")
        }
        return Snapshot(schemaVersion: 2, capturedAt: "2026-09-30T12:00:00.000Z", asOf: asOf, cadPerUSD: "1.36",
                        fxAsOf: asOf, accounts: accounts, history: history, notes: ["Synthetic demo data."])
    }

    private static func account(_ id: String, _ name: String, _ category: String, _ currency: String, _ minor: Int64) -> Account {
        Account(id: id, name: name, institution: "Demo", category: category, currency: currency, amountMinor: minor, note: "", asOf: "2026-09-30")
    }
}

private extension Format {
    static func isoDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
#endif
