import SwiftUI

/// Allocation bar plus one static row per asset group, largest first.
struct BreakdownCard: View {
    let rows: [GroupTotal]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Breakdown").font(Theme.section).padding(.horizontal, 2)
            VStack(spacing: 22) {
                AllocationBar(segments: rows.filter { $0.group != .debt && $0.total > 0 })
                ForEach(rows) { row in
                    HStack(spacing: 12) {
                        Image(systemName: row.group.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(row.group.color).frame(width: 23)
                        Text(row.group.rawValue).font(Theme.label)
                        Spacer(minLength: 4)
                        Text(Format.money(row.total)).font(Theme.number(.body)).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(18)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
    }
}

private struct AllocationBar: View {
    let segments: [GroupTotal]
    private let gap: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            let assets = max(segments.reduce(0) { $0 + $1.total }, 1)
            let width = geometry.size.width - CGFloat(max(segments.count - 1, 0)) * gap
            HStack(spacing: gap) {
                ForEach(segments) { segment in
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(segment.group.color)
                        .frame(width: max(0, width * segment.total / assets))
                }
            }
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }
}
