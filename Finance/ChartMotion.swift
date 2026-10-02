import SwiftUI

/// A chart vertex in normalized time: 0 is the first point, 1 the last.
struct PlotPoint: Identifiable, Equatable { let id: Int; let position: Double; let value: Double }

enum ChartMorph {
    static let spring = Spring(duration: 0.52, bounce: 0)
    static var duration: Double { spring.settlingDuration(target: 1.0, epsilon: 0.001) }

    static func plotted(_ points: [ChartPoint]) -> [PlotPoint] {
        guard let first = points.first?.date, let last = points.last?.date else { return [] }
        let span = last.timeIntervalSince(first)
        return points.enumerated().map { index, point in
            let position = span > 0 ? point.date.timeIntervalSince(first) / span : Double(index) / Double(max(points.count - 1, 1))
            return PlotPoint(id: index, position: position, value: point.value)
        }
    }

    /// Samples both linear curves at the union of their vertices, so the first frame is exactly the
    /// old chart, the last frame is exactly the new one, and no peak is cut off in between.
    static func points(from source: [PlotPoint], to target: [PlotPoint], progress: Double) -> [PlotPoint] {
        guard !source.isEmpty, !target.isEmpty else { return target }
        let positions = Array(Set(source.map(\.position) + target.map(\.position))).sorted()
        return positions.enumerated().map { index, position in
            let from = value(at: position, in: source)
            return PlotPoint(id: index, position: position, value: from + (value(at: position, in: target) - from) * progress)
        }
    }

    static func domain(from source: ClosedRange<Double>, to target: ClosedRange<Double>, progress: Double) -> ClosedRange<Double> {
        let lower = source.lowerBound + (target.lowerBound - source.lowerBound) * progress
        let upper = source.upperBound + (target.upperBound - source.upperBound) * progress
        return lower...max(upper, lower)
    }

    static func progress(elapsed: Double) -> Double {
        elapsed >= duration ? 1 : min(max(spring.value(target: 1.0, time: elapsed), 0), 1)
    }

    static func value(at position: Double, in points: [PlotPoint]) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if position <= first.position { return first.value }
        if position >= last.position { return last.value }
        let upper = points.firstIndex { $0.position >= position } ?? points.count - 1
        let a = points[upper - 1], b = points[upper]
        let width = b.position - a.position
        return width > 0 ? a.value + (b.value - a.value) * (position - a.position) / width : b.value
    }

    /// Binary search for the vertex closest to a normalized position.
    static func nearestIndex(to position: Double, in points: [PlotPoint]) -> Int {
        var low = 0, high = points.count - 1
        while low < high {
            let mid = (low + high) / 2
            if points[mid].position < position { low = mid + 1 } else { high = mid }
        }
        if low > 0, position - points[low - 1].position < points[low].position - position { return low - 1 }
        return low
    }
}

extension Period {
    /// Offer a window only once history fills it, and All only when it shows more than the longest
    /// window offered — e.g. a year of history shows 1Y but not an identical All.
    static func available(history: [ChartPoint]) -> [Period] {
        guard let first = history.first?.date, let end = history.last?.date else { return [.all] }
        let slack: TimeInterval = 3 * 86_400
        let windows = allCases.filter { $0 != .all && first <= $0.startDate(ending: end).addingTimeInterval(slack) }
        let earliestWindow = windows.map { $0.startDate(ending: end) }.min() ?? end
        return first < earliestWindow.addingTimeInterval(-slack) ? windows + [.all] : windows
    }
}
