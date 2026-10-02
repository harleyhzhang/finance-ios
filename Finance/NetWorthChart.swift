import SwiftUI
import Charts

struct ChartMorphState: Equatable { let points: [PlotPoint]; let domain: ClosedRange<Double>; let start: Date }

/// The line and area. Scrubbing never changes its inputs, so SwiftUI skips re-rendering the
/// hundreds of marks while a finger moves; only `ChartSelectionOverlay` redraws.
struct NetWorthPlot: View, Equatable {
    let target: [PlotPoint]
    let domain: ClosedRange<Double>
    let morph: ChartMorphState?
    let showsLatestMarker: Bool
    let selection: Binding<Double?>
    let onPlotFrame: (CGRect) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.target == rhs.target && lhs.domain == rhs.domain && lhs.morph == rhs.morph && lhs.showsLatestMarker == rhs.showsLatestMarker
    }

    var body: some View {
        TimelineView(.animation(paused: morph == nil)) { context in
            let progress = morph.map { ChartMorph.progress(elapsed: context.date.timeIntervalSince($0.start)) } ?? 1
            let plot = morph.map { ChartMorph.points(from: $0.points, to: target, progress: progress) } ?? target
            let domain = morph.map { ChartMorph.domain(from: $0.domain, to: self.domain, progress: progress) } ?? self.domain
            Chart {
                ForEach(plot) { point in
                    AreaMark(x: .value("Time", point.position), yStart: .value("Baseline", domain.lowerBound), yEnd: .value("Net worth", point.value))
                        .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.22), Theme.accent.opacity(0)], startPoint: .top, endPoint: .bottom)).interpolationMethod(.linear)
                    LineMark(x: .value("Time", point.position), y: .value("Net worth", point.value))
                        .foregroundStyle(Theme.accent).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)).interpolationMethod(.linear)
                }
                if showsLatestMarker, let last = plot.last {
                    PointMark(x: .value("Time", last.position), y: .value("Net worth", last.value)).foregroundStyle(Theme.accent).symbolSize(25)
                }
            }
            .chartXScale(domain: 0...1)
            .chartYScale(domain: domain)
            .chartXAxis(.hidden).chartYAxis(.hidden).chartXSelection(value: selection)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    let frame = proxy.plotFrame.map { geometry[$0] } ?? CGRect(origin: .zero, size: geometry.size)
                    Color.clear
                        .onAppear { onPlotFrame(frame) }
                        .onChange(of: frame) { _, frame in onPlotFrame(frame) }
                }
            }
        }
        .transaction { $0.animation = nil }
    }
}

/// The scrub rule and dot, drawn directly from the plot frame.
struct ChartSelectionOverlay: View {
    let point: PlotPoint?
    let domain: ClosedRange<Double>
    let plotFrame: CGRect

    var body: some View {
        if let point, plotFrame.width > 0 {
            let x = plotFrame.minX + point.position * plotFrame.width
            let span = domain.upperBound - domain.lowerBound
            let y = plotFrame.maxY - (span > 0 ? (point.value - domain.lowerBound) / span : 0.5) * plotFrame.height
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: x, y: plotFrame.minY))
                    path.addLine(to: CGPoint(x: x, y: plotFrame.maxY))
                }.stroke(Theme.rule, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                Circle().fill(Theme.accent).frame(width: 5.6, height: 5.6).position(x: x, y: y)
            }
            .allowsHitTesting(false)
        }
    }
}

/// Start and end dates at rest; while scrubbing, the selected date sits under the finger.
struct ChartDateRow: View {
    let start: String
    let end: String
    let selected: (label: String, position: Double)?
    let plotFrame: CGRect

    var body: some View {
        GeometryReader { geometry in
            if let selected {
                let width = plotFrame.width > 0 ? plotFrame.width : geometry.size.width
                let x = (plotFrame.width > 0 ? plotFrame.minX : 0) + selected.position * width
                Text(selected.label).fixedSize()
                    .position(x: min(max(x, 24), geometry.size.width - 24), y: geometry.size.height / 2)
            } else {
                HStack { Text(start); Spacer(); Text(end) }
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(height: 14)
        .font(Theme.caption).foregroundStyle(.secondary).monospacedDigit()
    }
}
