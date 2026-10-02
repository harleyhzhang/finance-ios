import Foundation

struct Account: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let institution: String
    let category: String
    let currency: String
    let amountMinor: Int64
    let note: String
    let asOf: String
    var valuation: EquityValuation? = nil
    var amount: Double { Double(amountMinor) / 100 }
}
struct HistoryValue: Codable, Equatable {
    let date: String
    let totalMinor: Int64
    let currency: String
    let source: String
}
struct Snapshot: Codable, Equatable {
    let schemaVersion: Int
    let capturedAt: String
    let asOf: String
    let cadPerUSD: String
    let fxAsOf: String
    let accounts: [Account]
    let history: [HistoryValue]
    let notes: [String]
    var rate: Decimal { Decimal(string: cadPerUSD, locale: Locale(identifier: "en_US_POSIX")) ?? 1 }
    var totalUSD: Double { accounts.reduce(0) { $0 + usd($1) } }
    func usd(_ account: Account) -> Double { converted(minor: account.amountMinor, from: account.currency, to: "USD") }
    func converted(minor: Int64, from: String, to: String) -> Double {
        let native = Decimal(minor) / 100
        let value = from == to ? native : (from == "CAD" ? native / rate : native * rate)
        return NSDecimalNumber(decimal: value).doubleValue
    }
    static func date(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return date
    }
    static func decode(_ data: Data) throws -> Snapshot {
        guard data.count <= 500_000 else { throw SnapshotError.invalid }
        let result = try JSONDecoder().decode(Snapshot.self, from: data)
        try result.validate()
        return result
    }
    func validate() throws {
        let currencies = ["CAD", "USD"]
        let categories = ["Cash", "Family investments", "Investments", "Business funds", "Credit cards", "RSUs"]
        guard schemaVersion == 2, Self.date(asOf) != nil, Self.date(fxAsOf) != nil, fxAsOf <= asOf, asOf <= String(capturedAt.prefix(10)),
              ISO8601DateFormatter.fractional.date(from: capturedAt) != nil,
              cadPerUSD.range(of: #"^\d+(\.\d+)?$"#, options: .regularExpression) != nil,
              let rate = Decimal(string: cadPerUSD), rate > 0, rate < 100,
              !accounts.isEmpty, accounts.count <= 100,
              Set(accounts.map(\.id)).count == accounts.count,
              accounts.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty && currencies.contains($0.currency) && categories.contains($0.category) && ($0.category != "Credit cards" || $0.amountMinor <= 0) && $0.amountMinor > -1_000_000_000_000 && $0.amountMinor < 1_000_000_000_000 && Self.date($0.asOf) != nil && $0.asOf <= asOf }),
              history.count <= 10_000,
              history.allSatisfy({ Self.date($0.date) != nil && $0.date <= asOf && currencies.contains($0.currency) && !$0.source.isEmpty && $0.totalMinor > -1_000_000_000_000 && $0.totalMinor < 1_000_000_000_000 }),
              Set(history.map(\.date)).count == history.count,
              history.map(\.date) == history.map(\.date).sorted()
        else { throw SnapshotError.invalid }
        for account in accounts {
            if account.category == "RSUs" {
                guard let valuation = account.valuation, account.currency == "USD",
                      try valuation.amountMinor(asOf: account.asOf) == account.amountMinor else { throw SnapshotError.invalid }
            } else if account.valuation != nil { throw SnapshotError.invalid }
        }
    }
}
enum SnapshotError: Error { case invalid, noConnection, unauthorized, unavailable, invalidResponse, rollback }
extension ISO8601DateFormatter {
    static var fractional: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
