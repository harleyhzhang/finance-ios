import Foundation

struct HistoryProjection {
    static func points(snapshot: Snapshot, currency: String, period: Period) -> [ChartPoint] {
        guard let end = Snapshot.date(snapshot.asOf) else { return [] }
        var values = snapshot.history.compactMap { item -> ChartPoint? in
            guard let date = Snapshot.date(item.date) else { return nil }
            return ChartPoint(id: Int(date.timeIntervalSince1970), date: date,
                              value: snapshot.converted(minor: item.totalMinor, from: item.currency, to: currency))
        }
        let current = snapshot.accounts.reduce(0.0) { $0 + snapshot.converted(minor: $1.amountMinor, from: $1.currency, to: currency) }
        values.removeAll { $0.date == end }
        values.append(ChartPoint(id: Int(end.timeIntervalSince1970), date: end, value: current))
        values.sort { $0.date < $1.date }
        if period == .all { return values }
        let start = period.startDate(ending: end)
        let previous = values.last { $0.date <= start }
        var selected = values.filter { $0.date >= start }
        if let previous, !selected.contains(where: { $0.id == previous.id }) { selected.insert(previous, at: 0) }
        return selected
    }
    static func domain(_ points: [ChartPoint]) -> ClosedRange<Double> {
        let low = points.map(\.value).min() ?? 0
        let high = points.map(\.value).max() ?? 0
        let padding = max((high-low)*0.08, max(abs(high)*0.005, 1))
        return (low-padding)...(high+padding)
    }
}
