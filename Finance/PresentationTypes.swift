import SwiftUI

/// How accounts are grouped on screen. Presentation only; snapshots keep each account's own category.
enum AssetGroup: String, CaseIterable, Identifiable {
    case cash = "Cash", investments = "Investments", debt = "Credit cards", rsus = "RSUs"
    func includes(category: String) -> Bool {
        category == rawValue || (self == .cash && category == "Business funds") || (self == .investments && category == "Family investments")
    }
    var id: String { rawValue }
    var symbol: String {
        switch self { case .cash: "banknote.fill"; case .investments: "chart.bar.fill"; case .debt: "creditcard.fill"; case .rsus: "lock.rectangle.stack.fill" }
    }
    var color: Color {
        switch self { case .cash: .green; case .investments: .cyan; case .debt: .red; case .rsus: .blue }
    }
}

struct GroupTotal: Identifiable, Equatable {
    let group: AssetGroup
    let total: Double
    var id: AssetGroup.ID { group.id }
}

extension Snapshot {
    func total(in currency: String) -> Double {
        accounts.reduce(0) { $0 + converted(minor: $1.amountMinor, from: $1.currency, to: currency) }
    }
    /// Groups present in this snapshot, largest first, so liabilities sort last.
    func breakdown(in currency: String) -> [GroupTotal] {
        AssetGroup.allCases.compactMap { group -> GroupTotal? in
            let members = accounts.filter { group.includes(category: $0.category) }
            guard !members.isEmpty else { return nil }
            return GroupTotal(group: group, total: members.reduce(0) { $0 + converted(minor: $1.amountMinor, from: $1.currency, to: currency) })
        }
        .sorted { $0.total == $1.total ? $0.group.rawValue < $1.group.rawValue : $0.total > $1.total }
    }
}

enum Period: String, CaseIterable, Identifiable {
    case month = "1M", sixMonths = "6M", ytd = "YTD", year = "1Y", all = "ALL"
    var id: String { rawValue }
    var label: String { self == .all ? "All" : rawValue }
    var title: String { switch self { case .month: "1 month"; case .sixMonths: "6 months"; case .ytd: "Year to date"; case .year: "1 year"; case .all: "All time" } }
    func startDate(ending end: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        switch self {
        case .month: return calendar.date(byAdding: .month, value: -1, to: end) ?? end
        case .sixMonths: return calendar.date(byAdding: .month, value: -6, to: end) ?? end
        case .ytd: return calendar.date(from: calendar.dateComponents([.year], from: end)) ?? end
        case .year: return calendar.date(byAdding: .year, value: -1, to: end) ?? end
        case .all: return calendar.date(byAdding: .year, value: -2, to: end) ?? end
        }
    }
}
struct ChartPoint: Identifiable { let id: Int; let date: Date; let value: Double }
